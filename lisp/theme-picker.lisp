(in-package #:mahogany)

;;; The theme picker: the themes as a carousel of cards across the
;;; middle of the screen, as Omarchy has it. Each card is a small
;;; desktop drawn in its theme: the wallpaper, the bar with its group
;;; marker, a focused and an unfocused window with the theme's borders,
;;; gaps and text colors. Drawn, not screenshots, so a new theme has its
;;; card at once. Moving the selection previews the theme on the whole
;;; desktop (preview-theme, as the theme menu does); Return keeps it,
;;; Escape goes back to the theme from before.

(config:defconfig *theme-picker-card-width* 320
  fixnum
  "The width of the selected card in the theme picker, in layout
pixels; the others are smaller. Cards are 16:10.")

(defstruct (theme-picker (:constructor %make-theme-picker))
  (names '() :type list)
  (selected 0 :type fixnum)
  (output nil)
  (canvas nil)
  (previous-grab nil)
  ;; Where the cards were drawn, for the pointer: (X0 X1 INDEX)
  (hits '() :type list))

(defglobal *theme-picker* nil
  "The open theme picker, or NIL.")

(defglobal *theme-thumbnails* (make-hash-table :test 'equal)
  "Wallpapers scaled down for the cards: (file . write date) -> image
surface. Kept, as a wallpaper is decoded at full size to make one.")

;;; A theme's card

(defun %theme-setting (theme symbol)
  "The value of the configuration variable SYMBOL while THEME is in
use: the theme's own setting, else the value the user has, put aside
while another theme's settings are in force."
  (let ((settings (theme-settings theme)))
    (if (member symbol settings)
        (getf settings symbol)
        (let ((saved (assoc symbol *theme-settings-saved*)))
          (if saved (cdr saved) (symbol-value symbol))))))

(defun %theme-thumbnail (file)
  "A thumbnail of the PNG FILE, made once; NIL when it cannot be read."
  (let* ((date (ignore-errors (file-write-date file)))
         (key (cons file date)))
    (or (gethash key *theme-thumbnails*)
        (let ((image (and date (draw:load-png file))))
          (when image
            (unwind-protect
                 (setf (gethash key *theme-thumbnails*)
                       (draw:scaled-image image 640 400))
              (draw:cairo-surface-destroy image)))))))

(defun %card-lines (cr x y width height colors)
  "Lines of text, as bars of COLORS, in the box at X,Y of WIDTH x HEIGHT."
  (let* ((line (max 2 (round height 45)))
         (step (round (* 2.6 line)))
         (lengths '(0.35 0.62 0.24 0.5 0.42 0.7 0.3 0.56 0.2 0.6 0.45 0.33
                    0.52 0.28 0.66 0.4)))
    (loop for row-y from y by step
          for length in lengths
          for color in (alexandria:flatten (make-list 4 :initial-element colors))
          while (<= (+ row-y line) (+ y height))
          do (draw:fill-rectangle cr x row-y (max line (round (* width length))) line color))))

(defun draw-theme-card (cr theme width height)
  "Draw THEME's card, a small desktop in its colors, at the origin of
CR, WIDTH x HEIGHT."
  (let* ((scale (/ width 1000))
         (bar (max 6 (round (* (%theme-setting theme '*mode-line-height*) scale 1.2))))
         (gap (max 2 (round (* (%theme-setting theme 'tree:*window-gap*) scale 1.5))))
         (outer (max 2 (round (* (%theme-setting theme 'tree:*output-gap*) scale 1.5))))
         (border (max 1 (round (* (%theme-setting theme 'tree:*frame-border-width*) scale 1.5))))
         (file (or *wallpaper* (theme-wallpaper theme)))
         (thumbnail (and file (%theme-thumbnail (uiop:native-namestring file)))))
    (draw:save-restore (cr)
      (draw:clip-rectangle cr 0 0 width height)
      ;; The wallpaper:
      (if thumbnail
          (draw:draw-image-cover cr thumbnail width height)
          (draw:fill-linear-gradient cr 0 0 width height
                                     (%wallpaper-gradient-stops (theme-wallpaper-color theme))))
      ;; The bar: the group marker at the left, the clock in the
      ;; middle, the status at the right, as bars of text.
      (draw:fill-rectangle cr 0 0 width bar (theme-background theme))
      (let ((text (max 2 (round bar 3)))
            (pad (max 3 (round bar 2))))
        (if (eq (%theme-setting theme '*mode-line-marker*) :brackets)
            (let ((w (round (* bar 1.4))))
              (draw:stroke-rectangle cr pad 2 w (- bar 4) :color (theme-accent theme)))
            (draw:fill-rounded-rectangle cr pad 1 (round (* bar 1.4)) (- bar 2) 2
                                         (theme-accent theme)))
        (draw:fill-rectangle cr (round (- width (* bar 4)) 2) (round (- bar text) 2)
                             (* bar 4) text (theme-foreground theme))
        (loop for i from 0 below 3
              do (draw:fill-rectangle cr (- width pad (* (1+ i) (round (* bar 2.2))))
                                      (round (- bar text) 2) (round (* bar 1.6)) text
                                      (theme-muted theme))))
      ;; Two windows, the focused one at the left, and below the
      ;; other an empty frame, where the wallpaper shows.
      (let* ((top (+ bar outer))
             (h (- height top outer))
             (left-w (round (* (- width (* 2 outer) gap) 0.58)))
             (right-x (+ outer left-w gap))
             (right-w (- width right-x outer))
             (right-h (round (* (- h gap) 0.55)))
             (inset (+ border (max 3 (round width 50)))))
        (flet ((window (x y w h border-color colors)
                 (draw:fill-rectangle cr x y w h (theme-background theme))
                 (%card-lines cr (+ x inset) (+ y inset) (- w (* 2 inset)) (- h (* 2 inset))
                              colors)
                 (draw:stroke-rectangle cr x y w h :color border-color :line-width border)))
          (window outer top left-w h (theme-border-focus theme)
                  (list (theme-accent theme) (theme-foreground theme) (theme-muted theme)
                        (theme-foreground theme) (theme-error theme) (theme-foreground theme)))
          (window right-x top right-w right-h (theme-border-unfocus theme)
                  (list (theme-muted theme) (theme-foreground theme) (theme-muted theme))))))))

;;; The picker

(defconstant +key-left+ #xff51)
(defconstant +key-right+ #xff53)
(defconstant +key-iso-left-tab+ #xfe20)

(defun theme-picker-open ()
  "Open the theme picker on the current output, on the theme in use."
  (theme-picker-close)
  (menu-close)
  (let* ((names (theme-names))
         (output (group-current-output (state-current-group *compositor-state*))))
    (unless (and output names)
      (return-from theme-picker-open nil))
    (let ((picker (%make-theme-picker
                   :names names
                   :selected (or (and *theme* (position (theme-name *theme*) names)) 0)
                   :output output
                   :canvas (hrt:make-canvas output :layer :layer-overlay))))
      (setf (hrt:canvas-on-button (theme-picker-canvas picker))
            (lambda (canvas x y button pressed)
              (declare (ignore canvas y))
              (%theme-picker-click picker x button pressed))
            (hrt:canvas-on-axis (theme-picker-canvas picker))
            (lambda (canvas x y vertical delta)
              (declare (ignore canvas x y vertical))
              (%theme-picker-move picker (if (plusp delta) 1 -1))))
      (setf *theme-picker* picker
            (theme-picker-previous-grab picker)
            (grab-keys (lambda (key text) (%theme-picker-key picker key text))))
      (%theme-picker-show picker)
      picker)))

(defun theme-picker-close (&optional keep)
  "Take the picker down: with KEEP the theme shown stays (remembered),
without the one from before it opened comes back."
  (alexandria:when-let ((picker *theme-picker*))
    (setf *theme-picker* nil)
    (ungrab-keys (theme-picker-previous-grab picker))
    (let ((canvas (theme-picker-canvas picker)))
      (unless (hrt:canvas-destroyed-p canvas)
        (hrt:canvas-destroy canvas)))
    (end-theme-preview keep)
    (when keep
      (toast-message *compositor-state*
                     (format nil "Theme: ~(~A~)" (theme-name *theme*))))))

(defun %theme-picker-show (picker)
  "Preview the selected theme, then draw the picker in it."
  (preview-theme (nth (theme-picker-selected picker) (theme-picker-names picker)))
  (%theme-picker-draw picker))

(defun %theme-picker-move (picker delta)
  (let ((count (length (theme-picker-names picker))))
    (setf (theme-picker-selected picker)
          (mod (+ (theme-picker-selected picker) delta) count))
    (%theme-picker-show picker)))

(defun %theme-picker-key (picker key text)
  (let* ((keysym (key-keysym key))
         (control (plusp (logand (key-modifier-mask key) mahogany/keyboard::+modifier-ctrl+))))
    (flet ((control-char (char)
             (and control (= keysym (char-code char)))))
      (cond ((= keysym +key-escape+) (theme-picker-close))
            ((or (= keysym +key-return+) (= keysym +key-kp-enter+)) (theme-picker-close t))
            ((or (= keysym +key-right+) (= keysym +key-down+) (= keysym +key-tab+)
                 (control-char #\n) (control-char #\f))
             (%theme-picker-move picker 1))
            ((or (= keysym +key-left+) (= keysym +key-up+) (= keysym +key-iso-left-tab+)
                 (control-char #\p) (control-char #\b))
             (%theme-picker-move picker -1))
            ((= keysym +key-home+) (%theme-picker-move picker (- (theme-picker-selected picker))))
            ((= keysym +key-end+)
             (%theme-picker-move picker (- (length (theme-picker-names picker))
                                           (theme-picker-selected picker) 1)))
            ;; A letter goes to the next theme whose name starts with it:
            ((and text (not control) (= 1 (length text)) (alpha-char-p (char text 0)))
             (let* ((names (theme-picker-names picker))
                    (count (length names))
                    (from (theme-picker-selected picker)))
               (loop for step from 1 to count
                     for index = (mod (+ from step) count)
                     when (char-equal (char text 0) (char (string (nth index names)) 0))
                       do (%theme-picker-move picker step)
                          (return))))))))

(defun %theme-picker-click (picker x button pressed)
  (when (and pressed (= button hrt:+button-left+))
    (alexandria:when-let ((index (loop for (x0 x1 index) in (theme-picker-hits picker)
                                       when (<= x0 x x1) return index)))
      (if (= index (theme-picker-selected picker))
          (theme-picker-close t)
          (%theme-picker-move picker (- index (theme-picker-selected picker)))))))

(defun %theme-picker-draw (picker)
  (let ((canvas (theme-picker-canvas picker))
        (output (theme-picker-output picker)))
    (when (hrt:canvas-destroyed-p canvas)
      (return-from %theme-picker-draw nil))
    (let* ((theme *theme*)
           (font (mh/theme:theme-font *menu-theme*))
           (small (font-at-size font (max 7 (- (font-size font) 2))))
           (names (theme-picker-names picker))
           (selected (theme-picker-selected picker))
           (plain (eq *overlay-style* :plain))
           (pad 18))
      (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
        (let* ((card-w (min *theme-picker-card-width* (round output-width 3)))
               (card-h (round (* card-w 10) 16))
               (side-w (round (* card-w 0.72)))
               (side-h (round (* side-w 10) 16))
               (gap (round card-w 12))
               (text-h (draw:with-image-surface (surface 1 1)
                         (draw:with-context (cr surface)
                           (nth-value 1 (draw:text-size cr "Xg" :font font)))))
               (height (+ pad card-h pad text-h 4 text-h pad))
               (center (round output-width 2))
               (hits '()))
          (hrt:canvas-set-position canvas 0 (max 0 (round (- output-height height) 2)))
          (hrt:with-canvas-frame (cr canvas output-width height)
            ;; A band across the screen, edged above and below:
            (draw:clear cr (theme-background theme) 0.9)
            (draw:fill-rectangle cr 0 0 output-width (%overlay-border) (theme-accent theme))
            (draw:fill-rectangle cr 0 (- height (%overlay-border)) output-width (%overlay-border)
                                 (theme-accent theme))
            ;; The cards, outward from the selected one while they fit:
            (flet ((card (index x w h dim)
                     (let ((y (+ pad (round (- card-h h) 2)))
                           (radius (%overlay-radius 8)))
                       (draw:save-restore (cr)
                         (draw:translate cr x y)
                         (draw:clip-rounded-rectangle cr 0 0 w h radius)
                         (draw-theme-card cr (find-theme (nth index names)) w h)
                         (when dim
                           (draw:fill-rectangle cr 0 0 w h (%dim (theme-background theme) 0.45))))
                       (if dim
                           (draw:stroke-rounded-rectangle cr x y w h radius
                                                          :color (%dim (theme-muted theme) 0.6)
                                                          :line-width 1)
                           (draw:stroke-rounded-rectangle cr (- x 3) (- y 3) (+ w 6) (+ h 6)
                                                          (if plain 0 (+ radius 3))
                                                          :color (theme-accent theme)
                                                          :line-width (if plain 2 3)))
                       (push (list x (+ x w) index) hits))))
              (card selected (- center (round card-w 2)) card-w card-h nil)
              ;; Each theme once: half the others to the right, the
              ;; rest to the left, as many as the width holds.
              (let* ((count (length names))
                     (to-right (ceiling (1- count) 2))
                     (to-left (floor (1- count) 2)))
                (loop for k from 1 to to-right
                      for offset = (+ (round card-w 2) gap (* (1- k) (+ side-w gap)))
                      for right = (+ center offset)
                      for left = (- center offset side-w)
                      while (<= (+ right side-w) output-width)
                      do (card (mod (+ selected k) count) right side-w side-h t)
                         (when (and (<= k to-left) (>= left 0))
                           (card (mod (- selected k) count) left side-w side-h t)))))
            ;; The name and description of the selected theme, and the keys:
            (let* ((name-y (+ pad card-h pad))
                   (name (format nil "~(~A~)" (theme-name theme)))
                   (line (format nil "~A · ~D/~D" (theme-description theme)
                                 (1+ selected) (length names))))
              (draw:draw-text cr name 0 name-y :font font :color (theme-foreground theme)
                                               :width output-width :alignment :center)
              (draw:draw-text cr line 0 (+ name-y text-h 4) :font small
                                                           :color (theme-muted theme)
                                                           :width output-width :alignment :center)
              (draw:draw-text cr "←/→ choose   Return keep   Esc back"
                              0 (+ name-y text-h 4) :font small :color (%dim (theme-muted theme) 0.7)
                              :width (- output-width pad) :alignment :right)))
          (setf (theme-picker-hits picker) hits))))))

(defcommand theme-picker ()
  (:documentation "Choose a theme from cards that preview it")
  (:method () (theme-picker-open)))
