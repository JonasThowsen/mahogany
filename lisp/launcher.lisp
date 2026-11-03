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
  ;; The same for a choice with C-Return, or NIL for ACTION again:
  (alternate-action nil :type (or null function))
  ;; A function of typed text when nothing matched, or NIL to refuse:
  (text-action nil :type (or null function))
  ;; A function of the selected item's data, called as the selection
  ;; moves, for a preview, or NIL:
  (select-action nil :type (or null function))
  ;; A function of no arguments called when the menu is cancelled, or NIL:
  (cancel-action nil :type (or null function))
  ;; A function of an item's data, true of the item to select first, or NIL:
  (initial nil :type (or null function)))

(defglobal *launcher-modes* (make-hash-table)
  "The launcher's modes, by name.")

(defglobal *launcher-mode-order* '()
  "The modes in the order they were defined, for the top menu.")

(defun register-launcher-mode (name &key prompt description items action alternate-action
                                         text-action select-action cancel-action initial)
  "Add, or replace, the launcher mode NAME. See define-launcher-mode."
  (check-type name keyword)
  (setf (gethash name *launcher-modes*)
        (%make-launcher-mode :name name
                             :prompt (or prompt (string-capitalize name))
                             :description (or description (string-capitalize name))
                             :items items
                             :action action
                             :alternate-action alternate-action
                             :text-action text-action
                             :select-action select-action
                             :cancel-action cancel-action
                             :initial initial))
  (unless (member name *launcher-mode-order*)
    (setf *launcher-mode-order* (append *launcher-mode-order* (list name))))
  name)

