(in-package #:mahogany)

;;; The key help: every binding active now, drawn by Lisp on a canvas
;;; over the current output in as many columns as fit, the way niri's
;;; hotkey overlay looks. It stays until a key is pressed or it is
;;; clicked; that key press closes it and does nothing else.

(config:defconfig *key-help-padding* 16
  (integer 0 100)
  "Pixels of room inside the key help's box.")

(defglobal *key-help* nil
  "The open key help, a plist (:canvas CANVAS :previous-grab GRAB), or NIL.")

(defun key-help-close ()
  "Take the key help down, if it is showing."
  (alexandria:when-let ((help *key-help*))
    (setf *key-help* nil)
    (ungrab-keys (getf help :previous-grab))
    (hrt:canvas-destroy (getf help :canvas))))

(defun %key-help-columns (entries rows)
  "ENTRIES, (KEY . COMMAND) pairs, split into columns of ROWS."
  (loop for start from 0 below (length entries) by rows
        collect (subseq entries start (min (length entries) (+ start rows)))))

(defun show-key-help ()
  "Show every key binding that is active now, until a key is pressed."
  (key-help-close)
  (menu-close)
  (let* ((output (current-output))
         (theme *menu-theme*)
         (font (mh/theme:theme-font theme))
         (pad *key-help-padding*)
         (entries (%active-bindings)))
    (unless output
      (return-from show-key-help nil))
    (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
      (let* ((canvas (hrt:make-canvas output :layer :layer-overlay))
             (row-height 0) (key-width 0) (command-width 0))
        ;; Measure once: a line's height, the widest key and command.
        (draw:with-image-surface (surface 1 1)
          (draw:with-context (cr surface)
            (multiple-value-bind (w h) (draw:text-size cr "Xg" :font font)
              (declare (ignore w))
              (setf row-height (+ h 4)))
            (loop for (key . command) in entries
                  do (setf key-width (max key-width (draw:text-size cr key :font font))
                           command-width (max command-width (draw:text-size cr command :font font))))))
        (let* ((max-rows (max 1 (floor (- output-height (* 4 pad) row-height) row-height)))
               ;; As few columns as the height allows, each as wide as
               ;; its text, or narrower when they would not fit the
               ;; width: then the commands are cut short.
               (columns (max 1 (ceiling (length entries) max-rows)))
               (rows (ceiling (length entries) columns))
               (columns (ceiling (length entries) rows))
               (column-width (min (+ key-width pad command-width (* 2 pad))
                                  (floor (- output-width (* 2 pad)) columns)))
               (key-width (min key-width (floor (* column-width 0.4))))
               (command-width (max 20 (- column-width key-width pad (* 2 pad))))
               (width (+ (* columns column-width) (* 2 pad)))
               (height (+ (* 3 pad) row-height (* (min rows (length entries)) row-height)))
               (x (round (- output-width width) 2))
               (y (round (- output-height height) 2)))
          (hrt:canvas-set-position canvas (max 0 x) (max 0 y))
          (hrt:with-canvas-frame (cr canvas width height)
            (draw:clear cr '(0 0 0 0))
            (draw:fill-rounded-rectangle cr 0 0 width height *menu-radius*
                                         (mh/theme:theme-background-color theme))
            (draw:stroke-rounded-rectangle cr 0 0 width height *menu-radius*
                                           :color (mh/theme:theme-border-color theme) :line-width 2)
            (draw:draw-text cr (format nil "Keys (~D) — any key closes this" (length entries))
                            pad pad :font font :color (mh/theme:theme-font-color theme))
            (loop for column in (%key-help-columns entries rows)
                  for column-x from (* 2 pad) by column-width
                  do (loop for (key . command) in column
                           for row-y from (+ (* 2 pad) row-height) by row-height
                           do (draw:draw-text cr key column-x row-y :font font
                                              :color (mh/theme:theme-border-color theme)
                                              :width key-width :ellipsize :end)
                              (draw:draw-text cr command (+ column-x key-width pad) row-y
                                              :font font
                                              :color (mh/theme:theme-font-color theme)
                                              :width command-width :ellipsize :end))))
          (setf (hrt:canvas-on-button canvas)
                (lambda (canvas x y button pressed)
                  (declare (ignore canvas x y button))
                  (when pressed (key-help-close))))
          (setf *key-help*
                (list :canvas canvas
                      :previous-grab (grab-keys (lambda (key text)
                                                  (declare (ignore key text))
                                                  (key-help-close)))))
          canvas)))))
