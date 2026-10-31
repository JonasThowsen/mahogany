(in-package #:mahogany)

(declaim (type fixnum *keyboard-focus-bits*
               +click-mask+
               +wheel-mask+
               +sloppy-mask+))
(defconstant +click-mask+ 1)
(defconstant +wheel-mask+ (ash 1 1))
(defconstant +sloppy-mask+ (ash 1 2))

(defglobal *keyboard-focus-bits* +click-mask+)

(config-system:define-setf-config
    (keyboard-focus-type :click
     :type (member :click-and-wheel :click :ignore :sloppy))
    "How keyboard focus is changed based on mouse input.
Values:
  :click
     Change when a button on the mouse is clicked
  :click-and-wheel
     Change when a button is clicked or the scroll whell is used.
  :sloppy (not implemented)
     Change focus when the mouse is moved over surface, is clicked,
     or the wheel is used.
  :ignore
     Do not change focus after the mouse is used."
  (:setter (val)
           (setf *keyboard-focus-bits*
                 (case val
                   (:click-and-wheel
                    (logior +click-mask+ +wheel-mask+))
                   (:sloppy
                    (logior +click-mask+ +wheel-mask+ +sloppy-mask+))
                   (:click
                    +click-mask+)
                   (:ignore 0)))
           val)
  (:getter ()
           (macrolet ((not-set-p (&rest args)
                        `(= *keyboard-focus-bits* (logior ,@args))))
             (cond
               ((not-set-p +click-mask+ +wheel-mask+ +sloppy-mask+)
                :sloppy)
               ((not-set-p +click-mask+ +wheel-mask+)
                :click-and-wheel)
               ((not-set-p +click-mask+)
                :click)
               ((= *keyboard-focus-bits* 0)
                :ignore)))))

;; wl_keyboard.repeat_info has two int32 and the protocol requires both to be non-negative.
(deftype keyboard-repeat-value () '(unsigned-byte 31))

(declaim (type keyboard-repeat-value *keyboard-repeat-rate* *keyboard-repeat-delay*))
;; wlroots default, so we don't need to update at startup.
(defglobal *keyboard-repeat-rate* 25)
(defglobal *keyboard-repeat-delay* 600)

(defun %apply-keyboard-repeat ()
  "Push the current repeat settings to the seat."
  (when (state-server *compositor-state*)
    (hrt:hrt-seat-set-repeat-info (server-seat *compositor-state*)
                                  *keyboard-repeat-rate*
                                  *keyboard-repeat-delay*)))

(config-system:define-setf-config
    (keyboard-repeat-rate 25 :type keyboard-repeat-value)
    "How many times a second a held key repeats, in Hz. 0 disables repeat."
  (:setter (val)
           (setf *keyboard-repeat-rate* val)
           (%apply-keyboard-repeat)
           val)
  (:getter () *keyboard-repeat-rate*))

(config-system:define-setf-config
    (keyboard-repeat-delay 600 :type keyboard-repeat-value)
    "How long a key must be held before it starts repeating, in milliseconds."
  (:setter (val)
           (setf *keyboard-repeat-delay* val)
           (%apply-keyboard-repeat)
           val)
  (:getter () *keyboard-repeat-delay*))

(defglobal *touchpad-tap-to-click* t)
(defglobal *touchpad-disable-while-typing* :default)
(defglobal *touchpad-accel-speed* nil)
(defglobal *touchpad-natural-scroll* :default)
(defglobal *mouse-natural-scroll* :default)
(defglobal *mouse-accel-speed* nil)
(defglobal *numlock* nil)

(deftype touchpad-state () '(member :default t nil))

(defun %touchpad-state (val)
  (declare (type touchpad-state val))
  (ecase val
    (:default :hrt-touchpad-default)
    ((t) :hrt-touchpad-enabled)
    ((nil) :hrt-touchpad-disabled)))

(config-system:define-setf-config
    (touchpad-tap-to-click t :type touchpad-state)
    "Whether tapping the touchpad is a click: one finger left, two right,
three middle.

Applies to every tap-capable touchpad, and to any plugged in later. :default
goes back to libinput default for each device."
  (:setter (val)
           (setf *touchpad-tap-to-click* val)
           (when (state-server *compositor-state*)
             (hrt:hrt-seat-set-touchpad-tap (server-seat *compositor-state*)
                                            (%touchpad-state val)))
           val)
  (:getter () *touchpad-tap-to-click*))

(config-system:define-setf-config
    (touchpad-disable-while-typing :default :type touchpad-state)
    "Whether the touchpad stops responding while you are typing.

Applies to every touchpad that supports it, and to any plugged in later.
:default goes back to libinput default for each device."
  (:setter (val)
           (setf *touchpad-disable-while-typing* val)
           (when (state-server *compositor-state*)
             (hrt:hrt-seat-set-touchpad-dwt (server-seat *compositor-state*)
                                            (%touchpad-state val)))
           val)
  (:getter () *touchpad-disable-while-typing*))

(config-system:define-setf-config
    (touchpad-accel-speed nil :type (or null (real -1 1)))
    "Pointer speed for the touchpad, from -1 (slowest) through 0 to 1 (fastest).
NIL goes back to libinput's default, which is the same as 0."
  (:setter (val)
           (setf *touchpad-accel-speed* val)
           (when (state-server *compositor-state*)
             (let ((seat (server-seat *compositor-state*)))
               (if val
                   (hrt:hrt-seat-set-touchpad-accel seat (float val 1.0d0))
                   (hrt:hrt-seat-reset-touchpad-accel seat))))
           val)
  (:getter () *touchpad-accel-speed*))

(config-system:define-setf-config
    (touchpad-natural-scroll :default :type touchpad-state)
    "Whether the touchpad scrolls the content the way the fingers move,
as a phone does: T, NIL, or :default for libinput's default (off)."
  (:setter (val)
           (setf *touchpad-natural-scroll* val)
           (when (state-server *compositor-state*)
             (hrt:hrt-seat-set-touchpad-natural-scroll (server-seat *compositor-state*)
                                                       (%touchpad-state val)))
           val)
  (:getter () *touchpad-natural-scroll*))

(config-system:define-setf-config
    (mouse-natural-scroll :default :type touchpad-state)
    "Whether the wheel of a mouse (or any pointer that is not a touchpad)
scrolls reversed: T, NIL, or :default for libinput's default (off)."
  (:setter (val)
           (setf *mouse-natural-scroll* val)
           (when (state-server *compositor-state*)
             (hrt:hrt-seat-set-mouse-natural-scroll (server-seat *compositor-state*)
                                                    (%touchpad-state val)))
           val)
  (:getter () *mouse-natural-scroll*))

(config-system:define-setf-config
    (mouse-accel-speed nil :type (or null (real -1 1)))
    "Pointer speed for mice and other pointers that are not touchpads,
from -1 (slowest) through 0 to 1 (fastest). NIL is libinput's default."
  (:setter (val)
           (setf *mouse-accel-speed* val)
           (when (state-server *compositor-state*)
             (let ((seat (server-seat *compositor-state*)))
               (if val
                   (hrt:hrt-seat-set-mouse-accel seat (float val 1.0d0))
                   (hrt:hrt-seat-reset-mouse-accel seat))))
           val)
  (:getter () *mouse-accel-speed*))

(config-system:define-setf-config
    (numlock nil :type boolean)
    "Whether Num Lock is on when the session starts, and on every keyboard
plugged in later."
  (:setter (val)
           (setf *numlock* val)
           (when (state-server *compositor-state*)
             (hrt:hrt-seat-set-numlock (server-seat *compositor-state*) val))
           val)
  (:getter () *numlock*))

(defun apply-input-settings ()
  "Push the input settings to heart: called once the server is up, as
the settings set before then only remember the values."
  (let ((seat (server-seat *compositor-state*)))
    (hrt:hrt-seat-set-touchpad-tap seat (%touchpad-state *touchpad-tap-to-click*))
    (hrt:hrt-seat-set-touchpad-dwt seat (%touchpad-state *touchpad-disable-while-typing*))
    (hrt:hrt-seat-set-touchpad-natural-scroll seat (%touchpad-state *touchpad-natural-scroll*))
    (hrt:hrt-seat-set-mouse-natural-scroll seat (%touchpad-state *mouse-natural-scroll*))
    (if *touchpad-accel-speed*
        (hrt:hrt-seat-set-touchpad-accel seat (float *touchpad-accel-speed* 1.0d0))
        (hrt:hrt-seat-reset-touchpad-accel seat))
    (if *mouse-accel-speed*
        (hrt:hrt-seat-set-mouse-accel seat (float *mouse-accel-speed* 1.0d0))
        (hrt:hrt-seat-reset-mouse-accel seat))
    (hrt:hrt-seat-set-numlock seat *numlock*)
    (%apply-keyboard-repeat)
    (%apply-cursor-theme)))

(defun %unkown-keybinding-message (key-state last)
  (declare (optimize (speed 3) (safety 0))
           (type key-state key-state)
           (type key last))
  (with-output-to-string (s)
    (format s "Keybinding \"")
    (dolist (k (reverse (key-state-sequence key-state)))
      (pprint-key k s)
      (format s " "))
    (pprint-key last s)
    (format s "\"~%is undefined.")))

(defun check-and-run-keybinding (key seat key-state)
  (declare (type key key)
           (type key-state key-state)
           (optimize (speed 3)))
  (when (not (key-modifier-key-p key))
    (let* ((handling-keybinding (key-state-active-p key-state)))
      (flet ((reset-state ()
               (log-string :trace "Reseting keyboard state")
               (state-ungrab-seat *compositor-state*)
               (server-keystate-reset *compositor-state*)))
        (multiple-value-bind (matched result)
            (key-state-advance key key-state)
          (cond
            (;; A known keybinding was pressed:
             matched
             (cond
               (result
                (reset-state)
                ;; Only consume the pressed key if we have a command
                ;; and not a special keyword:
                (if (eq :pass-through result)
                    (return-from check-and-run-keybinding nil)
                    (execute-command result
		                             (key-state-sequence key-state) seat)))
               (t (state-grab-seat *compositor-state*)
                  t)))
            (;; No keybinding was pressed but we were expecting one.
             handling-keybinding
             (toast-message *compositor-state* (%unkown-keybinding-message key-state key))
             (reset-state)
             ;; Since we still took an action (canceling the keybinding),
             ;; still consume the pressed key
             t)
            ;; No action was taken, don't consume the pressed key:
            (t  nil)))))))

(defun handle-key-event (state key seat event-state)
  (declare (type key key)
           (type (unsigned-byte 32) event-state)
           (type mahogany-state state)
           (optimize (speed 3)))
  (let ((key-state (state-key-state state)))
    (declare (type key-state key-state))
    (if (= event-state wl:+wl-keyboard-key-state-pressed+)
        (check-and-run-keybinding key seat key-state)
        (key-state-active-p key-state))))

(defun %focus-frame-under-cursor (seat)
  (declare (optimize (speed 2)))
  (declare (type cffi:foreign-pointer seat))
  (let* ((lx (hrt:hrt-seat-cursor-lx seat))
         (ly (hrt:hrt-seat-cursor-ly seat))
         ;; The frame under the cursor is in the group shown on the
         ;; output there:
         (found (silence-notes
                  (loop for group being the hash-values
                          of (state-output-groups *compositor-state*)
                        thereis (or (group-floating-frame-at group lx ly)
                                    (tree:frame-at (mahogany-group-tiled-container group)
                                                   lx ly))))))
    (if found
        (let ((hrt:*in-pointer-event* t))
          (state-focus-frame *compositor-state* found seat))
        nil)))

(hrt:define-hrt-callback handle-mouse-wheel-event :void
    ((seat (:pointer (:struct hrt:hrt-seat)))
     (event :pointer))
    ()
  (declare (optimize (speed 3))
           #+sbcl
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (when (not (zerop (logand *keyboard-focus-bits* +wheel-mask+)))
    (%focus-frame-under-cursor seat))
  (hrt:hrt-seat-notify-axis seat event))

(hrt:define-hrt-callback handle-mouse-button-event :void
    ((seat (:pointer (:struct hrt:hrt-seat)))
     (event :pointer))
    ()
  (declare (optimize (speed 3))
           #+sbcl
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (when (not (zerop (logand *keyboard-focus-bits* +click-mask+)))
    (%focus-frame-under-cursor seat))
  (hrt:hrt-seat-notify-button seat event))

;;; A key grab: while a Lisp widget (a menu, a prompt) has it, every key
;;; press goes to its function and to nothing else, keybindings included.

(defglobal *key-grab* nil
  "A function of (key text) taking every key press while a widget has the
keyboard, or NIL. TEXT is what the key types, a string, or NIL.")

(defglobal *grab-repeat* nil
  "The key held down in a grab, repeating: a plist (:timer TIMER :keysym
KEYSYM), or NIL.")

(defun %grab-repeat-stop ()
  "The held key was let go, or the grab ended: no more repeats."
  (alexandria:when-let ((repeat *grab-repeat*))
    (setf *grab-repeat* nil)
    (hrt:timer-handle-destroy (getf repeat :timer))))

(defun %grab-repeat-start (grab key text)
  "KEY was pressed into GRAB: send it again after *keyboard-repeat-delay*
and then *keyboard-repeat-rate* times a second, as a client would
repeat it, until it is released or the grab changes. A widget's
Backspace has to repeat like a client's."
  (%grab-repeat-stop)
  (when (plusp *keyboard-repeat-rate*)
    (let ((timer (hrt:server-make-timer
                  (state-server *compositor-state*)
                  (lambda (timer)
                    (cond ((and (eq *key-grab* grab)
                                *grab-repeat*
                                (eq (getf *grab-repeat* :timer) timer))
                           (handler-case (funcall grab key text)
                             (error (c)
                               (log-string :error "Key grab ~S (repeat): ~A" grab c)
                               (ungrab-keys)))
                           ;; The grab may have ended in there:
                           (if (and *grab-repeat* (eq (getf *grab-repeat* :timer) timer))
                               (hrt:timer-handle-update
                                timer (max 1 (round 1000 *keyboard-repeat-rate*)))
                               (hrt:timer-handle-destroy timer)))
                          (t
                           (when (and *grab-repeat* (eq (getf *grab-repeat* :timer) timer))
                             (setf *grab-repeat* nil))
                           (hrt:timer-handle-destroy timer)))))))
      (setf *grab-repeat* (list :timer timer :keysym (key-keysym key)))
      (hrt:timer-handle-update timer *keyboard-repeat-delay*))))

(defun grab-keys (function)
  "Send every key press to FUNCTION, called with the key and the text it
types (a string or NIL), until ungrab-keys. A key held down repeats
into it as it would into a client. Returns the previous grab."
  (declare (type function function))
  (%grab-repeat-stop)
  (prog1 *key-grab*
    (setf *key-grab* function)))

(defun ungrab-keys (&optional previous)
  "End the key grab, or go back to PREVIOUS, the grab there was before."
  (%grab-repeat-stop)
  (setf *key-grab* previous))

(defun key-text (key)
  "What KEY types: a string of one character (or more for some keysyms),
or NIL for keys that type nothing, such as Shift or F1."
  (cffi:with-foreign-object (buffer :char 8)
    (let ((length (xkb:keysym-to-utf8 (key-keysym key) buffer 8)))
      (when (> length 1)                ; the length counts the NUL
        (let ((text (cffi:foreign-string-to-lisp buffer :count (1- length))))
          ;; Control characters type nothing readable:
          (if (and (= (length text) 1) (< (char-code (char text 0)) 32))
              nil
              text))))))

(hrt:define-hrt-callback keyboard-callback :bool
    ((seat (:pointer (:struct hrt:hrt-seat)))
     (info (:pointer (:struct hrt:hrt-keypress-info))))
    ()
  (declare (optimize (speed 3))
           #+sbcl
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (cffi:with-foreign-slots ((hrt:keysyms hrt:modifiers hrt:keysyms-len hrt:wl-key-state)
                            info (:struct hrt:hrt-keypress-info))
    (when *close-message-on-key*
      (close-message *compositor-state*))
    ;; A key let go stops its repeat into a grab, whichever key: a
    ;; held key is the one that matters, and it goes when any does.
    ;; That is all a release is for here; heart forwards it anyway.
    (unless (= hrt:wl-key-state wl:+wl-keyboard-key-state-pressed+)
      (%grab-repeat-stop)
      (return-from keyboard-callback nil))
    ;; A widget has the keyboard: it gets the key, nothing else does.
    (when (and *key-grab* (= hrt:wl-key-state wl:+wl-keyboard-key-state-pressed+))
      (when (plusp hrt:keysyms-len)
        (let ((key (make-key (cffi:mem-aref hrt:keysyms :uint32 0) hrt:modifiers)))
          (unless (key-modifier-key-p key)
            (let ((grab *key-grab*)
                  (text (key-text key)))
              (handler-case (funcall grab key text)
                (error (c)
                  (log-string :error "Key grab ~S: ~A" grab c)
                  (ungrab-keys)))
              ;; Still grabbed by the same widget: the key repeats while held.
              (when (eq *key-grab* grab)
                (%grab-repeat-start grab key text))))))
      (return-from keyboard-callback t))
    ;; don't check for key commands if we are collecting args:
    (when *collecting-args-p*
      (log-string :trace "Not checking keybinding due to interactive command")
      (return-from keyboard-callback nil))
    ;; I'm not sure why this is an array, but it's what tinywl does:
    (dotimes (i hrt:keysyms-len)
      (let ((key (make-key (cffi:mem-aref hrt:keysyms :uint32 i) hrt:modifiers)))
        (when (handle-key-event *compositor-state* key seat hrt:wl-key-state)
          (return t))))))

;;; The pointer's look: an xcursor theme and size, for Mahogany's own
;;; cursor and, through XCURSOR_THEME and XCURSOR_SIZE, for the programs
;;; it starts.

(defglobal *cursor-theme* nil)
(defglobal *cursor-size* 24)
(defglobal *cursor-theme-exported* nil
  "True when XCURSOR_THEME holds a theme Mahogany set.")

(declaim (ftype function %setenv %unsetenv %update-activation-environment))
(defun %apply-cursor-theme ()
  (when (state-server *compositor-state*)
    (state-set-cursor-theme *compositor-state* *cursor-theme* *cursor-size*))
  ;; No theme: take away the one Mahogany set before, so programs get
  ;; the default (one from the session's own environment is left be):
  (cond (*cursor-theme*
         (%setenv "XCURSOR_THEME" *cursor-theme*)
         (setf *cursor-theme-exported* t))
        (*cursor-theme-exported*
         (%unsetenv "XCURSOR_THEME")
         (setf *cursor-theme-exported* nil)))
  (%setenv "XCURSOR_SIZE" (princ-to-string *cursor-size*))
  (%update-activation-environment "XCURSOR_THEME" "XCURSOR_SIZE"))

(config-system:define-setf-config
    (cursor-theme nil :type (or null string))
    "The xcursor theme, such as \"Adwaita\" or \"Nordzy-cursors\", for
Mahogany's cursor and the programs it starts; NIL for the default."
  (:setter (val)
           (setf *cursor-theme* val)
           (%apply-cursor-theme)
           val)
  (:getter () *cursor-theme*))

(config-system:define-setf-config
    (cursor-size 24 :type (integer 1 512))
    "The cursor's size in logical pixels (it is scaled with the output)."
  (:setter (val)
           (setf *cursor-size* val)
           (%apply-cursor-theme)
           val)
  (:getter () *cursor-size*))

