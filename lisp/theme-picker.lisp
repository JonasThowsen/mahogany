(in-package #:mahogany)

;;; The theme picker: the themes as a carousel of cards across the
;;; middle of the screen, as Omarchy has it. Each card is a small
;;; desktop drawn in its theme: the wallpaper, the bar with its group
;;; marker, a focused and an unfocused window with the theme's borders,
;;; gaps and text colors. Drawn, not screenshots, so a new theme has its
;;; card at once. Moving the selection previews the theme on the whole
;;; desktop (preview-theme, as the theme menu does); Return keeps it,
;;; Escape goes back to the theme from before.
;;;
;;; It has to feel instant. The carousel slides from card to card on a
;;; timer, every frame painting cards rendered once and kept; the band
;;; takes its colors from the card nearest the middle as it slides, and
;;; the theme is put to use on the desktop (wallpaper, borders, gaps:
;;; windows resize) only once the carousel has come to rest, so holding
;;; an arrow key does not wait for each theme in turn.

(config:defconfig *theme-picker-card-width* 320
  fixnum
  "The width of the selected card in the theme picker, in layout
pixels; the others are smaller. Cards are 16:10.")

(defstruct (theme-picker (:constructor %make-theme-picker))
  (names '() :type list)
  ;; The card the carousel moves to, counted without wrapping around:
  ;; the theme is (nth (mod target count) names).
  (target 0 :type fixnum)
  ;; Where the carousel is, in cards, as it slides toward TARGET:
  (position 0d0 :type double-float)
  ;; The slide under way: from where, and since when (in seconds).
  (from 0d0 :type double-float)
  (start 0d0 :type double-float)
  ;; The theme put to use last, so a slide ending where it began does
  ;; not apply it again:
  (applied nil)
  ;; The font and sizes, fixed when it opens, so the band keeps its
  ;; place while the themes change:
  (font "" :type string)
  (small-font "" :type string)
  (text-height 0 :type fixnum)
  (output nil)
  (canvas nil)
  (previous-grab nil)
  ;; Where the cards were drawn, for the pointer: (X0 X1 CARD)
  (hits '() :type list))

(defglobal *theme-picker* nil
  "The open theme picker, or NIL.")

(defglobal *theme-picker-timer* nil
  "The timer that draws the carousel's frames, made once.")

(defglobal *theme-cards* (make-hash-table :test 'equal)
  "Cards rendered, by (theme name width height scale): (theme wallpaper
. image surface), redone when the theme or the wallpaper changed.")

(defconstant +theme-picker-slide-seconds+ 0.18d0
  "How long the carousel takes to slide to the next card.")

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

;;; A card rendered once, at the size it is shown in the middle

(defun %theme-card-image (theme width height scale)
  "THEME's card rendered at WIDTH x HEIGHT layout pixels times SCALE,
made once and kept until the theme or the wallpaper changes."
  (let* ((key (list (theme-name theme) width height scale))
         (wallpaper *wallpaper*)
         (entry (gethash key *theme-cards*)))
    (if (and entry (eq (first entry) theme) (equal (second entry) wallpaper))
        (cddr entry)
        (let ((surface (draw:make-image-surface (ceiling (* width scale))
                                                (ceiling (* height scale)))))
          (when entry
            (draw:cairo-surface-destroy (cddr entry)))
          (draw:with-context (cr surface)
            (draw:scale cr scale)
            (draw-theme-card cr theme width height))
          (setf (gethash key *theme-cards*) (list* theme wallpaper surface))
          surface))))

;;; The picker

(defconstant +key-left+ #xff51)
(defconstant +key-right+ #xff53)
(defconstant +key-iso-left-tab+ #xfe20)

(defun %seconds-now ()
  (/ (float (get-internal-real-time) 1d0) internal-time-units-per-second))

(defun %picker-name (picker card)
  "The name of the theme on CARD, counted without wrapping around."
  (let ((names (theme-picker-names picker)))
    (nth (mod card (length names)) names)))

(defun theme-picker-open ()
  "Open the theme picker on the current output, on the theme in use."
  (theme-picker-close)
  (menu-close)
  (let* ((names (theme-names))
         (output (group-current-output (state-current-group *compositor-state*))))
    (unless (and output names)
      (return-from theme-picker-open nil))
    (let* ((selected (or (and *theme* (position (theme-name *theme*) names)) 0))
           (font (mh/theme:theme-font *menu-theme*))
           (picker (%make-theme-picker
                    :names names
                    :target selected
                    :position (float selected 1d0)
                    :from (float selected 1d0)
                    :applied (and *theme* (theme-name *theme*))
                    :font font
                    :small-font (font-at-size font (max 7 (- (font-size font) 2)))
                    :output output
                    :canvas (hrt:make-canvas output :layer :layer-overlay))))
      (setf (theme-picker-text-height picker)
            (draw:with-image-surface (surface 1 1)
              (draw:with-context (cr surface)
                (nth-value 1 (draw:text-size cr "Xg" :font font)))))
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
      ;; Remember the theme to go back to:
      (when *theme*
        (preview-theme (theme-name *theme*)))
      (%theme-picker-draw picker)
      picker)))

(defun theme-picker-close (&optional keep)
  "Take the picker down: with KEEP the theme it shows stays
(remembered), without the one from before it opened comes back."
  (alexandria:when-let ((picker *theme-picker*))
    (setf *theme-picker* nil)
    (when *theme-picker-timer*
      (hrt:timer-handle-update *theme-picker-timer* 0))
    (ungrab-keys (theme-picker-previous-grab picker))
    (let ((canvas (theme-picker-canvas picker)))
      (unless (hrt:canvas-destroyed-p canvas)
        (hrt:canvas-destroy canvas)))
    (when keep
      ;; Kept before the slide came to rest: the theme it was going to.
      (%theme-picker-apply picker))
    (end-theme-preview keep)
    (when keep
      (toast-message *compositor-state*
                     (format nil "Theme: ~(~A~)" (theme-name *theme*))))))

(defun %theme-picker-apply (picker)
  "Put the theme the carousel is on to use on the desktop, unless it is."
  (let ((name (%picker-name picker (theme-picker-target picker))))
    (unless (eq name (theme-picker-applied picker))
      (setf (theme-picker-applied picker) name)
      (preview-theme name))))

(defun %theme-picker-move (picker delta)
  "Slide DELTA cards on, from where the carousel is now."
  (unless (zerop delta)
    (setf (theme-picker-from picker) (theme-picker-position picker)
          (theme-picker-start picker) (%seconds-now))
    (incf (theme-picker-target picker) delta)
    (%theme-picker-tick picker)))

(defun %theme-picker-tick (picker)
  "Draw a frame of the slide, and arm the timer for the next one; at its
end, put the theme to use."
  (unless (eq picker *theme-picker*)
    (return-from %theme-picker-tick nil))
  (let* ((elapsed (- (%seconds-now) (theme-picker-start picker)))
         (time (min 1d0 (/ elapsed +theme-picker-slide-seconds+)))
         ;; Ease out: fast at first, settling softly.
         (eased (- 1d0 (expt (- 1d0 time) 3)))
         (from (theme-picker-from picker))
         (target (float (theme-picker-target picker) 1d0)))
    (setf (theme-picker-position picker) (+ from (* (- target from) eased)))
    (%theme-picker-draw picker)
    (if (< time 1d0)
        (progn
          (unless *theme-picker-timer*
            (setf *theme-picker-timer*
                  (hrt:server-make-timer (state-server *compositor-state*)
                                         (lambda (timer)
                                           (declare (ignore timer))
                                           (alexandria:when-let ((picker *theme-picker*))
                                             (%theme-picker-tick picker))))))
          (hrt:timer-handle-update *theme-picker-timer* 16))
        (%theme-picker-apply picker))))

(defun %theme-picker-key (picker key text)
  (let* ((keysym (key-keysym key))
         (control (plusp (logand (key-modifier-mask key) mahogany/keyboard::+modifier-ctrl+)))
         (count (length (theme-picker-names picker)))
         (index (mod (theme-picker-target picker) count)))
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
            ((= keysym +key-home+) (%theme-picker-move picker (- index)))
            ((= keysym +key-end+) (%theme-picker-move picker (- count index 1)))
            ;; A letter goes to the next theme whose name starts with it:
            ((and text (not control) (= 1 (length text)) (alpha-char-p (char text 0)))
             (loop for step from 1 to count
                   when (char-equal (char text 0)
                                    (char (string (%picker-name picker (+ index step))) 0))
                     do (%theme-picker-move picker step)
                        (return)))))))

(defun %theme-picker-click (picker x button pressed)
  (when (and pressed (= button hrt:+button-left+))
    (alexandria:when-let ((card (loop for (x0 x1 card) in (theme-picker-hits picker)
                                      when (<= x0 x x1) return card)))
      (if (= card (theme-picker-target picker))
          (theme-picker-close t)
          (%theme-picker-move picker (- card (theme-picker-target picker)))))))

(defun %theme-picker-draw (picker)
  "Draw the band with the cards where the carousel is now. Cheap: the
cards are images rendered once, the colors those of the card nearest
the middle."
  (let ((canvas (theme-picker-canvas picker))
        (output (theme-picker-output picker)))
    (when (hrt:canvas-destroyed-p canvas)
      (return-from %theme-picker-draw nil))
    (let* ((names (theme-picker-names picker))
           (count (length names))
           (position (theme-picker-position picker))
           (nearest (round position))
           (theme (find-theme (%picker-name picker nearest)))
           (plain (eq (%theme-setting theme '*overlay-style*) :plain))
           (radius (if plain 0 8))
           (edge (if plain 1 2))
           (font (theme-picker-font picker))
           (small (theme-picker-small-font picker))
           (text-h (theme-picker-text-height picker))
           (scale (hrt:output-scale output))
           (pad 18))
      (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
        (let* ((card-w (min *theme-picker-card-width* (round output-width 3)))
               (card-h (round (* card-w 10) 16))
               (side 0.72d0)              ; the size of a card away from the middle
               (gap (round card-w 12))
               ;; From the middle of the band to the middle of the card
               ;; one place over, and from one side card to the next:
               (first-step (+ (/ card-w 2) gap (/ (* card-w side) 2)))
               (step (+ (* card-w side) gap))
               (height (+ pad card-h pad text-h 4 text-h pad))
               (center (/ output-width 2))
               ;; Each theme once: as many to each side as half the others.
               (reach (min (floor (1- count) 2)
                           (ceiling (/ (- center first-step) step))))
               (hits '()))
          (hrt:canvas-set-position canvas 0 (max 0 (round (- output-height height) 2)))
          (hrt:with-canvas-frame (cr canvas output-width height)
            (draw:clear cr (theme-background theme) 0.9)
            (draw:fill-rectangle cr 0 0 output-width edge (theme-accent theme))
            (draw:fill-rectangle cr 0 (- height edge) output-width edge (theme-accent theme))
            ;; The cards, the far ones first so the near ones lie over
            ;; them; each placed and sized by its distance from the
            ;; middle, a fraction while the carousel slides.
            (let ((cards (loop for card from (- nearest reach 1) to (+ nearest reach 1)
                               collect card)))
              (dolist (card (sort cards #'> :key (lambda (card) (abs (- card position)))))
                (let* ((distance (- card position))
                       (away (abs distance))
                       (near (min 1d0 away))
                       (size (- 1d0 (* (- 1d0 side) near)))
                       (offset (if (<= away 1d0)
                                   (* away first-step)
                                   (+ first-step (* (- away 1d0) step))))
                       (mid-x (+ center (* (signum distance) offset)))
                       (w (round (* card-w size)))
                       (h (round (* card-h size)))
                       (x (round (- mid-x (/ w 2))))
                       (y (+ pad (round (- card-h h) 2))))
                  (when (and (< x output-width) (> (+ x w) 0) (< away (+ reach 0.5d0)))
                    (let ((image (%theme-card-image (find-theme (%picker-name picker card))
                                                    card-w card-h scale)))
                      (draw:save-restore (cr)
                        (draw:clip-rounded-rectangle cr x y w h radius)
                        (draw:paint-image cr image x y w h)
                        ;; Away from the middle, dimmed:
                        (when (plusp near)
                          (draw:fill-rectangle cr x y w h
                                               (%dim (theme-background theme) (* 0.5 near)))))
                      (if (< away 0.5d0)
                          (draw:stroke-rounded-rectangle cr (- x 3) (- y 3) (+ w 6) (+ h 6)
                                                         (if plain 0 (+ radius 3))
                                                         :color (theme-accent theme)
                                                         :line-width (if plain 2 3))
                          (draw:stroke-rounded-rectangle cr x y w h radius
                                                         :color (%dim (theme-muted theme) 0.6)
                                                         :line-width 1))
                      (push (list x (+ x w) card) hits))))))
            ;; The name and description of the theme in the middle, and the keys:
            (let ((name-y (+ pad card-h pad)))
              (draw:draw-text cr (format nil "~(~A~)" (theme-name theme)) 0 name-y
                              :font font :color (theme-foreground theme)
                              :width output-width :alignment :center)
              (draw:draw-text cr (format nil "~A · ~D/~D" (theme-description theme)
                                         (1+ (mod nearest count)) count)
                              0 (+ name-y text-h 4) :font small :color (theme-muted theme)
                              :width output-width :alignment :center)
              (draw:draw-text cr "←/→ choose   Return keep   Esc back"
                              0 (+ name-y text-h 4) :font small
                              :color (%dim (theme-muted theme) 0.7)
                              :width (- output-width pad) :alignment :right)))
          (setf (theme-picker-hits picker) hits))))))

(defcommand theme-picker ()
  (:documentation "Choose a theme from cards that preview it")
  (:method () (theme-picker-open)))
