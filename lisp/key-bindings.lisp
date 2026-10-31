(in-package #:mahogany)

(defun interactively-read-bool (com im arg prompt)
  (declare (ignore com arg))
  (let ((result (cl-interactive:input-method-read-index
                 im
                 (list "Yes" "No")
                 prompt)))
    (= 0 (first result))))

(defcommand run-shell-command
    ((shell-command (:function interactively-read-string :data "Exec")))
  (:method ((exec string))
    (uiop:launch-program exec)))

(defcommand handle-server-stop ()
  (:method ()
    (server-stop *compositor-state*)))

(defcommand shutdown-gracefully ()
  (:method ()
    (server-shutdown-gracefully *compositor-state*)))

(defcommand shutdown-confirm
    ((should-shutdown (:function interactively-read-bool :data "Quit?")))
  (:method (should-shutdown)
    (when should-shutdown
      (server-shutdown-gracefully *compositor-state*))))

(defcommand shutdown-cancel ()
  (:method ()
    (server-shutdown-cancel *compositor-state*)))

(defcommand open-terminal ()
  (:method ()
    (mh-sys:open-terminal)))

(defcommand show-time ()
  (:documentation "Show the current date and time in a message")
  (:method ()
    (multiple-value-bind (sec min hour day month year)
        (decode-universal-time (get-universal-time))
      (declare (ignore sec))
      (toast-message *compositor-state*
                     (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D"
                             year month day hour min)))))

(defun %binding-name (binding)
  (string-downcase
   (if (typep binding 'generic-function)
       (symbol-name (c2mop:generic-function-name binding))
       (princ-to-string binding))))

(defun %active-bindings ()
  "Return a list of (KEYS-STRING . NAME) for every key binding that is
active, shorter key sequences first. A sequence bound in more than one
keymap is listed once, with the binding that wins."
  (let ((seen (make-hash-table :test 'equal))
        (result nil))
    ;; The keymaps are searched in order, so the first binding wins:
    (dolist (kmap (state-keybindings *compositor-state*))
      (map-kmap-bindings
       (lambda (keys binding)
         (let ((keys-string (format nil "~{~A~^ ~}"
                                    (mapcar (lambda (key)
                                              (with-output-to-string (s)
                                                (pprint-key key s)))
                                            keys))))
           (unless (gethash keys-string seen)
             (setf (gethash keys-string seen) t)
             (push (list (length keys) keys-string (%binding-name binding))
                   result))))
       kmap))
    (mapcar (lambda (entry) (cons (second entry) (third entry)))
            (stable-sort result
                         (lambda (a b)
                           (if (= (first a) (first b))
                               (string-lessp (second a) (second b))
                               (< (first a) (first b))))))))

(declaim (ftype function show-key-help))
(defcommand describe-bindings ()
  (:documentation "Show every key binding that is active now, until a key is pressed")
  (:method ()
    (show-key-help)))

(defcommand split-frame-h ()
  (:documentation "Split the current frame horizontally")
  (:method ()
    (let ((frame (state-current-frame *compositor-state*)))
      (when frame
        (tree:split-frame-h frame :direction :right)))))

(defcommand split-frame-v ()
  (:documentation "Split the current frame vertically")
  (:method ()
    (let ((frame (state-current-frame *compositor-state*)))
      (when frame
        (tree:split-frame-v frame :direction :bottom)))))

(defcommand split-frame-parent-h ()
  (:documentation "Split the curent frame's parent")
  (:method ()
    (let ((frame (state-current-frame *compositor-state*)))
      (if (tree:topmost-frame-p frame)
          (error 'mahogany/util:invalid-operation
                 :text "Cannot split the topmost frame")
          (tree:split-frame-h (tree:frame-parent frame))))))

(defcommand split-frame-parent-v ()
  (:documentation "Split the curent frame's parent")
  (:method ()
    (let ((frame (state-current-frame *compositor-state*)))
      (if (tree:topmost-frame-p frame)
          (error 'mahogany/util:invalid-operation
                 :text "Cannot split the topmost frame")
          (tree:split-frame-v (tree:frame-parent frame))))))

(defcommand maximize-current-frame ()
  (:method ()
    (let ((group (state-current-group *compositor-state*)))
      (group-maximize-current-frame group))))

(defcommand remove-current-frame ()
  (:documentation "Remove the current frame in the tree")
  (:method ()
    (state-remove-cur-group-frame *compositor-state*)))

(defcommand close-current-view ()
  (:method ()
    (alexandria:when-let*
        ((frame (state-current-frame *compositor-state*))
         (surface (tree:frame-surface frame)))
      (typecase surface
        (hrt:view
         (hrt:view-request-close surface))
        (hrt:layer-surface
         (hrt:layer-surface-close surface))))))

(defcommand next-view ()
  (:documentation "Raise the next hidden view in the current group")
  (:method ()
    (state-next-hidden-frame *compositor-state*)))

(defcommand previous-view ()
  (:documentation "Raise the previous hidden view in the current group")
  (:method ()
    (state-prev-hidden-frame *compositor-state*)))

(defcommand next-frame (seat)
  (:documentation
   "Set the current frame to the next one in the frame graph")
  (:method (seat)
    (let ((cur-frame (state-current-frame *compositor-state*)))
      (state-focus-frame *compositor-state* (tree:frame-next cur-frame) seat))))

(defcommand prev-frame (seat)
  (:documentation
   "Set the current frame to the previous one in the frame graph")
  (:method (seat)
    (let ((cur-frame (state-current-frame *compositor-state*)))
      (state-focus-frame *compositor-state* (tree:frame-prev cur-frame) seat))))

(defun interactively-read-new-group-name (com im arg prompt)
  (declare (ignore com arg))
  (let* ((next-name (state-next-group-name *compositor-state*))
         (full-prompt (concatenate 'string prompt " (default: " next-name ")")))
    (cl-interactive:input-method-read im full-prompt :require-match nil)))

(defcommand gnew
    ((name (:function interactively-read-new-group-name :data "Name")))
  (:method ((name string))
    (mahogany-state-group-add
     *compositor-state*
     :group-name (if (string= name "") nil name))))

(defcommand gnewbg
    ((name (:function interactively-read-new-group-name :data "Name")))
  (:method ((name string))
    (mahogany-state-group-add
     *compositor-state*
     :group-name (if (string= name "") nil name)
     :make-current nil)))

(defun interactively-read-group (com im arg prompt)
  (declare (ignore com arg))
  (let* ((groups (remove-if-not #'group-listed-p
                                (output-groups *compositor-state* (state-current-home *compositor-state*))))
         ;; It would be good to sort the list so that the current
         ;; group is on the bottom, mark the current group with a `*`,
         ;; or something similar to help user.
         (group-name (cl-interactive:completing-read
                      im prompt
                      :completions (map 'list #'mahogany-group-name groups)
                      :require-match t)))
    (find group-name groups :key #'mahogany-group-name :test #'string=)))

(defun read-group-windows (com im arg prompt)
  (declare (ignore com arg))
  (let* ((group (state-current-group *compositor-state*))
         (views (remove-if (lambda (x) (not (hrt:view-mapped-p x)))
                           (mahogany-group-views group)))
         (idx-list (cl-interactive:input-method-read-index
               im
               (mapcar #'hrt::view-title views)
               prompt :select-multiple t)))
    (mapcar (lambda (x) (elt views x)) idx-list)))

(defcommand grouplist
    ((group (:function interactively-read-group :data "Group?")))
  (:method (group)
    (setf (state-current-group *compositor-state*) group)))

(defcommand gkill ()
  (:method ()
    (let ((current-group (state-current-group *compositor-state*)))
      (mahogany-state-group-remove *compositor-state* current-group))))

(defcommand gnext ()
  (:documentation "The next group of this output, by number")
  (:method ()
    (state-next-group *compositor-state*)))

(defcommand gprev ()
  (:documentation "The previous group of this output, by number")
  (:method ()
    (state-previous-group *compositor-state*)))

(defcommand grename
    ((new-name (:function interactively-read-string :data "New Name")))
  (:method (new-name)
    (let ((current-group (state-current-group *compositor-state*)))
      (setf (mahogany-group-name current-group) new-name))))

(defun %prep-move-cur-view ()
  (alexandria:when-let*
      ((current-frame (state-current-frame *compositor-state*))
       (surface (tree:frame-surface current-frame)))
    (when (typep surface 'hrt:layer-surface)
      (error 'mahogany/util:invalid-operation
             :text "Cannot move layer shell surfaces"))
    (let ((current-group (state-current-group *compositor-state*)))
      (unless (eq (mahogany-group-current-frame current-group)
                  current-frame)
        (error 'mahogany/util:mahogany-panic
               :text "Current tiled frame does not match current group"))
      (return-from %prep-move-cur-view (values current-group surface))))
  (error 'mahogany/util:invalid-operation
         :text "No view to move."))

(defun %move-current-surface (destination)
  (multiple-value-bind (cur-group surface)
      (%prep-move-cur-view)
    (group-move-view cur-group destination surface)))

(defcommand gmerge
    ((from (:function interactively-read-group :data "From Group")))
  (:documentation "Merge FROM into the current group. FROM is not deleted")
  (:method (from)
    (group-transfer-views (state-current-group *compositor-state*)
                          from)))

(defcommand gmove
    ((group (:function interactively-read-group :data "Group?")))
  (:documentation "Move the currently focused view to the specified group")
  (:method (destination)
    (%move-current-surface destination)))

(defcommand gmove-select
    ((views (:function read-group-windows :data "To Move"))
     (group (:function interactively-read-group :data "Destination")))
  (:documentation "Move the selected windows to the specified group")
  (:method (views destination)
    (let ((cur-group (state-current-group *compositor-state*)))
      (dolist (v views)
        (group-move-view cur-group destination v)))))

(defcommand gmove-and-follow
    ((group (:function interactively-read-group :data "Group?")))
  (:documentation
   "Move the currently focused view to the specified group and switch to it")
  (:method (destination)
    (%move-current-surface destination)
    (setf (state-current-group *compositor-state*) destination)))

(defcommand gnext-with-window
    ()
  (:documentation
   "Cycle to the next group of this output, taking the current window along.")
  (:method ()
    (multiple-value-bind (initial-group surface)
        (%prep-move-cur-view)
      (state-next-group *compositor-state*)
      (group-move-view
       initial-group
       (state-current-group *compositor-state*)
       surface))))

(defcommand gprev-with-window
    ()
  (:documentation
   "Cycle to the previous group of this output, taking the current window along.")
  (:method ()
    (multiple-value-bind (initial-group surface)
        (%prep-move-cur-view)
      (state-previous-group *compositor-state*)
      (group-move-view
       initial-group
       (state-current-group *compositor-state*)
       surface))))

;;; Groups by number: s-N and C-t N switch, s-C-N and C-t g N move the
;;; window; the groups up to N are made when missing, so s-5 works in
;;; a fresh session.

(defun select-group-number (n)
  "Switch the focused output to its group number N, made when it is
missing (and only it: 9 after 1 gives 1 and 9)."
  (let ((state *compositor-state*))
    (alexandria:if-let ((group (%state-select-group state n)))
      (setf (state-current-group state) group)
      (mahogany-state-group-add state :number n))))

(defun move-window-to-group-number (n &key follow)
  "Move the focused window to group number N of its output (made when
missing), and switch to it when FOLLOW is true."
  (let* ((state *compositor-state*)
         (group (or (%state-select-group state n)
                    (mahogany-state-group-add state :number n :make-current nil))))
    (unless (eq group (state-current-group state))
      (%move-current-surface group)
      (mode-line-update)
      (when follow
        (setf (state-current-group state) group)))))

(macrolet ((define-number-commands ()
             `(progn
                ,@(loop for n from 1 to 10
                        collect `(defcommand ,(alexandria:symbolicate "SELECT-GROUP-" (princ-to-string n)) ()
                                   (:documentation ,(format nil "Switch to group ~D, making it when missing" n))
                                   (:method () (select-group-number ,n)))
                        collect `(defcommand ,(alexandria:symbolicate "MOVE-WINDOW-TO-GROUP-" (princ-to-string n)) ()
                                   (:documentation ,(format nil "Move the focused window to group ~D" n))
                                   (:method () (move-window-to-group-number ,n)))))))
  (define-number-commands))

(defun interactively-read-valid-output-layout (com im arg prompt)
  (declare (ignore com arg))
  (let* ((outputs (map 'list #'tree:output-container-output
                       (state-cur-outputs *compositor-state*)))
         (configs (mh/output-config:find-valid-output-layouts outputs)))
    (if configs
        (let ((idx-list (cl-interactive:input-method-read-index
                         im
                         (mapcar #'mh/output-config:output-layout-config-name configs)
                         prompt)))
          (elt configs (car idx-list)))
        nil)))

(defcommand output-layout-apply
    ((config (:function interactively-read-valid-output-layout
              :data "Configuration?")))
  (:documentation
   "Select an output layout to use from a list of the currently
valid output layouts")
  (:method ((config mh/output-config:output-layout-config))
    (let ((success (state-use-output-layout *compositor-state* config)))
      (unless success
        (let ((config-name (mh/output-config:output-layout-config-name config)))
          (toast-message *compositor-state*
                         (format nil "Failed to apply configuration ~S"
                                 config-name)
                         :theme *message-error-theme*)))
      success))
  (:method ((config null))
    (toast-message *compositor-state*
                   (format nil "No valid output layouts available.")
                   :theme *message-error-theme*)))

(defcommand output-layout-rescan ()
  (:documentation
   "Rescan the outputs and apply the most appropriate (default) output layout")
  (:method ()
    (let ((success (state-output-layouts-rescan *compositor-state*)))
      (unless success
        (toast-message *compositor-state*
                       (format nil "Failed to apply scanned configuration")
                       :theme *message-error-theme*))
      success)))

#+:hrt-debug
(defcommand add-output ()
  (:method ()
    (if (hrt:hrt-add-output (state-server *compositor-state*))
        (log-string :info "Output not added")
        (log-string :info "Output added"))))

#+:hrt-debug
(defvar *debug-map*
    (define-kmap
      (kbd "a") #'add-output))

(defvar *session-root-map*
  (define-kmap
    (kbd "q") (define-kmap
                (kbd "q") #'shutdown-gracefully
                (kbd "k") #'handle-server-stop)))

(define-kmap-mode session-cmd-mode
  :documentation "keybindings for quitting mahogany"
  :prefix-binding *session-root-map*)

(defvar *group-map*
  (define-kmap
    (kbd "c") #'gnew
    (kbd "k") #'gkill
    (kbd "n") #'gnext
    (kbd "N") #'gnext-with-window
    (kbd "l") #'grouplist
    (kbd "p") #'gprev
    (kbd "P") #'gprev-with-window
    (kbd "m") #'gmove
    (kbd "M") #'gmove-and-follow
    ;; C-t g N sends the window to group N, C-t g FN switches to it
    ;; (as C-t N does):
    (kbd "1") #'move-window-to-group-1
    (kbd "2") #'move-window-to-group-2
    (kbd "3") #'move-window-to-group-3
    (kbd "4") #'move-window-to-group-4
    (kbd "5") #'move-window-to-group-5
    (kbd "6") #'move-window-to-group-6
    (kbd "7") #'move-window-to-group-7
    (kbd "8") #'move-window-to-group-8
    (kbd "9") #'move-window-to-group-9
    (kbd "F1") #'select-group-1
    (kbd "F2") #'select-group-2
    (kbd "F3") #'select-group-3
    (kbd "F4") #'select-group-4
    (kbd "F5") #'select-group-5
    (kbd "F6") #'select-group-6
    (kbd "F7") #'select-group-7
    (kbd "F8") #'select-group-8
    (kbd "F9") #'select-group-9
    (kbd "F10") #'select-group-10))

(defvar *root-map*
  (define-kmap
    (kbd "!") #'run-shell-command
    (kbd ";") #'colon
    (kbd "a") #'show-time
    (kbd "?") #'describe-bindings
    (kbd "o") #'next-frame
    (kbd "O") #'prev-frame
    (kbd "k") #'close-current-view
    (kbd "c") #'open-terminal
    (kbd "s") #'split-frame-v
    (kbd "S") #'split-frame-h
    (kbd "Q") #'maximize-current-frame
    (kbd "n") #'next-view
    (kbd "p") #'previous-view
    (kbd "g") '*group-map*
    (kbd "R") #'remove-current-frame
    ;; Groups by number, as StumpWM's gselect; C-t g N moves the window:
    (kbd "1") #'select-group-1
    (kbd "2") #'select-group-2
    (kbd "3") #'select-group-3
    (kbd "4") #'select-group-4
    (kbd "5") #'select-group-5
    (kbd "6") #'select-group-6
    (kbd "7") #'select-group-7
    (kbd "8") #'select-group-8
    (kbd "9") #'select-group-9))

;; The launcher and the directions are bound on *root-map* too, in
;; default-bindings.lisp, which loads after them.

(defvar *top-map* (define-kmap))

#+:hrt-debug
(progn
  (define-key *root-map* (kbd "d") *debug-map*))

;; Instead of using the macro, maybe we should define this manually
;; so users can't deactivate it?
(define-kmap-mode base-mode
  :documentation "Base mode for mahogany that contains the default keybindings"
  :top-binding *top-map*
  :prefix-binding *root-map*)

(define-kmap-mode prefix-passthrough-mode
  :documentation "Kmap mode that makes pressing the prefix key twice in a row
send the prefix key to the focused client."
  :prefix-binding *prefix-passthrough-kmap*)

(base-mode t)
(prefix-passthrough-mode t)
(session-cmd-mode t)
