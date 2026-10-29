(in-package #:mahogany)

;;; A menu drawn by Lisp: a prompt, a filter typed by the user, and the
;;; items that match it, fuzzily. It takes the keyboard while it is open
;;; (grab-keys) and the pointer over it. It is asynchronous: menu-open
;;; returns at once, and the on-choose or on-cancel function runs later,
;;; on the main thread. The launcher and the interactive commands'
;;; input method are built on it.

(config:defconfig *menu-theme*
    (mh/theme:make-theme :font "monospace 12"
                         :font-color (colors:rgb 0.9 0.9 0.9)
                         :background-color (colors:rgb 0.1 0.1 0.12)
                         :border-color (colors:rgb 0.8 0.3 0.2))
  mh/theme:theme
  "Font and colors of menus. The border color marks the selected item.")

(config:defconfig *menu-width* 0.4
  (real (0) 1)
  "The width of a menu, as a fraction of the output's width.")

(config:defconfig *menu-rows* 12
  fixnum
  "How many items a menu shows at once.")

(config:defconfig *menu-padding* 14
  fixnum
  "Space in layout pixels around and between what a menu shows.")

(config:defconfig *menu-radius* 12
  fixnum
  "How much a menu's corners are rounded, in layout pixels.")

(config:defconfig *menu-match-function* 'fuzzy-match-score
  (or symbol function)
  "How a menu matches what is typed against an item: a function of the
filter and the item's text returning a score, higher for better, or
NIL for no match. The default matches the filter's characters in order,
anywhere in the text.")

;;; Items

(defstruct (menu-item (:constructor make-menu-item
                          (label &key data detail keywords)))
  "A choice in a menu: LABEL is shown and matched, DETAIL shown dimmer at
the right, KEYWORDS matched as well, DATA is whatever the menu's user
needs back."
  (label "" :type string)
  (data nil)
  (detail nil :type (or null string))
  (keywords '() :type list))

(defun fuzzy-match-score (filter text)
  "A score for TEXT against FILTER: every character of FILTER must occur
in TEXT, in order, case ignored. Characters found right after the
previous one, or at the start of a word, score higher; a longer gap
scores lower. NIL when FILTER is not found; 0 for an empty FILTER."
  (declare (type string filter text))
  (if (zerop (length filter))
      0
      (let ((score 0)
            (position -1)
            (previous -2))
        (loop for char across filter
              do (let ((found (position char text :start (1+ position)
                                                  :test #'char-equal)))
                   (unless found
                     (return-from fuzzy-match-score nil))
                   (cond ((= found (1+ previous)) (incf score 10))
                         ((or (zerop found)
                              (not (alphanumericp (char text (1- found)))))
                          (incf score 6))
                         (t (decf score (min 5 (- found position 1)))))
                   (setf previous found
                         position found)))
        ;; Shorter texts that match are more likely what was meant:
        (- score (floor (length text) 10)))))

(defun %dim (color alpha)
  "COLOR (a cl-colors2 rgb) with ALPHA, as a color list for draw:set-color."
  (list (colors:rgb-red color) (colors:rgb-green color) (colors:rgb-blue color) alpha))

(defun menu-item-score (filter item)
  "The item's best score among its label and keywords, or NIL."
  (let ((best (funcall *menu-match-function* filter (menu-item-label item))))
    (dolist (keyword (menu-item-keywords item) best)
      (let ((score (funcall *menu-match-function* filter keyword)))
        (when (and score (or (null best) (> score best)))
          (setf best score))))))

;;; The menu

(defstruct (menu (:constructor %make-menu))
  (prompt "" :type string)
  (items '() :type list)
  (filter "" :type string)
  ;; The items matching the filter, best first:
  (matches #() :type vector)
  (selected 0 :type fixnum)
  (scroll 0 :type fixnum)
  (allow-text nil)
  ;; Draw the filter as dots (a passphrase):
  (secret nil)
  (on-choose nil :type (or null function))
  (on-cancel nil :type (or null function))
  (canvas nil)
  (output nil)
  (previous-grab nil)
  ;; Where the rows were drawn, for the pointer: (Y0 Y1 INDEX)
  (row-hits '() :type list))

(defglobal *menu* nil
  "The open menu, or NIL.")

(defun menu-open (prompt items &key on-choose on-cancel allow-text secret (initial-filter ""))
  "Show a menu with PROMPT and ITEMS (menu-items, or strings) on the
current output, and return at once. When the user chooses, ON-CHOOSE is
called with the menu-item, or with the typed string when ALLOW-TEXT is
true and nothing matched; when they cancel, ON-CANCEL is called. Both
run on the main thread. SECRET draws what is typed as dots, for a
passphrase. An open menu is replaced."
  (menu-close)
  (let* ((output (group-current-output (state-current-group *compositor-state*)))
         (menu (%make-menu :prompt prompt
                           :items (mapcar (lambda (item)
                                            (if (stringp item) (make-menu-item item) item))
                                          items)
                           :filter initial-filter
                           :allow-text allow-text
                           :secret secret
                           :on-choose on-choose
                           :on-cancel on-cancel
                           :output output)))
    (unless output
      (log-string :error "No output to show a menu on")
      (when on-cancel (funcall on-cancel))
      (return-from menu-open nil))
    (let ((canvas (hrt:make-canvas output :layer :layer-overlay)))
      (setf (menu-canvas menu) canvas
            (hrt:canvas-on-button canvas) (lambda (canvas x y button pressed)
                                            (declare (ignore canvas x))
                                            (%menu-click menu y button pressed))
            (hrt:canvas-on-axis canvas) (lambda (canvas x y vertical delta)
                                          (declare (ignore canvas x y))
                                          (when vertical
                                            (%menu-move menu (if (plusp delta) 1 -1))))
            (hrt:canvas-on-motion canvas) (lambda (canvas x y)
                                            (declare (ignore canvas x))
                                            (%menu-hover menu y))))
    (setf *menu* menu
          (menu-previous-grab menu) (grab-keys (lambda (key text) (%menu-key menu key text))))
    (%menu-filter menu)
    (%menu-draw menu)
    menu))

(defun menu-close ()
  "Take the open menu down, without choosing or cancelling."
  (alexandria:when-let ((menu *menu*))
    (setf *menu* nil)
    (ungrab-keys (menu-previous-grab menu))
    (when (menu-canvas menu)
      (hrt:canvas-destroy (menu-canvas menu)))))

(defun menu-cancel ()
  "Close the open menu as cancelled."
  (alexandria:when-let ((menu *menu*))
    (menu-close)
    (when (menu-on-cancel menu)
      (funcall (menu-on-cancel menu)))))

(defun %menu-choose (menu)
  (let ((matches (menu-matches menu)))
    (cond ((plusp (length matches))
           (let ((item (aref matches (menu-selected menu))))
             (menu-close)
             (when (menu-on-choose menu)
               (funcall (menu-on-choose menu) item))))
          ((and (menu-allow-text menu) (plusp (length (menu-filter menu))))
           (let ((text (menu-filter menu)))
             (menu-close)
             (when (menu-on-choose menu)
               (funcall (menu-on-choose menu) text)))))))

(defun %menu-filter (menu)
  "Recompute the matches for the filter; the selection goes to the top."
  (let* ((filter (menu-filter menu))
         (scored (loop for item in (menu-items menu)
                       for score = (menu-item-score filter item)
                       when score collect (cons score item))))
    (setf (menu-matches menu)
          (map 'vector #'cdr (stable-sort scored #'> :key #'car))
          (menu-selected menu) 0
          (menu-scroll menu) 0)))

(defun %menu-move (menu delta)
  (let ((count (length (menu-matches menu))))
    (when (plusp count)
      (setf (menu-selected menu)
            (max 0 (min (1- count) (+ (menu-selected menu) delta))))
      ;; Keep the selection in view:
      (let ((rows *menu-rows*))
        (cond ((< (menu-selected menu) (menu-scroll menu))
               (setf (menu-scroll menu) (menu-selected menu)))
              ((>= (menu-selected menu) (+ (menu-scroll menu) rows))
               (setf (menu-scroll menu) (1+ (- (menu-selected menu) rows))))))
      (%menu-draw menu))))

(defun %menu-set-filter (menu filter)
  (setf (menu-filter menu) filter)
  (%menu-filter menu)
  (%menu-draw menu))

(defconstant +key-return+ #xff0d)
(defconstant +key-kp-enter+ #xff8d)
(defconstant +key-escape+ #xff1b)
(defconstant +key-backspace+ #xff08)
(defconstant +key-tab+ #xff09)
(defconstant +key-up+ #xff52)
(defconstant +key-down+ #xff54)
(defconstant +key-page-up+ #xff55)
(defconstant +key-page-down+ #xff56)
(defconstant +key-home+ #xff50)
(defconstant +key-end+ #xff57)

(defun %menu-key (menu key text)
  "A key press while MENU is open."
  (let* ((keysym (key-keysym key))
         (control (plusp (logand (key-modifier-mask key) mahogany/keyboard::+modifier-ctrl+)))
         (filter (menu-filter menu)))
    (flet ((control-char (char)
             (and control (= keysym (char-code char)))))
      (cond ((= keysym +key-escape+) (menu-cancel))
            ((or (= keysym +key-return+) (= keysym +key-kp-enter+)) (%menu-choose menu))
            ((or (= keysym +key-down+) (= keysym +key-tab+) (control-char #\n) (control-char #\j))
             (%menu-move menu 1))
            ((or (= keysym +key-up+) (control-char #\p) (control-char #\k))
             (%menu-move menu -1))
            ((= keysym +key-page-down+) (%menu-move menu *menu-rows*))
            ((= keysym +key-page-up+) (%menu-move menu (- *menu-rows*)))
            ((= keysym +key-home+) (%menu-move menu (- (length (menu-matches menu)))))
            ((= keysym +key-end+) (%menu-move menu (length (menu-matches menu))))
            ((or (= keysym +key-backspace+) (control-char #\h))
             (when (plusp (length filter))
               (%menu-set-filter menu (subseq filter 0 (1- (length filter))))))
            ((control-char #\u) (%menu-set-filter menu ""))
            ((control-char #\w)
             (let ((end (or (position #\Space (string-right-trim " " filter) :from-end t) -1)))
               (%menu-set-filter menu (subseq filter 0 (1+ end)))))
            ((and text (not control))
             (%menu-set-filter menu (concatenate 'string filter text)))))))

(defun %menu-row-at (menu y)
  (loop for (y0 y1 index) in (menu-row-hits menu)
        when (<= y0 y y1) return index))

(defun %menu-click (menu y button pressed)
  (when (and pressed (= button hrt:+button-left+))
    (alexandria:when-let ((index (%menu-row-at menu y)))
      (setf (menu-selected menu) index)
      (%menu-choose menu))))

(defun %menu-hover (menu y)
  (alexandria:when-let ((index (%menu-row-at menu y)))
    (unless (= index (menu-selected menu))
      (setf (menu-selected menu) index)
      (%menu-draw menu))))

;;; Drawing

(defun %menu-draw (menu)
  (let* ((theme *menu-theme*)
         (font (mh/theme:theme-font theme))
         (pad *menu-padding*)
         (output (menu-output menu))
         (canvas (menu-canvas menu))
         (matches (menu-matches menu))
         (rows (min *menu-rows* (length matches))))
    (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
      (let* ((width (min output-width
                         (max (round (* output-width *menu-width*)) 520)))
             (row-height 0)
             (hits '()))
        ;; Measure a line of text once, off screen:
        (draw:with-image-surface (surface 1 1)
          (draw:with-context (cr surface)
            (multiple-value-bind (w h) (draw:text-size cr "Xg" :font font)
              (declare (ignore w))
              (setf row-height (+ h (round (* pad 3) 4))))))
        (let* ((height (+ pad row-height pad (* rows row-height) (if (plusp rows) pad 0)))
               (x (round (- output-width width) 2))
               (y (round (- output-height height) 3)))
          (hrt:canvas-set-position canvas (max 0 x) (max 0 y))
          (hrt:with-canvas-frame (cr canvas width height)
            (draw:clear cr '(0 0 0 0))
            (draw:fill-rounded-rectangle cr 0 0 width height *menu-radius*
                                         (mh/theme:theme-background-color theme))
            (draw:stroke-rounded-rectangle cr 0 0 width height *menu-radius*
                                           :color (mh/theme:theme-border-color theme) :line-width 2)
            ;; The prompt line: PROMPT filter▏ and how many match:
            (let* ((count (if (menu-items menu)
                              (format nil "~D/~D" (length matches) (length (menu-items menu)))
                              ""))
                   (count-width (draw:text-size cr count :font font))
                   (line (format nil "~A ~A▏" (menu-prompt menu)
                                 (if (menu-secret menu)
                                     (make-string (length (menu-filter menu)) :initial-element #\•)
                                     (menu-filter menu)))))
              (draw:draw-text cr line pad pad :font font
                                              :color (mh/theme:theme-font-color theme)
                                              :width (- width (* 3 pad) count-width)
                                              :ellipsize :start)
              (draw:draw-text cr count (- width pad count-width) pad :font font
                                                                     :color (%dim (mh/theme:theme-font-color theme) 0.6)))
            ;; The rows:
            (loop for row from 0 below rows
                  for index = (+ (menu-scroll menu) row)
                  for item = (aref matches index)
                  for row-y = (+ pad row-height pad (* row row-height))
                  for selected = (= index (menu-selected menu))
                  ;; The selected row is a block of the accent, its
                  ;; text in the background color to stand out on it:
                  for text-color = (if selected
                                       (mh/theme:theme-background-color theme)
                                       (mh/theme:theme-font-color theme))
                  do (when selected
                       (draw:fill-rounded-rectangle cr pad row-y (- width (* 2 pad)) row-height 6
                                                    (mh/theme:theme-border-color theme)))
                     (let* ((detail (menu-item-detail item))
                            ;; A detail takes at most half the row:
                            (detail-width (if detail
                                              (min (+ pad (draw:text-size cr detail :font font))
                                                   (floor width 2))
                                              0)))
                       (draw:draw-text cr (menu-item-label item) (* 2 pad) (+ row-y (round (* pad 3) 8))
                                       :font font :color text-color
                                       :width (- width (* 4 pad) detail-width) :ellipsize :end)
                       (when detail
                         (draw:draw-text cr detail (- width (* 2 pad) detail-width (- pad))
                                         (+ row-y (round (* pad 3) 8))
                                         :font font
                                         :width (- detail-width pad) :ellipsize :end
                                         :color (%dim text-color 0.6))))
                     (push (list row-y (+ row-y row-height) index) hits))
            (setf (menu-row-hits menu) hits)))))))
