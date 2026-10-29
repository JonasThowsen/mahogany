(in-package #:mahogany)

;;; Messages (toasts): a card drawn by Lisp on a canvas, the way mako
;;; shows notifications: at the top right of the current output by
;;; default, rounded, with a border in the theme's accent, or in its
;;; error color for an error. It goes after *message-delay*
;;; milliseconds, or at the next key press when asked.

;; In group.lisp and canvas.lisp, which load after this file:
(declaim (ftype function group-current-output))

(config:defconfig *message-gravity* :gravity-top-right
  (member :gravity-top-right :gravity-top-left :gravity-bottom-right :gravity-bottom-left
          :gravity-right :gravity-left :gravity-top :gravity-bottom :gravity-center)
  "Where messages are placed on the output.")

(config:defconfig *message-delay* 3000
  fixnum
  "How long toast messages are displayed by default, in milliseconds")

(config:defconfig *message-margin* 20
  fixnum
  "Layout pixels between a message and the edge of the output's usable
area (below the mode-line).")

(config:defconfig *message-width* 420
  fixnum
  "The width of a message card in layout pixels; longer text wraps.")

(config:defconfig *message-theme* (mh/theme:make-theme)
  mh/theme:theme
  "Font and colors of messages; the border color is the card's edge.")

(config:defconfig *message-error-theme*
    (mh/theme:augment-theme
     *message-theme*
     :border-color (colors:rgb 1.0 0.0 0.0))
  mh/theme:theme
  "Font and colors of error messages")

(defglobal *close-message-on-key* nil
  "True while the message shown should go away at the next key press.")

(defglobal *message-canvas* nil
  "The canvas of the message shown, or NIL.")

(defglobal *message-timer* nil
  "The timer that takes the message down, made once and armed per message.")

(defun close-message (state)
  "Take down the message being shown, if there is one."
  (declare (ignore state))
  (setf *close-message-on-key* nil)
  (when *message-timer*
    (hrt:timer-handle-update *message-timer* 0))
  (when *message-canvas*
    (unless (hrt:canvas-destroyed-p *message-canvas*)
      (hrt:canvas-destroy *message-canvas*))
    (setf *message-canvas* nil)))

(defun %message-place (gravity area-x area-y area-width area-height width height margin)
  "Where a card of WIDTH x HEIGHT goes in the area, by GRAVITY."
  (let ((left (+ area-x margin))
        (right (- (+ area-x area-width) margin width))
        (center-x (+ area-x (round (- area-width width) 2)))
        (top (+ area-y margin))
        (bottom (- (+ area-y area-height) margin height))
        (center-y (+ area-y (round (- area-height height) 2))))
    (ecase gravity
      (:gravity-top-right (values right top))
      (:gravity-top-left (values left top))
      (:gravity-bottom-right (values right bottom))
      (:gravity-bottom-left (values left bottom))
      (:gravity-right (values right center-y))
      (:gravity-left (values left center-y))
      (:gravity-top (values center-x top))
      (:gravity-bottom (values center-x bottom))
      (:gravity-center (values center-x center-y)))))

(defun toast-message (state text &key (gravity *message-gravity*)
                                   (ms-delay *message-delay*)
                                   (theme *message-theme*)
                                   close-on-key)
  "Show TEXT in a message on the current output for MS-DELAY
milliseconds (0: until close-message, or a key when CLOSE-ON-KEY), in
place of the message shown before. When CLOSE-ON-KEY is true, the next
key press takes it down; the key still does what it does."
  (declare (type mahogany-state state))
  (let ((output (and (state-current-group state)
                     (group-current-output (state-current-group state)))))
    (unless (and output (state-server state))
      (log-string :info "Message: ~A" text)
      (return-from toast-message nil))
    (close-message state)
    (setf *close-message-on-key* close-on-key)
    (let ((font (mh/theme:theme-font theme))
          (pad 14)
          (border 2)
          (radius 10)
          (canvas (hrt:make-canvas output :layer :layer-overlay)))
      (multiple-value-bind (area-x area-y area-width area-height) (hrt:output-usable-area output)
        (let* ((width (min *message-width* (max 100 (- area-width (* 2 *message-margin*)))))
               (text-width (- width (* 2 (+ pad border))))
               (text-height 0))
          ;; Measure off screen, so the canvas shows one frame only:
          (draw:with-image-surface (surface 1 1)
            (draw:with-context (cr surface)
              (draw:with-layout (layout cr :text text :font font :width text-width)
                (setf text-height (nth-value 1 (draw:layout-pixel-size layout))))))
          (let ((height (+ text-height (* 2 (+ pad border)))))
            (multiple-value-bind (x y)
                (%message-place gravity area-x area-y area-width area-height
                                width height *message-margin*)
              (hrt:canvas-set-position canvas (max 0 x) (max 0 y)))
            (hrt:with-canvas-frame (cr canvas width height)
              (draw:clear cr '(0 0 0 0))
              (draw:fill-rounded-rectangle cr 0 0 width height radius
                                           (mh/theme:theme-background-color theme))
              (draw:stroke-rounded-rectangle cr 0 0 width height radius
                                             :color (mh/theme:theme-border-color theme)
                                             :line-width border)
              (draw:draw-text cr text (+ pad border) (+ pad border)
                              :font font :color (mh/theme:theme-font-color theme)
                              :width text-width)))
          (setf *message-canvas* canvas)
          (when (plusp ms-delay)
            (unless *message-timer*
              (setf *message-timer*
                    (hrt:server-make-timer (state-server state)
                                           (lambda (timer)
                                             (declare (ignore timer))
                                             (close-message state)))))
            (hrt:timer-handle-update *message-timer* ms-delay))
          canvas)))))
