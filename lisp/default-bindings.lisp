(in-package #:mahogany)

;;; The default keys: SUPER chords on *top-map*, laid out as niri has
;;; them (h j k l and the arrows for directions, Control moves the
;;; window, Shift the output), next to the C-t prefix map of StumpWM
;;; (*root-map*). init.lisp changes any of them with define-key and
;;; undefine-key on *top-map*; describe-bindings (s-S-SPC) lists what
;;; is bound. Also here: *autostart*, the programs started with the
;;; session.

;;; The group-number commands, select-group-N and move-window-to-group-N,
;;; are in key-bindings.lisp with the C-t maps that bind them too.

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
  "s-S-SPC" #'describe-bindings
  "s-M-SPC" #'launcher-menu
  "s-x" #'launcher-commands
  "s-semicolon" #'colon
  "s-o" #'launcher-windows
  "s-M-l" #'lock-session
  "s-S-e" #'shutdown-confirm
  ;; Windows and frames: h j k l and the arrows are left, down, up,
  ;; right; Control moves the window, Shift goes to the output beside
  "s-q" #'close-current-view
  "s-h" #'focus-left "s-j" #'focus-down "s-k" #'focus-up "s-l" #'focus-right
  "s-Left" #'focus-left "s-Down" #'focus-down "s-Up" #'focus-up "s-Right" #'focus-right
  "s-C-h" #'move-window-left "s-C-j" #'move-window-down
  "s-C-k" #'move-window-up "s-C-l" #'move-window-right
  "s-C-Left" #'move-window-left "s-C-Down" #'move-window-down
  "s-C-Up" #'move-window-up "s-C-Right" #'move-window-right
  "s-S-h" #'focus-output-left "s-S-j" #'focus-output-down
  "s-S-k" #'focus-output-up "s-S-l" #'focus-output-right
  "s-S-Left" #'focus-output-left "s-S-Down" #'focus-output-down
  "s-S-Up" #'focus-output-up "s-S-Right" #'focus-output-right
  "s-S-C-h" #'move-window-to-output-left "s-S-C-j" #'move-window-to-output-down
  "s-S-C-k" #'move-window-to-output-up "s-S-C-l" #'move-window-to-output-right
  "s-S-C-Left" #'move-window-to-output-left "s-S-C-Down" #'move-window-to-output-down
  "s-S-C-Up" #'move-window-to-output-up "s-S-C-Right" #'move-window-to-output-right
  "s-Tab" #'next-view
  "s-S-Tab" #'previous-view
  "s-f" #'maximize-current-frame
  "s-S-f" #'fullscreen-toggle
  "s-s" #'split-frame-h
  "s-S-s" #'split-frame-v
  "s-S-r" #'remove-current-frame
  "s-grave" #'scratchpad-toggle
  "s-S-grave" #'scratchpad-send
  ;; Groups (workspaces): d and u, or Page Down and Up, go down and up
  ;; the list; with Control the window comes along
  "s-d" #'gnext "s-Page_Down" #'gnext
  "s-u" #'gprev "s-Page_Up" #'gprev
  "s-C-d" #'gnext-with-window "s-C-Page_Down" #'gnext-with-window
  "s-C-u" #'gprev-with-window "s-C-Page_Up" #'gprev-with-window
  "s-g" #'launcher-groups
  "s-S-g" #'move-window-to-group-menu
  "s-1" #'select-group-1 "s-2" #'select-group-2 "s-3" #'select-group-3
  "s-4" #'select-group-4 "s-5" #'select-group-5 "s-6" #'select-group-6
  "s-7" #'select-group-7 "s-8" #'select-group-8 "s-9" #'select-group-9
  "s-C-1" #'move-window-to-group-1 "s-C-2" #'move-window-to-group-2
  "s-C-3" #'move-window-to-group-3 "s-C-4" #'move-window-to-group-4
  "s-C-5" #'move-window-to-group-5 "s-C-6" #'move-window-to-group-6
  "s-C-7" #'move-window-to-group-7 "s-C-8" #'move-window-to-group-8
  "s-C-9" #'move-window-to-group-9
  "s-S-1" #'move-window-to-group-1 "s-S-2" #'move-window-to-group-2
  "s-S-3" #'move-window-to-group-3 "s-S-4" #'move-window-to-group-4
  "s-S-5" #'move-window-to-group-5 "s-S-6" #'move-window-to-group-6
  "s-S-7" #'move-window-to-group-7 "s-S-8" #'move-window-to-group-8
  "s-S-9" #'move-window-to-group-9
  ;; Screenshots, as niri: Control an area, Shift the screen, Alt the window
  "s-C-p" #'screenshot-area
  "s-S-p" #'screenshot-screen
  "s-M-p" #'screenshot-window
  ;; The desktop
  "s-b" #'mode-line
  "s-C-SPC" #'theme-menu
  "s-C-S-SPC" #'next-theme)

;;; The same on the C-t prefix map, StumpWM style, for a session where
;;; SUPER is taken: Mahogany nested in another compositor, say. C-t N
;;; and C-t g N (the groups) are in key-bindings.lisp with the map.

(define-keys *root-map*
  "SPC" #'launcher-apps
  "\"" #'launcher-windows
  "x" #'launcher-commands
  "m" #'launcher-menu
  "Left" #'focus-left "Down" #'focus-down "Up" #'focus-up "Right" #'focus-right
  "M-Left" #'move-window-left "M-Down" #'move-window-down
  "M-Up" #'move-window-up "M-Right" #'move-window-right
  "S-Left" #'focus-output-left "S-Down" #'focus-output-down
  "S-Up" #'focus-output-up "S-Right" #'focus-output-right
  "f" #'fullscreen-toggle)

;;; Autostart

(config:defconfig *autostart* '()
  list
  "Programs started with the session, once the compositor is up: each
a list of arguments or a shell command string, such as
(\"xwayland-satellite\") or \"mako\". A program that is not installed is
logged and skipped.")

(defun run-autostart ()
  "Start xwayland-satellite and the programs in *autostart*, a moment
after the server is up."
  (when (or *autostart* *xwayland*)
    (let ((timer (hrt:server-make-timer
                  (state-server *compositor-state*)
                  (lambda (timer)
                    (hrt:timer-handle-destroy timer)
                    (start-xwayland)
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
