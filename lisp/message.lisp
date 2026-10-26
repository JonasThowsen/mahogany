(in-package #:mahogany)

(config:defconfig *message-gravity* :gravity-center
  hrt:toast-message-gravity
  "Where toast messages are placed on the screen")

(config:defconfig *message-delay* 3000
  fixnum
  "How long toast messages are displayed by default, in milliseconds")

(config:defconfig *message-theme* (mh/theme:make-theme)
  mh/theme:theme
  "Theme data for displaying toast messages")

(config:defconfig *message-error-theme*
    (mh/theme:augment-theme
     *message-theme*
     :font-color (colors:rgb 1.0 0.0 0.0)
     :border-color (colors:rgb 1.0 0.0 0.0))
  mh/theme:theme
  "Theme data for error messages")

(defglobal *close-message-on-key* nil
  "True while the message shown should go away at the next key press.")

(defun toast-message (state text &key (gravity *message-gravity*)
                                   (ms-delay *message-delay*)
                                   (theme *message-theme*)
                                   close-on-key)
  "Show TEXT in a message on the current output for MS-DELAY
milliseconds (0: until close-message, or a key when CLOSE-ON-KEY), in
place of the message shown before. When CLOSE-ON-KEY is true, the next
key press takes it down; the key still does what it does."
  (declare (type mahogany-state state))
  (with-accessors ((cur-group state-current-group)
                   (hrt-server state-server))
      state
    (let* ((cur-output (group-current-output cur-group)))
      (setf *close-message-on-key* close-on-key)
      (hrt:toast-message hrt-server cur-output text
                         gravity
                         theme
                         ms-delay))))

(defun close-message (state)
  "Take down the message being shown, if there is one."
  (declare (type mahogany-state state))
  (setf *close-message-on-key* nil)
  (hrt:hrt-toast-message-close (state-server state)))