(defmacro define-launcher-mode (name (&key prompt description)
                                &key items action alternate-action text-action
                                  select-action cancel-action initial)
  "Define a launcher mode. NAME is a keyword. ITEMS is a form evaluated
when the menu opens, giving menu-items (make-menu-item) or strings.
ACTION is a function of the chosen item's data (or its label, for a
string item); ALTERNATE-ACTION, when given, is called instead for a
choice made with C-Return. TEXT-ACTION, when given, is a function of
what was typed when it matched nothing, so the mode accepts free text.
SELECT-ACTION, when given, is a function of the selected item's data,
called each time the selection moves (a preview); CANCEL-ACTION a
function of no arguments called when the menu is cancelled (to undo
the preview); INITIAL a function of an item's data, true of the item
selected when the menu opens.

  (define-launcher-mode :projects (:prompt \"Project\" :description \"Open a project\")
    :items (mapcar (lambda (dir) (make-menu-item (file-namestring dir) :data dir))
                   (directory \"~/coding/*/\"))
    :action (lambda (dir) (uiop:launch-program (list \"foot\" \"-D\" (namestring dir)))))"
  `(register-launcher-mode ,name
                           :prompt ,prompt
                           :description ,description
                           :items (lambda () ,items)
                           :action ,action
                           :alternate-action ,alternate-action
                           :text-action ,text-action
                           :select-action ,select-action
                           :cancel-action ,cancel-action
                           :initial ,initial))

(defun launcher (&optional (mode-name :menu))
  "Open the launcher in the mode MODE-NAME (:menu lists the modes)."
  (let ((mode (gethash mode-name *launcher-modes*)))
    (unless mode
      (error 'mahogany/util:recoverable-error
             :text (format nil "No launcher mode ~S" mode-name)))
    (flet ((chooser (action)
             (lambda (choice)
               (handler-case
                   (if (menu-item-p choice)
                       (funcall action (menu-item-value choice))
                       (funcall (launcher-mode-text-action mode) choice))
                 (error (c)
                   (toast-message *compositor-state*
                                  (format nil "~A: ~A" mode-name c)
                                  :theme *message-error-theme*))))))
      (menu-open (menu-prompt-string (launcher-mode-prompt mode))
                 (funcall (launcher-mode-items mode))
                 :allow-text (not (null (launcher-mode-text-action mode)))
                 :on-choose (chooser (launcher-mode-action mode))
                 :on-choose-alternate (alexandria:when-let ((action (launcher-mode-alternate-action mode)))
                                        (chooser action))
                 :on-select (alexandria:when-let ((action (launcher-mode-select-action mode)))
                              (lambda (item) (funcall action (menu-item-value item))))
                 :on-cancel (launcher-mode-cancel-action mode)
                 :initial-selection (alexandria:when-let ((initial (launcher-mode-initial mode)))
                                      (lambda (item) (funcall initial (menu-item-value item))))))))

(defun menu-item-value (item)
  "What a launcher mode's actions get for ITEM: its data, or its label."
  (or (menu-item-data item) (menu-item-label item)))

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

(defcommand launcher-eval ()
  (:documentation "Evaluate a Lisp form in the compositor")
  (:method () (launcher :eval)))

(defcommand launcher-load ()
  (:documentation "Load a Lisp file into the compositor")
  (:method () (launcher :load)))

(defcommand move-window-to-group-menu ()
  (:documentation "Move the current window to a group chosen from a menu")
  (:method () (launcher :move-to-group)))

;;; Applications: .desktop files

(defstruct (desktop-entry (:constructor make-desktop-entry
                              (id name &key generic comment exec terminal keywords categories
                                        actions wm-class)))
  "An application from a .desktop file. ACTIONS are its [Desktop Action]
groups, each (ID NAME EXEC); WM-CLASS its StartupWMClass, the app id
its windows have when it is not the file's name."
  id name generic comment exec terminal keywords categories actions wm-class)

(defun %desktop-directories ()
  (append (list (uiop:xdg-data-home "applications/"))
          (mapcar (lambda (dir) (uiop:subpathname dir "applications/"))
                  (uiop:xdg-data-dirs))))

(defun %parse-desktop-file (file)
  "The desktop-entry of FILE, or NIL when it is not an application to show."
  (let* ((fields (make-hash-table :test 'equal))
         (group nil)                    ; the table of the group being read
         (actions '()))                 ; (id . table) of the action groups, in file order
    (with-open-file (stream file :external-format :utf-8 :if-does-not-exist nil)
      (unless stream (return-from %parse-desktop-file nil))
      (loop for line = (read-line stream nil)
            while line
            do (let ((line (string-trim '(#\Space #\Tab #\Return) line)))
                 (cond ((zerop (length line)))
                       ((char= (char line 0) #\#))
                       ((char= (char line 0) #\[)
                        (setf group
                              (cond ((string= line "[Desktop Entry]") fields)
                                    ((and (alexandria:starts-with-subseq "[Desktop Action " line)
                                          (alexandria:ends-with #\] line))
                                     (let ((table (make-hash-table :test 'equal)))
                                       (setf actions
                                             (append actions
                                                     (list (cons (subseq line 16 (1- (length line)))
                                                                 table))))
                                       table))
                                    (t nil))))
                       (group
                        (let ((eq (position #\= line)))
                          (when eq
                            (setf (gethash (string-right-trim " " (subseq line 0 eq)) group)
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
                            :categories (uiop:split-string (or (field "Categories") "") :separator ";")
                            :wm-class (field "StartupWMClass")
                            :actions (loop for (id . table) in actions
                                           for name = (gethash "Name" table)
                                           for exec = (gethash "Exec" table)
                                           when (and name exec)
                                             collect (list id name (%strip-exec-field-codes exec))))))))

(defun desktop-entry-new-window-action (entry)
  "The action of ENTRY that opens a new window, as (ID NAME EXEC), or
NIL: browsers and editors have one, named new-window or \"New Window\";
a private or incognito window is not it."
  (flet ((says (string &rest words)
           (every (lambda (word) (search word string :test #'char-equal)) words)))
    (find-if (lambda (action)
               (destructuring-bind (id name exec) action
                 (declare (ignore exec))
                 (and (or (says id "new" "window") (says name "new" "window"))
                      (notany (lambda (word) (or (says id word) (says name word)))
                              '("private" "incognito" "anonym")))))
             (desktop-entry-actions entry))))

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

(defun launch-desktop-entry (entry &key new-window)
  "Start the application of ENTRY, in a terminal when it wants one. With
NEW-WINDOW, through its new-window action when it has one, so an
application already running opens another window instead of showing
the one it has."
  (let* ((action (and new-window (desktop-entry-new-window-action entry)))
         (exec (if action (third action) (desktop-entry-exec entry))))
    (log-string :info "Starting ~A~@[ (~A)~]: ~A" (desktop-entry-name entry)
                (and action (second action)) exec)
    (if (desktop-entry-terminal entry)
        (let ((terminal (loop for name in mahogany/system::*default-terminals*
                              thereis (mh-sys:find-program name))))
          (if terminal
              (uiop:launch-program (list terminal "-e" "sh" "-c" exec))
              (error 'mahogany/util:recoverable-error :text "No terminal found")))
        (uiop:launch-program exec))))

(defun desktop-entry-of-view (view)
  "The desktop-entry of VIEW's application, by its app id: the file's
name, its StartupWMClass, or the program its Exec starts. NIL when
none fits."
  (alexandria:when-let ((app-id (hrt:view-app-id view)))
    (let ((entries (desktop-entries)))
      (or (find app-id entries :key #'desktop-entry-id :test #'string-equal)
          (find app-id entries :key #'desktop-entry-wm-class :test #'equalp)
          (find-if (lambda (entry)
                     (let ((program (first (uiop:split-string (desktop-entry-exec entry)
                                                              :separator " "))))
                       (and program
                            (string-equal app-id (file-namestring program)))))
                   entries)))))

(defun launch-view-application (view)
  "Start another window of VIEW's application: through its desktop
entry, with its new-window action when it has one."
  (let ((entry (desktop-entry-of-view view)))
    (unless entry
      (error 'mahogany/util:recoverable-error
             :text (format nil "No application found for ~A"
                           (or (hrt:view-app-id view) (hrt:view-title view) "the window"))))
    (%remember-choice (desktop-entry-name entry))
    (launch-desktop-entry entry :new-window t)))

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
            (launch-desktop-entry entry))
  :alternate-action (lambda (entry)
                      (%remember-choice (desktop-entry-name entry))
                      (launch-desktop-entry entry :new-window t)))

(define-launcher-mode :commands (:prompt "Command" :description "Mahogany commands")
  :items (let ((keys (make-hash-table :test 'equalp)))
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
  :action (lambda (view) (mahogany-state-show-view *compositor-state* view))
  :alternate-action #'launch-view-application)

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

;;; Lisp from the launcher: a form to evaluate, or a file to load, in
;;; the running compositor. Both run on the main thread, as every
;;; choice in a menu does, so they may touch any of the compositor's
;;; state; a form that takes long stalls the session while it runs.

(defglobal *eval-history* '()
  "The forms evaluated from the launcher, the latest first.")

(defun eval-text (text)
  "Read the forms in TEXT in the mahogany package and evaluate them in
order; the values of the last one."
  (let ((*package* (find-package :mahogany))
        (values '()))
    (with-input-from-string (stream text)
      (loop for form = (read stream nil stream)
            until (eq form stream)
            do (setf values (multiple-value-list (eval form)))))
    (values-list values)))

(defparameter *values-text-length* 400
  "How much of the values an answer in a message shows.")

(defun %values-text (values)
  "VALUES as an answer shows them: each printed, briefly, and the
whole cut to *values-text-length* characters (the log has it all)."
  (let* ((*print-length* 20) (*print-level* 4) (*print-pretty* nil)
         (*package* (find-package :mahogany))
         (text (if values (format nil "~{~S~^, ~}" values) "; no values")))
    (if (> (length text) *values-text-length*)
        (concatenate 'string (subseq text 0 *values-text-length*) "…")
        text)))

(defun %eval-and-show (text)
  "Evaluate TEXT, remember it, and show its values in a message."
  (let* ((text (string-trim " " text))
         (values (multiple-value-list (eval-text text)))
         (answer (%values-text values)))
    (setf *eval-history* (cons text (remove text *eval-history* :test #'string=)))
    (log-string :info "Evaluated ~A => ~A" text
                (let ((*print-length* 100) (*print-level* 10) (*print-pretty* nil)
                      (*package* (find-package :mahogany)))
                  (format nil "~{~S~^, ~}" values)))
    (toast-message *compositor-state* (format nil "~A~%=> ~A" text answer))
    (values-list values)))

(define-launcher-mode :eval (:prompt "Eval" :description "Evaluate a Lisp form in the compositor")
  :items *eval-history*
  :action #'%eval-and-show
  :text-action #'%eval-and-show)

(defglobal *load-history* '()
  "The files loaded from the launcher, the latest first, as typed.")

(defun load-lisp-file (name)
  "Load the Lisp file NAME (~ stands for the home directory) into the
running compositor, as init.lisp is loaded, and return its truename."
  (let ((file (probe-file (string-trim " " name))))
    (unless file
      (error 'mahogany/util:recoverable-error :text (format nil "No file ~A" name)))
    (load file)
    (log-string :info "Loaded ~A" file)
    file))

(defun %load-items ()
  "The files loaded before, then the Lisp files beside init.lisp."
  (let ((config-files (mapcar #'uiop:native-namestring
                              (directory (uiop:xdg-config-home "mahogany/*.lisp")))))
    (append *load-history*
            (set-difference config-files *load-history* :test #'string=))))

(defun %load-and-show (name)
  (let ((file (load-lisp-file name))
        (name (string-trim " " name)))
    (setf *load-history* (cons name (remove name *load-history* :test #'string=)))
    (toast-message *compositor-state* (format nil "Loaded ~A" file))
    file))

(define-launcher-mode :load (:prompt "Load" :description "Load a Lisp file into the compositor")
  :items (%load-items)
  :action #'%load-and-show
  :text-action #'%load-and-show)

;;; Everything in one list, as Raycast has it: applications, windows,
;;; commands, groups, screens and the launcher's own modes, each item
;;; saying what it is, the often chosen first.

(defun %all-command-items ()
  ;; The bindings name commands in lower case, the database in upper:
  (let ((keys (make-hash-table :test 'equalp)))
    (loop for (keys-string . name) in (%active-bindings)
          unless (gethash name keys)
            do (setf (gethash name keys) keys-string))
    (mapcar (lambda (name)
              (make-menu-item (string-downcase name)
                              :data (list :command name)
                              :detail (format nil "Command~@[ · ~A~]" (gethash name keys))))
            (sort (copy-list (cl-interactive:database-strings
                              cl-interactive:*default-command-database*))
                  #'string-lessp))))

(defun %all-items ()
  "The items of the :all mode, the often chosen first within each kind:
applications, windows, groups, screens, commands, modes."
  (let ((windows (loop for group across (state-groups *compositor-state*)
                       append (loop for view in (mahogany-group-views group)
                                    collect (make-menu-item (or (hrt:view-title view) "(untitled)")
                                                            :data (list :window view)
                                                            :detail (format nil "Window · ~A" (%group-label group))
                                                            :keywords (list (or (hrt:view-app-id view) ""))))))
        (apps (%by-history
               (mapcar (lambda (entry)
                         (make-menu-item (desktop-entry-name entry)
                                         :data (list :app entry)
                                         :detail (format nil "App~@[ · ~A~]"
                                                         (or (desktop-entry-generic entry)
                                                             (desktop-entry-comment entry)))
                                         :keywords (append (desktop-entry-keywords entry)
                                                           (list (desktop-entry-exec entry)))))
                       (desktop-entries))
               (lambda (item) (desktop-entry-name (second (menu-item-data item))))))
        (groups (loop for group in (%listed-groups)
                      unless (eq group (state-current-group *compositor-state*))
                        collect (make-menu-item (format nil "Group ~A" (mahogany-group-name group))
                                                :data (list :group group)
                                                :detail (format nil "Group · ~D window~:P"
                                                                (length (mahogany-group-views group)))
                                                :keywords (list "workspace"))))
        (screens (let ((all (outputs)))
                   (when (> (length all) 1)
                     (loop for output in all
                           unless (hrt:output= output (current-output))
                             collect (make-menu-item (hrt:output-name output)
                                                     :data (list :output output)
                                                     :detail "Screen"
                                                     :keywords (list "monitor" "output"))))))
        (commands (%by-history (%all-command-items) #'menu-item-label))
        (modes (loop for name in *launcher-mode-order*
                     for mode = (gethash name *launcher-modes*)
                     unless (member name '(:menu :all))
                       collect (make-menu-item (launcher-mode-description mode)
                                               :data (list :mode name)
                                               :detail "Mode"))))
    (append windows apps groups screens commands modes)))

(defun %all-choose (data)
  (destructuring-bind (kind payload) data
    (ecase kind
      (:app (%remember-choice (desktop-entry-name payload))
       (launch-desktop-entry payload))
      (:window (mahogany-state-show-view *compositor-state* payload))
      (:group (setf (state-current-group *compositor-state*) payload))
      (:output (focus-output payload))
      (:command (%remember-choice payload)
       (let ((command (cl-interactive:find-command
                       cl-interactive:*default-command-database* payload)))
         (execute-command command nil (server-seat *compositor-state*))))
      (:mode (launcher payload)))))

(defun %all-choose-anew (data)
  "The :all mode's choice with C-Return: a window starts another window
of its application, an application starts in a new window; the rest
as with Return."
  (destructuring-bind (kind payload) data
    (case kind
      (:app (%remember-choice (desktop-entry-name payload))
       (launch-desktop-entry payload :new-window t))
      (:window (launch-view-application payload))
      (t (%all-choose data)))))

(define-launcher-mode :all (:prompt "Go" :description "Everything: apps, windows, commands, groups, screens")
  :items (%all-items)
  :action #'%all-choose
  :alternate-action #'%all-choose-anew)

(defcommand launcher-all ()
  (:documentation "Everything in one list: applications, windows, commands, groups, screens")
  (:method () (launcher :all)))

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
