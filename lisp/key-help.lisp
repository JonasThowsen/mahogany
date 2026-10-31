(in-package #:mahogany)

;;; The key help: every binding active now, drawn by Lisp on a canvas
;;; over the current output in as many columns as fit, the way niri's
;;; hotkey overlay looks. Typing narrows it to the keys and commands
;;; that contain the text; Escape, or a click on it, takes it down.

(config:defconfig *key-help-padding* 16
  (integer 0 100)
  "Pixels of room inside the key help's box.")

(defglobal *key-help* nil
  "The open key help, a plist (:canvas CANVAS :output OUTPUT :entries
ENTRIES :filter STRING :previous-grab GRAB), or NIL.")

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

(defun %key-help-matches (entries filter)
  "The entries whose key or command contains FILTER, case ignored; all
of them for an empty FILTER."
  (if (zerop (length filter))
      entries
      (remove-if-not (lambda (entry)
                       (or (search filter (car entry) :test #'char-equal)
                           (search filter (cdr entry) :test #'char-equal)))
                     entries)))

(defun %key-help-draw (canvas output entries filter total)
  "Draw ENTRIES, the matches of FILTER among TOTAL bindings, on CANVAS
over OUTPUT, centred."
  (let* ((theme *menu-theme*)
         (font (mh/theme:theme-font theme))
         (pad *key-help-padding*)
         (title (format nil "Keys (~D~:[ of ~D~;~*~]) — type to search~@[: ~A~] · Esc closes"
                        (length entries) (= (length entries) total) total
                        (and (plusp (length filter)) filter)))
         (row-height 0) (key-width 0) (command-width 0) (title-width 0))
    (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
      ;; Measure once: a line's height, the widest key and command.
      (draw:with-image-surface (surface 1 1)
        (draw:with-context (cr surface)
          (multiple-value-bind (w h) (draw:text-size cr "Xg" :font font)
            (declare (ignore w))
            (setf row-height (+ h 4)))
          (setf title-width (draw:text-size cr title :font font))
          (loop for (key . command) in entries
                do (setf key-width (max key-width (draw:text-size cr key :font font))
                         command-width (max command-width (draw:text-size cr command :font font))))))
      (let* ((max-rows (max 1 (floor (- output-height (* 4 pad) row-height) row-height)))
             ;; As few columns as the height allows, each as wide as
             ;; its text, or narrower when they would not fit the
             ;; width: then the commands are cut short.
             (columns (max 1 (ceiling (length entries) max-rows)))
             (rows (max 1 (ceiling (length entries) columns)))
             (columns (max 1 (ceiling (length entries) rows)))
             (column-width (min (+ key-width pad command-width (* 2 pad))
                                (floor (- output-width (* 2 pad)) columns)))
             (key-width (min key-width (floor (* column-width 0.4))))
             (command-width (max 20 (- column-width key-width pad (* 2 pad))))
             (width (min (- output-width (* 2 pad))
                         (max (+ (* columns column-width) (* 2 pad))
                              (+ title-width (* 2 pad)))))
             (height (+ (* 3 pad) row-height (* (max 1 (min rows (length entries))) row-height)))
             (x (round (- output-width width) 2))
             (y (round (- output-height height) 2)))
        (hrt:canvas-set-position canvas (max 0 x) (max 0 y))
        (hrt:with-canvas-frame (cr canvas width height)
          (draw:clear cr '(0 0 0 0))
          (draw:fill-rounded-rectangle cr 0 0 width height *menu-radius*
                                       (mh/theme:theme-background-color theme))
          (draw:stroke-rounded-rectangle cr 0 0 width height *menu-radius*
                                         :color (mh/theme:theme-border-color theme) :line-width 2)
          (draw:draw-text cr title pad pad :font font
                          :color (mh/theme:theme-font-color theme)
                          :width (- width (* 2 pad)) :ellipsize :end)
          (if (null entries)
              (draw:draw-text cr "No key matches" (* 2 pad) (+ (* 2 pad) row-height)
                              :font font :color (mh/theme:theme-font-color theme))
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
                                                :width command-width :ellipsize :end)))))))))

(defun %key-help-redraw ()
  (alexandria:when-let ((help *key-help*))
    (let ((entries (getf help :entries)))
      (%key-help-draw (getf help :canvas) (getf help :output)
                      (%key-help-matches entries (getf help :filter))
                      (getf help :filter) (length entries)))))

(defun %key-help-key (key text)
  "A key press while the help shows: Escape closes it, Backspace and
plain text edit the search, the rest is ignored."
  (let ((modifiers (logand (key-modifier-mask key)
                           (logior mahogany/keyboard::+modifier-ctrl+
                                   mahogany/keyboard::+modifier-alt+
                                   mahogany/keyboard::+modifier-super+))))
    (cond ((= (key-keysym key) +key-escape+)
           (key-help-close))
          ((= (key-keysym key) +key-backspace+)
           (let ((filter (getf *key-help* :filter)))
             (when (plusp (length filter))
               (setf (getf *key-help* :filter) (subseq filter 0 (1- (length filter))))
               (%key-help-redraw))))
          ((and text (zerop modifiers))
           (setf (getf *key-help* :filter)
                 (concatenate 'string (getf *key-help* :filter) text))
           (%key-help-redraw)))))

(defun show-key-help ()
  "Show every key binding that is active now; typing searches it, Escape
closes it."
  (key-help-close)
  (menu-close)
  (let ((output (current-output))
        (entries (%active-bindings)))
    (unless output
      (return-from show-key-help nil))
    (let ((canvas (hrt:make-canvas output :layer :layer-overlay)))
      (setf (hrt:canvas-on-button canvas)
            (lambda (canvas x y button pressed)
              (declare (ignore canvas x y button))
              (when pressed (key-help-close))))
      (setf *key-help*
            (list :canvas canvas
                  :output output
                  :entries entries
                  :filter ""
                  :previous-grab (grab-keys #'%key-help-key)))
      (%key-help-redraw)
      canvas)))
