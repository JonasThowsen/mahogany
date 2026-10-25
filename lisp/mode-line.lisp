(in-package #:mahogany)

;;; The mode-line: a bar at the top (or bottom) of each output, drawn by
;;; Lisp on a canvas, as StumpWM's. It shows segments: the groups with
;;; the current one marked, the focused window's title, the clock, and
;;; whatever functions the user adds. It is redrawn on a timer and when
;;; groups change; everything about it can be changed in init.lisp or
;;; live from the REPL, and the next redraw shows it.

(config:defconfig *mode-line-enabled* t
  boolean
  "Whether the mode-line is shown. The mode-line command toggles it.")

(config:defconfig *mode-line-position* :top
  (member :top :bottom)
  "The edge of each output the mode-line sits at.")

(config:defconfig *mode-line-height* 28
  fixnum
  "The height of the mode-line in layout pixels.")

(config:defconfig *mode-line-padding* 8
  fixnum
  "Space in layout pixels at the ends of the mode-line and between its
segments.")

(config:defconfig *mode-line-theme*
    (mh/theme:make-theme :font "monospace 12"
                         :font-color (colors:rgb 0.9 0.9 0.9)
                         :background-color (colors:rgb 0.1 0.1 0.12)
                         :border-color (colors:rgb 0.8 0.3 0.2))
  mh/theme:theme
  "Colors and font of the mode-line. The border color marks the current
group.")

(config:defconfig *mode-line-segments* '(:groups :title :fill :clock)
  list
  "What the mode-line shows, left to right. A segment is :groups (every
group, the current one marked), :title (the focused window's title,
shortened to the room left), :clock (HH:MM), :date (weekday, day and
month), :fill (the rest goes to the right end), or a function of the
output returning a string, or NIL for nothing.")

(config:defconfig *mode-line-timeout* 1000
  fixnum
  "Milliseconds between redraws of the mode-line, for the clock and
window titles. Group and focus changes redraw it at once.")

(defstruct (mode-line (:constructor %make-mode-line (output canvas)))
  (output nil :type hrt:output :read-only t)
  (canvas nil :type hrt:canvas :read-only t)
  ;; What a click does where: a list of (X0 X1 FUNCTION), from the last
  ;; draw.
  (hits '() :type list))

(defglobal *mode-lines* (make-hash-table :test 'equal)
  "The mode-line of each output, by the output's full name.")

(defglobal *mode-line-timer* nil
  "The timer that redraws the mode-lines, while they are shown.")

;;; Segments

(defparameter +day-names+ #("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))
(defparameter +month-names+
  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(defun mode-line-clock ()
  (multiple-value-bind (sec min hour) (get-decoded-time)
    (declare (ignore sec))
    (format nil "~2,'0D:~2,'0D" hour min)))

(defun mode-line-date ()
  (multiple-value-bind (sec min hour day month year weekday) (get-decoded-time)
    (declare (ignore sec min hour year))
    (format nil "~A ~D ~A" (aref +day-names+ weekday) day
            (aref +month-names+ (1- month)))))

(defun mode-line-title ()
  "The title of the focused window, or NIL."
  (let ((frame (state-current-frame *compositor-state*)))
    (when (typep frame 'tree:view-frame)
      (alexandria:when-let ((view (tree:frame-surface frame)))
        (let ((title (hrt:view-title view)))
          (and title (plusp (length title)) title))))))

(defun %mode-line-groups ()
  "The groups in order of their numbers, as (name current-p group)."
  (let ((current (state-current-group *compositor-state*)))
    (map 'list (lambda (group)
                 (list (mahogany-group-name group) (eq group current) group))
         (sort (copy-seq (state-groups *compositor-state*)) #'<
               :key #'mahogany-group-number))))

(defun %mode-line-items (output)
  "What to draw for OUTPUT, as a list of items: (:text STRING &key
marked flexible) and :fill."
  (let ((items '()))
    (dolist (segment *mode-line-segments* (nreverse items))
      (flet ((add (text &rest options)
               (when (and text (plusp (length text)))
                 (push (list* :text text options) items))))
        (case segment
          (:groups (loop for (name current group) in (%mode-line-groups)
                         do (add name :marked current
                                 :on-click (let ((group group))
                                             (lambda ()
                                               (setf (state-current-group *compositor-state*)
                                                     group))))))
          (:title (add (mode-line-title) :flexible t))
          (:clock (add (mode-line-clock)))
          (:date (add (mode-line-date)))
          (:fill (push :fill items))
          ((nil))
          (t (add (handler-case (funcall segment output)
                    (error (c)
                      (log-string :error "Mode-line segment ~S: ~A" segment c)
                      nil)))))))))

;;; Drawing

(defun %draw-mode-line-items (cr items width height theme)
  "Lay ITEMS out on a WIDTH x HEIGHT bar and draw them: the items before
:fill from the left, the rest from the right, and a :flexible item
taking the room that is left, shortened to it. Returns the clickable
places as a list of (X0 X1 FUNCTION)."
  (let* ((font (mh/theme:theme-font theme))
         (pad *mode-line-padding*)
         (chip-pad (round pad 2))
         (fill (position :fill items))
         (left (subseq items 0 (or fill (length items))))
         (right (if fill (subseq items (1+ fill)) '()))
         (hits '()))
    (labels ((text-width (item)
               (multiple-value-bind (w h) (draw:text-size cr (getf item :text) :font font)
                 (declare (ignore h))
                 (+ w (if (getf item :marked) (* 2 chip-pad) 0))))
             (fixed-width (items)
               (loop for item in items
                     unless (getf item :flexible)
                       sum (+ (text-width item) pad)))
             (draw-item (item x available)
               "Draw ITEM at X in at most AVAILABLE pixels; return its width."
               (destructuring-bind (&key text marked flexible on-click) item
                 (let* ((room (if flexible (max 0 (- available pad)) nil))
                        (chip (if marked chip-pad 0)))
                   (draw:with-layout (layout cr :text text :font font
                                                :width (when room (- room (* 2 chip)))
                                                :ellipsize (when room :end))
                     (multiple-value-bind (w h) (draw:layout-pixel-size layout)
                       (let ((y (round (- height h) 2)))
                         (when marked
                           (draw:fill-rounded-rectangle
                            cr x (- y chip) (+ w (* 2 chip)) (+ h (* 2 chip)) 4
                            (mh/theme:theme-border-color theme)))
                         (draw:show-layout cr layout (+ x chip) y
                                           (mh/theme:theme-font-color theme))
                         (when on-click
                           (push (list x (+ x w (* 2 chip)) on-click) hits))
                         (+ w (* 2 chip)))))))))
      ;; From the right end first, so the left side knows its room:
      (let ((x (- width pad)))
        (dolist (item (reverse right))
          (let ((w (text-width item)))
            (decf x w)
            (draw-item item x w)
            (decf x pad)))
        (let ((right-edge x)
              (x pad))
          (dolist (item left)
            (let ((available (- right-edge x
                                (fixed-width (cdr (member item left))))))
              (incf x (+ (draw-item item x available) pad))))))
      hits)))

(defun mode-line-draw (mode-line)
  "Draw MODE-LINE for its output as it is now."
  (let* ((output (mode-line-output mode-line))
         (canvas (mode-line-canvas mode-line))
         (theme *mode-line-theme*)
         (height *mode-line-height*))
    (multiple-value-bind (width output-height) (hrt:output-resolution output)
      (hrt:canvas-set-position canvas 0 (if (eq *mode-line-position* :bottom)
                                            (- output-height height)
                                            0))
      (hrt:with-canvas-frame (cr canvas width height)
        (draw:clear cr (mh/theme:theme-background-color theme))
        (setf (mode-line-hits mode-line)
              (%draw-mode-line-items cr (%mode-line-items output) width height theme))))))

(defun %mode-line-click (mode-line x y button pressed)
  "A click on MODE-LINE: run what is under X."
  (declare (ignore y))
  (when (and pressed (= button hrt:+button-left+))
    (loop for (x0 x1 function) in (mode-line-hits mode-line)
          when (<= x0 x x1)
            do (funcall function)
               (mode-line-update)
               (return))))

(defun %mode-line-scroll (vertical delta)
  "The wheel over a mode-line goes through the groups."
  (when vertical
    (if (plusp delta)
        (state-next-hidden-group *compositor-state*)
        (state-prev-hidden-group *compositor-state*))))

;;; Mode-lines of the outputs

(defun %mode-line-reserve (output height)
  (if (eq *mode-line-position* :bottom)
      (hrt:output-set-reserved output :bottom height)
      (hrt:output-set-reserved output :top height)))

(defun %ensure-mode-line (output)
  "The mode-line of OUTPUT, made if it has none."
  (let ((name (hrt:output-full-name output)))
    (or (gethash name *mode-lines*)
        (let* ((canvas (hrt:make-canvas output :layer :layer-top))
               (mode-line (%make-mode-line output canvas)))
          (setf (hrt:canvas-on-button canvas)
                (lambda (canvas x y button pressed)
                  (declare (ignore canvas))
                  (%mode-line-click mode-line x y button pressed))
                (hrt:canvas-on-axis canvas)
                (lambda (canvas x y vertical delta)
                  (declare (ignore canvas x y))
                  (%mode-line-scroll vertical delta)))
          (%mode-line-reserve output *mode-line-height*)
          (setf (gethash name *mode-lines*) mode-line)))))

(defun %remove-mode-line (mode-line)
  (let ((output (mode-line-output mode-line)))
    (remhash (hrt:output-full-name output) *mode-lines*)
    (unless (hrt:canvas-destroyed-p (mode-line-canvas mode-line))
      (hrt:canvas-destroy (mode-line-canvas mode-line))
      (hrt:output-set-reserved output))))

(defun mode-line-update ()
  "Redraw the mode-lines of the outputs in use, making those that are
missing and dropping those of outputs that have gone."
  (when (and *mode-line-enabled* (state-server *compositor-state*))
    (let ((outputs (map 'list #'tree:output-container-output
                        (state-cur-outputs *compositor-state*))))
      (maphash (lambda (name mode-line)
                 (declare (ignore name))
                 (when (or (hrt:canvas-destroyed-p (mode-line-canvas mode-line))
                           (not (member (mode-line-output mode-line) outputs
                                        :test #'hrt:output=)))
                   (%remove-mode-line mode-line)))
               *mode-lines*)
      (dolist (output outputs)
        (handler-case (mode-line-draw (%ensure-mode-line output))
          (error (c)
            (log-string :error "Could not draw the mode-line of ~S: ~A"
                        (hrt:output-full-name output) c)))))))

(defun %mode-line-timer-fired (timer)
  (declare (type hrt:timer-handle timer))
  (cond (*mode-line-enabled*
         (mode-line-update)
         (hrt:timer-handle-update timer *mode-line-timeout*))
        (t
         (hrt:timer-handle-destroy timer)
         (setf *mode-line-timer* nil))))

(defun mode-line-start ()
  "Show the mode-lines and keep them up to date."
  (setf *mode-line-enabled* t)
  (mode-line-update)
  (unless *mode-line-timer*
    (setf *mode-line-timer*
          (hrt:server-make-timer (state-server *compositor-state*)
                                 #'%mode-line-timer-fired))
    (hrt:timer-handle-update *mode-line-timer* *mode-line-timeout*)))

(defun mode-line-stop ()
  "Take the mode-lines down and give their space back."
  (setf *mode-line-enabled* nil)
  (when *mode-line-timer*
    (hrt:timer-handle-destroy *mode-line-timer*)
    (setf *mode-line-timer* nil))
  (maphash (lambda (name mode-line)
             (declare (ignore name))
             (%remove-mode-line mode-line))
           *mode-lines*)
  (clrhash *mode-lines*))

(defun mode-line-reset ()
  "Take the mode-lines and their timer down for shutdown, leaving
*mode-line-enabled* as the user set it."
  (when *mode-line-timer*
    (hrt:timer-handle-destroy *mode-line-timer*)
    (setf *mode-line-timer* nil))
  (maphash (lambda (name mode-line)
             (declare (ignore name))
             (%remove-mode-line mode-line))
           *mode-lines*)
  (clrhash *mode-lines*))

(defcommand mode-line ()
  (:documentation "Toggle the mode-line")
  (:method ()
    (if *mode-line-enabled*
        (mode-line-stop)
        (mode-line-start))))
