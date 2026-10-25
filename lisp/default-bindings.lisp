(in-package #:mahogany)

;;; The default keys: SUPER chords on *top-map*, the way Omarchy and
;;; most Wayland desktops have them, next to the C-t prefix map of
;;; StumpWM (*root-map*). init.lisp changes any of them with define-key
;;; and undefine-key on *top-map*; describe-bindings (s-k) lists what
;;; is bound. Also here: *autostart*, the programs started with the
;;; session.

;;; Groups by number

(defun select-group-number (n)
  "Switch to group number N, making the groups up to N when they are
missing, so s-5 works in a fresh session."
  (let ((state *compositor-state*))
    (loop until (%state-select-group state n)
          do (mahogany-state-group-add state :make-current nil))
    (state-select-group state n)))

(defun move-window-to-group-number (n &key follow)
  "Move the focused window to group number N (made when missing), and
switch to it when FOLLOW is true."
  (let* ((state *compositor-state*)
         (group (or (%state-select-group state n)
                    (progn (loop until (%state-select-group state n)
                                 do (mahogany-state-group-add state :make-current nil))
                           (%state-select-group state n)))))
    (unless (eq group (state-current-group state))
      (%move-current-surface group)
      (mode-line-update)
      (when follow
        (setf (state-current-group state) group)))))

(macrolet ((define-number-commands ()
             `(progn
                ,@(loop for n from 1 to 9
                        collect `(defcommand ,(alexandria:symbolicate "SELECT-GROUP-" (princ-to-string n)) ()
                                   (:documentation ,(format nil "Switch to group ~D, making it when missing" n))
                                   (:method () (select-group-number ,n)))
                        collect `(defcommand ,(alexandria:symbolicate "MOVE-WINDOW-TO-GROUP-" (princ-to-string n)) ()
                                   (:documentation ,(format nil "Move the focused window to group ~D" n))
                                   (:method () (move-window-to-group-number ,n)))))))
  (define-number-commands))

;;; The keys

(defun define-keys (kmap &rest bindings)
  "Bind the keys in BINDINGS, alternating key strings and commands, in
KMAP: (define-keys *top-map* \"s-RET\" #'open-terminal \"s-w\" #'close-current-view)."
  (loop for (key command) on bindings by #'cddr
        do (define-key kmap (kbd key) command)))

(define-keys *top-map*
  ;; Programs and menus
  "s-RET" #'open-terminal
  "s-SPC" #'launcher-apps
  "s-M-SPC" #'launcher-menu
  "s-x" #'launcher-commands
  "s-semicolon" #'colon
  "s-k" #'describe-bindings
  ;; Windows and frames
  "s-w" #'close-current-view
  "s-Tab" #'next-view
  "s-S-Tab" #'previous-view
  "s-Up" #'previous-view
  "s-Down" #'next-view
  "s-o" #'next-frame
  "s-Right" #'next-frame
  "s-S-o" #'prev-frame
  "s-Left" #'prev-frame
  "s-s" #'split-frame-v
  "s-S-s" #'split-frame-h
  "s-f" #'maximize-current-frame
  "s-r" #'remove-current-frame
  "s-S-w" #'launcher-windows
  "s-grave" #'scratchpad-toggle
  "s-S-grave" #'scratchpad-send
  ;; Groups
  "s-g" #'launcher-groups
  "s-S-g" #'move-window-to-group-menu
  "s-bracketright" #'gnext
  "s-bracketleft" #'gprev
  "s-1" #'select-group-1 "s-2" #'select-group-2 "s-3" #'select-group-3
  "s-4" #'select-group-4 "s-5" #'select-group-5 "s-6" #'select-group-6
  "s-7" #'select-group-7 "s-8" #'select-group-8 "s-9" #'select-group-9
  "s-S-1" #'move-window-to-group-1 "s-S-2" #'move-window-to-group-2
  "s-S-3" #'move-window-to-group-3 "s-S-4" #'move-window-to-group-4
  "s-S-5" #'move-window-to-group-5 "s-S-6" #'move-window-to-group-6
  "s-S-7" #'move-window-to-group-7 "s-S-8" #'move-window-to-group-8
  "s-S-9" #'move-window-to-group-9
  ;; Outputs
  "s-period" #'focus-next-output
  "s-comma" #'focus-previous-output
  "s-S-period" #'move-window-to-next-output
  "s-S-comma" #'move-window-to-previous-output
  ;; The desktop
  "s-b" #'mode-line
  "s-C-SPC" #'theme-menu
  "s-C-S-SPC" #'next-theme
  "s-ESC" #'lock-session
  "s-S-e" #'shutdown-confirm)

;;; Autostart

(config:defconfig *autostart* '()
  list
  "Programs started with the session, once the compositor is up: each
a list of arguments or a shell command string, such as
(\"xwayland-satellite\") or \"mako\". A program that is not installed is
logged and skipped.")

(defun run-autostart ()
  "Start the programs in *autostart*, a moment after the server is up."
  (when *autostart*
    (let ((timer (hrt:server-make-timer
                  (state-server *compositor-state*)
                  (lambda (timer)
                    (hrt:timer-handle-destroy timer)
                    (dolist (command *autostart*)
                      (let ((program (if (listp command) (first command) command)))
                        (if (and (listp command)
                                 (not (mahogany/system:find-program program)))
                            (log-string :warn "Autostart: ~A is not installed" program)
                            (handler-case
                                (progn
                                  (log-string :info "Autostart: ~S" command)
                                  (uiop:launch-program command))
                              (error (c)
                                (log-string :error "Autostart: could not start ~S: ~A"
                                            command c))))))))))
      (hrt:timer-handle-update timer 500))))
