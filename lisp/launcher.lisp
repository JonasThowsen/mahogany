(in-package #:mahogany)

;;; The launcher: menus for starting applications, running commands,
;;; going to windows and groups, and anything else a user adds as a
;;; mode. It is also the input method of interactive commands, in place
;;; of rofi.

;;; Modes

(defstruct (launcher-mode (:constructor %make-launcher-mode))
  (name nil :type keyword)
  (prompt "" :type string)
  (description "" :type string)
  ;; A function of no arguments returning the menu-items (or strings):
  (items nil :type function)
  ;; A function of the chosen item's data:
  (action nil :type function)
  ;; A function of typed text when nothing matched, or NIL to refuse:
  (text-action nil :type (or null function)))

(defglobal *launcher-modes* (make-hash-table)
  "The launcher's modes, by name.")

(defglobal *launcher-mode-order* '()
  "The modes in the order they were defined, for the top menu.")

(defun register-launcher-mode (name &key prompt description items action text-action)
  "Add, or replace, the launcher mode NAME. See define-launcher-mode."
  (check-type name keyword)
  (setf (gethash name *launcher-modes*)
        (%make-launcher-mode :name name
                             :prompt (or prompt (string-capitalize name))
                             :description (or description (string-capitalize name))
                             :items items
                             :action action
                             :text-action text-action))
  (unless (member name *launcher-mode-order*)
    (setf *launcher-mode-order* (append *launcher-mode-order* (list name))))
  name)

(defmacro define-launcher-mode (name (&key prompt description) &key items action text-action)
  "Define a launcher mode. NAME is a keyword. ITEMS is a form evaluated
when the menu opens, giving menu-items (make-menu-item) or strings.
ACTION is a function of the chosen item's data (or its label, for a
string item). TEXT-ACTION, when given, is a function of what was typed
when it matched nothing, so the mode accepts free text.

  (define-launcher-mode :projects (:prompt \"Project\" :description \"Open a project\")
    :items (mapcar (lambda (dir) (make-menu-item (file-namestring dir) :data dir))
                   (directory \"~/coding/*/\"))
    :action (lambda (dir) (uiop:launch-program (list \"foot\" \"-D\" (namestring dir)))))"
  `(register-launcher-mode ,name
                           :prompt ,prompt
                           :description ,description
                           :items (lambda () ,items)
                           :action ,action
                           :text-action ,text-action))

(defun launcher (&optional (mode-name :menu))
  "Open the launcher in the mode MODE-NAME (:menu lists the modes)."
  (let ((mode (gethash mode-name *launcher-modes*)))
    (unless mode
      (error 'mahogany/util:recoverable-error
             :text (format nil "No launcher mode ~S" mode-name)))
    (menu-open (menu-prompt-string (launcher-mode-prompt mode))
               (funcall (launcher-mode-items mode))
               :allow-text (not (null (launcher-mode-text-action mode)))
               :on-choose (lambda (choice)
                            (handler-case
                                (if (menu-item-p choice)
                                    (funcall (launcher-mode-action mode)
                                             (or (menu-item-data choice) (menu-item-label choice)))
                                    (funcall (launcher-mode-text-action mode) choice))
                              (error (c)
                                (toast-message *compositor-state*
                                               (format nil "~A: ~A" mode-name c)
                                               :theme *message-error-theme*)))))))

(defun menu-prompt-string (prompt)
  "PROMPT ending in a colon, as menus show it: \"Run\" and \"Run: \" both
give \"Run:\"."
  (let ((prompt (string-right-trim " " prompt)))
    (if (and (plusp (length prompt)) (char= (char prompt (1- (length prompt))) #\:))
        prompt
        (concatenate 'string prompt ":"))))

(defcommand launcher-menu ()
  (:documentation "Open the launcher's menu of modes")
  (:method () (launcher :menu)))

(defcommand launcher-apps ()
  (:documentation "Start an application")
  (:method () (launcher :apps)))

(defcommand launcher-commands ()
  (:documentation "Run a Mahogany command")
  (:method () (launcher :commands)))

(defcommand launcher-windows ()
  (:documentation "Go to a window")
  (:method () (launcher :windows)))

(defcommand launcher-groups ()
  (:documentation "Go to a group")
  (:method () (launcher :groups)))

(defcommand launcher-run ()
  (:documentation "Run a shell command")
  (:method () (launcher :run)))

(defcommand move-window-to-group-menu ()
  (:documentation "Move the current window to a group chosen from a menu")
  (:method () (launcher :move-to-group)))

;;; Applications: .desktop files

(defstruct (desktop-entry (:constructor make-desktop-entry (id name &key generic comment exec terminal keywords categories)))
  id name generic comment exec terminal keywords categories)

(defun %desktop-directories ()
  (append (list (uiop:xdg-data-home "applications/"))
          (mapcar (lambda (dir) (uiop:subpathname dir "applications/"))
                  (uiop:xdg-data-dirs))))

(defun %parse-desktop-file (file)
  "The desktop-entry of FILE, or NIL when it is not an application to show."
  (let ((in-entry nil) (fields (make-hash-table :test 'equal)))
    (with-open-file (stream file :external-format :utf-8 :if-does-not-exist nil)
      (unless stream (return-from %parse-desktop-file nil))
      (loop for line = (read-line stream nil)
            while line
            do (let ((line (string-trim '(#\Space #\Tab #\Return) line)))
                 (cond ((zerop (length line)))
                       ((char= (char line 0) #\#))
                       ((char= (char line 0) #\[)
                        (setf in-entry (string= line "[Desktop Entry]")))
                       (in-entry
                        (let ((eq (position #\= line)))
                          (when eq
                            (setf (gethash (string-right-trim " " (subseq line 0 eq)) fields)
                                  (string-left-trim " " (subseq line (1+ eq)))))))))))
    (flet ((field (name) (gethash name fields))
           (truep (value) (and value (string-equal value "true"))))
      (when (and (equal (field "Type") "Application")
                 (field "Name") (field "Exec")
                 (not (truep (field "NoDisplay")))
                 (not (truep (field "Hidden"))))
        (make-desktop-entry (pathname-name file) (field "Name")
                            :generic (field "GenericName")
                            :comment (field "Comment")
                            :exec (%strip-exec-field-codes (field "Exec"))
                            :terminal (truep (field "Terminal"))
                            :keywords (uiop:split-string (or (field "Keywords") "") :separator ";")
                            :categories (uiop:split-string (or (field "Categories") "") :separator ";"))))))

(defun %strip-exec-field-codes (exec)
  "EXEC without the %f %u ... placeholders of the desktop entry spec."
  (with-output-to-string (out)
    (loop with i = 0
          while (< i (length exec))
          do (let ((char (char exec i)))
               (cond ((and (char= char #\%) (< (1+ i) (length exec)))
                      (let ((code (char exec (1+ i))))
                        (when (char= code #\%) (write-char #\% out))
                        (incf i 2)))
                     (t (write-char char out) (incf i)))))))

(defun desktop-entries ()
  "The applications installed, from the XDG data directories; the first
directory with a given file wins."
  (let ((seen (make-hash-table :test 'equal))
        (entries '()))
    (dolist (dir (%desktop-directories))
      (dolist (file (ignore-errors (directory (merge-pathnames "*.desktop" dir))))
        (let ((id (pathname-name file)))
          (unless (gethash id seen)
            (setf (gethash id seen) t)
            (alexandria:when-let ((entry (ignore-errors (%parse-desktop-file file))))
              (push entry entries))))))
    (sort entries #'string-lessp :key #'desktop-entry-name)))

(defun launch-desktop-entry (entry)
  "Start the application of ENTRY, in a terminal when it wants one."
  (let ((exec (desktop-entry-exec entry)))
    (log-string :info "Starting ~A: ~A" (desktop-entry-name entry) exec)
    (if (desktop-entry-terminal entry)
        (let ((terminal (loop for name in mahogany/system::*default-terminals*
                              thereis (mh-sys:find-program name))))
          (if terminal
              (uiop:launch-program (list terminal "-e" "sh" "-c" exec))
              (error 'mahogany/util:recoverable-error :text "No terminal found")))
        (uiop:launch-program exec))))

;;; What was chosen before comes first

(defglobal *launcher-history* (make-hash-table :test 'equal)
  "How often each application and command was chosen, by name.")

(defun %history-file ()
  (state-file "launcher-history.sexp"))

(defun %load-history ()
  (ignore-errors
   (with-open-file (in (%history-file) :if-does-not-exist nil)
     (when in
       (let ((*read-eval* nil))
         (loop for (name . count) in (read in nil)
               do (setf (gethash name *launcher-history*) count)))))))

(defun %save-history ()
  (ignore-errors
   (ensure-directories-exist (%history-file))
   (with-open-file (out (%history-file) :direction :output :if-exists :supersede)
     (let ((*print-readably* t))
       (print (alexandria:hash-table-alist *launcher-history*) out)))))

(defun %remember-choice (name)
  (incf (gethash name *launcher-history* 0))
  (%save-history))

(defun %by-history (items key)
  "ITEMS with the often chosen first, otherwise in their order."
  (stable-sort (copy-list items) #'>
               :key (lambda (item) (gethash (funcall key item) *launcher-history* 0))))

;;; The modes

(define-launcher-mode :menu (:prompt "Go" :description "Everything")
  :items (loop for name in *launcher-mode-order*
               for mode = (gethash name *launcher-modes*)
               unless (eq name :menu)
                 collect (make-menu-item (launcher-mode-description mode) :data name))
  :action (lambda (name) (launcher name)))

(define-launcher-mode :apps (:prompt "Run" :description "Applications")
  :items (%by-history
          (mapcar (lambda (entry)
                    (make-menu-item (desktop-entry-name entry)
                                    :data entry
                                    :detail (or (desktop-entry-generic entry) (desktop-entry-comment entry))
                                    :keywords (append (desktop-entry-keywords entry)
                                                      (list (desktop-entry-exec entry)))))
                  (desktop-entries))
          (lambda (item) (desktop-entry-name (menu-item-data item))))
  :action (lambda (entry)
            (%remember-choice (desktop-entry-name entry))
            (launch-desktop-entry entry)))

(define-launcher-mode :commands (:prompt "Command" :description "Mahogany commands")
  :items (let ((keys (make-hash-table :test 'equal)))
           (loop for (keys-string . name) in (%active-bindings)
                 unless (gethash name keys)
                   do (setf (gethash name keys) keys-string))
           (%by-history
            (mapcar (lambda (name) (make-menu-item name :data name :detail (gethash name keys)))
                    (sort (copy-list (cl-interactive:database-strings
                                      cl-interactive:*default-command-database*))
                          #'string-lessp))
            #'menu-item-label))
  :action (lambda (name)
            (%remember-choice name)
            (let ((command (cl-interactive:find-command
                            cl-interactive:*default-command-database* name)))
              (if command
                  (execute-command command nil (server-seat *compositor-state*))
                  (toast-message *compositor-state* (format nil "No command ~A" name)
                                 :theme *message-error-theme*)))))

(defun %group-label (group)
  "GROUP's name, with its output's when there is more than one output."
  (let ((home (mahogany-group-home group)))
    (if (and (stringp home) (> (length (state-cur-outputs *compositor-state*)) 1))
        (format nil "~A ~A" home (mahogany-group-name group))
        (mahogany-group-name group))))

(defun %listed-groups ()
  "The groups of the focused output the user chooses among, by number."
  (remove-if-not #'group-listed-p
                 (output-groups *compositor-state* (state-current-home *compositor-state*))))

(define-launcher-mode :windows (:prompt "Window" :description "Windows")
  :items (loop for group across (state-groups *compositor-state*)
               append (loop for view in (mahogany-group-views group)
                            collect (make-menu-item (or (hrt:view-title view) "(untitled)")
                                                    :data view
                                                    :detail (%group-label group))))
  :action (lambda (view) (mahogany-state-show-view *compositor-state* view)))

(define-launcher-mode :groups (:prompt "Group" :description "Groups of this output")
  :items (loop for group in (%listed-groups)
               collect (make-menu-item (mahogany-group-name group)
                                       :data group
                                       :detail (format nil "~D window~:P"
                                                       (length (mahogany-group-views group)))))
  :action (lambda (group) (setf (state-current-group *compositor-state*) group)))

(define-launcher-mode :move-to-group (:prompt "Move window to" :description "Move the window to a group of this output")
  :items (loop for group in (%listed-groups)
               unless (eq group (state-current-group *compositor-state*))
                 collect (make-menu-item (mahogany-group-name group) :data group))
  :action (lambda (group) (%move-current-surface group)))

(define-launcher-mode :run (:prompt "Run" :description "Shell command")
  :items (mapcar #'car (sort (remove-if-not (lambda (entry) (stringp (car entry)))
                                            (alexandria:hash-table-alist *launcher-history*))
                             #'> :key #'cdr))
  :action (lambda (command) (%remember-choice command) (uiop:launch-program command))
  :text-action (lambda (command) (%remember-choice command) (uiop:launch-program command)))

;;; The input method of interactive commands

(defclass menu-input-method (cl-interactive:input-method) ()
  (:documentation "Reads through the Lisp menu. Interactive commands run
on a thread of their own, which waits here while the menu is open on the
main thread."))

(defmethod cl-interactive:prepare-completions-for-input-method
    ((im menu-input-method) (completions cl-interactive:database))
  (cl-interactive:database-strings completions))

(defmethod cl-interactive:prepare-completions-for-input-method
    ((im menu-input-method) (completions list))
  (if (every #'stringp completions)
      completions
      (error 'cl-interactive:unknown-completions-error
             :input-method im :completions completions)))

(defun %menu-read (prompt items allow-text initial)
  "Open a menu on the main thread and wait for its result: the chosen
item, or NIL for cancelled."
  (let ((semaphore (sb-thread:make-semaphore))
        (result nil))
    (hrt:with-main-thread ()
      (menu-open prompt items
                 :allow-text allow-text
                 :initial-filter (or initial "")
                 :on-choose (lambda (choice)
                              (setf result choice)
                              (sb-thread:signal-semaphore semaphore))
                 :on-cancel (lambda ()
                              (sb-thread:signal-semaphore semaphore))))
    (sb-thread:wait-on-semaphore semaphore)
    result))

(defmethod cl-interactive:input-method-read ((im menu-input-method) (prompt string)
                                             &key completions require-match initial-input
                                               history &allow-other-keys)
  (declare (ignore history))
  (let ((result (%menu-read (menu-prompt-string prompt) completions
                            (not require-match) initial-input)))
    (cond ((null result) (error (quote cl-interactive:cancel-interactive-command)))
          ((menu-item-p result) (menu-item-label result))
          (t result))))

(defmethod cl-interactive/input-method::input-method-read-index
    ((im menu-input-method) sequence prompt &key select-multiple)
  (declare (ignore select-multiple))
  (let* ((items (loop for element in (coerce sequence 'list)
                      for index from 0
                      collect (make-menu-item (princ-to-string element) :data index)))
         (result (%menu-read (menu-prompt-string prompt) items nil nil)))
    (if (menu-item-p result)
        (list (menu-item-data result))
        (error 'cl-interactive:cancel-interactive-command))))

(setf cl-interactive:*default-input-method* (make-instance 'menu-input-method))
(pushnew 'menu-input-method *input-methods-available*)

(%load-history)
