(in-package #:mahogany)

;;; The on-screen display: a small panel with a label and a bar that
;;; shows for a moment after the volume or the brightness changed, like
;;; swayosd.

(config:defconfig *osd-timeout* 1500
  fixnum
  "Milliseconds the on-screen display stays.")

(config:defconfig *osd-position* :top
  (member :top :center :bottom)
  "Where the on-screen display appears on the output.")

(config:defconfig *osd-theme*
    (mh/theme:make-theme :font "monospace 12"
                         :font-color (colors:rgb 0.9 0.9 0.9)
                         :background-color (colors:rgb 0.1 0.1 0.12)
                         :border-color (colors:rgb 0.8 0.3 0.2))
  mh/theme:theme
  "Font and colors of the on-screen display; the border color fills the bar.")

(defglobal *osd-canvas* nil)
(defglobal *osd-timer* nil)

(defun osd-hide ()
  "Take the on-screen display down."
  (when *osd-timer*
    (hrt:timer-handle-destroy *osd-timer*)
    (setf *osd-timer* nil))
  (when *osd-canvas*
    (hrt:canvas-destroy *osd-canvas*)
    (setf *osd-canvas* nil)))

(defun %osd-timer-fired (timer)
  (declare (ignore timer))
  (setf *osd-timer* nil)
  (osd-hide))

(defun osd-show (label &key percent icon)
  "Show LABEL, with ICON before it and a bar at PERCENT when given, on
the current output for *osd-timeout* milliseconds. A display already
shown is replaced."
  (let ((output (group-current-output (state-current-group *compositor-state*))))
    (unless output
      (return-from osd-show nil))
    (when (and *osd-canvas* (not (hrt:output= (hrt:canvas-output *osd-canvas*) output)))
      (osd-hide))
    (let* ((theme *osd-theme*)
           (font (mh/theme:theme-font theme))
           (pad 14)
           (canvas (or *osd-canvas*
                       (setf *osd-canvas* (hrt:make-canvas output :layer :layer-overlay)))))
      (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
        (let* ((width (max 220 (round output-width 5)))
               (text (if icon (format nil "~A  ~A" icon label) label))
               (text-height 0)
               ;; with-canvas-frame returns whether the frame was shown, so
               ;; the measurement is taken out through the variable:
               (measured (hrt:with-canvas-frame (cr canvas width 1)
                           (setf text-height (nth-value 1 (draw:text-size cr text :font font)))))
               (bar-height (progn measured (if percent 6 0)))
               (height (+ pad text-height (if percent (+ 10 bar-height) 0) pad))
               (x (round (- output-width width) 2))
               (y (ecase *osd-position*
                    (:top (round output-height 10))
                    (:center (round (- output-height height) 2))
                    (:bottom (- output-height height (round output-height 10))))))
          (hrt:canvas-set-position canvas x y)
          (hrt:with-canvas-frame (cr canvas width height)
            (draw:clear cr '(0 0 0 0))
            (draw:fill-rounded-rectangle cr 0 0 width height 10
                                         (mh/theme:theme-background-color theme))
            (draw:draw-text cr text pad pad :font font
                                            :color (mh/theme:theme-font-color theme)
                                            :width (- width (* 2 pad)) :ellipsize :end)
            (when percent
              (let ((bar-y (+ pad text-height 10))
                    (bar-width (- width (* 2 pad))))
                (draw:fill-rounded-rectangle cr pad bar-y bar-width bar-height 3
                                             (%dim (mh/theme:theme-font-color theme) 0.25))
                (draw:fill-rounded-rectangle cr pad bar-y
                                             (round (* bar-width (max 0 (min 100 percent))) 100)
                                             bar-height 3
                                             (mh/theme:theme-border-color theme)))))))
      ;; (Re)start the timer that takes it down:
      (unless *osd-timer*
        (setf *osd-timer* (hrt:server-make-timer (state-server *compositor-state*)
                                                 #'%osd-timer-fired)))
      (hrt:timer-handle-update *osd-timer* *osd-timeout*)
      canvas)))

;;; The keys

(defun %show-volume (status)
  (if status
      (let ((muted (getf status :muted)) (percent (getf status :percent)))
        (osd-show (if muted "Muted" (format nil "Volume ~D%" percent))
                  :percent (if muted 0 percent)
                  :icon (if muted (icon :volume-muted) (icon :volume))))
      (toast-message *compositor-state* "No audio (wpctl)" :theme *message-error-theme*))
  (mode-line-update))

(defcommand volume-up ()
  (:documentation "Turn the volume up")
  (:method () (volume-change *volume-step* #'%show-volume)))

(defcommand volume-down ()
  (:documentation "Turn the volume down")
  (:method () (volume-change (- *volume-step*) #'%show-volume)))

(defcommand volume-mute ()
  (:documentation "Mute the audio, or unmute it")
  (:method () (volume-toggle-mute #'%show-volume)))

(defcommand microphone-mute ()
  (:documentation "Mute the microphone, or unmute it")
  (:method () (microphone-toggle-mute (lambda () (osd-show "Microphone toggled" :icon (icon :microphone))))))

(defun %show-brightness (percent)
  (if percent
      (osd-show (format nil "Brightness ~D%" percent) :percent percent :icon (icon :brightness))
      (toast-message *compositor-state* "No backlight (brightnessctl)" :theme *message-error-theme*))
  (mode-line-update))

(defcommand brightness-up ()
  (:documentation "Turn the screen brightness up")
  (:method () (brightness-change *brightness-step* #'%show-brightness)))

(defcommand brightness-down ()
  (:documentation "Turn the screen brightness down")
  (:method () (brightness-change (- *brightness-step*) #'%show-brightness)))

;;; The keys every keyboard has for these, outside any prefix:
(define-key *top-map* (kbd "XF86AudioRaiseVolume") #'volume-up)
(define-key *top-map* (kbd "XF86AudioLowerVolume") #'volume-down)
(define-key *top-map* (kbd "XF86AudioMute") #'volume-mute)
(define-key *top-map* (kbd "XF86AudioMicMute") #'microphone-mute)
(define-key *top-map* (kbd "XF86MonBrightnessUp") #'brightness-up)
(define-key *top-map* (kbd "XF86MonBrightnessDown") #'brightness-down)
