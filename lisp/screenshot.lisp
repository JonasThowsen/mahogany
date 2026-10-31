(in-package #:mahogany)

;;; Screenshots: of the whole output, the focused window or an area
;;; chosen with the pointer, taken with grim, saved to
;;; *screenshot-directory*, copied to the clipboard and, when wanted,
;;; opened in an editor such as satty. The area is chosen on a canvas
;;; drawn by Lisp over the output: drag with the pointer, Escape
;;; cancels.

(config:defconfig *screenshot-directory* "~/Pictures/Screenshots/"
  (or string pathname)
  "Where screenshots are saved, as screenshot-YYYY-MM-DD-HHMMSS.png.")

(config:defconfig *screenshot-editor*
    '("satty" "--filename" :file "--output-filename" :file
      "--copy-command" "wl-copy" "--early-exit")
  list
  "The program that edits a screenshot, as a list of arguments where
:file stands for the screenshot's file; NIL for none.")

(config:defconfig *screenshot-edit* :auto
  (member t nil :auto :click)
  "What the screenshot commands do about the editor: :click shows a
message that opens it when clicked, T opens it right away, NIL never,
and :auto is :click when *screenshot-editor*'s program is installed,
else NIL. The screenshot menu offers editing either way.")

(config:defconfig *screenshot-message-delay* 8000
  fixnum
  "How long the message after a screenshot stays, in milliseconds: the
time there is to click it and edit the screenshot.")

(config:defconfig *screenshot-copy-command* '("wl-copy" "--type" "image/png")
  list
  "The program that gets the PNG on its standard input to put it on
the clipboard; NIL for none.")

(config:defconfig *screenshot-selection-color* nil
  (or null colors:rgb)
  "The color of the frame around the area being chosen; NIL for the
theme's accent.")

(defun screenshot-file-name (&optional (time (get-universal-time)))
  "A new file name in *screenshot-directory* for a screenshot taken at
TIME."
  (multiple-value-bind (second minute hour day month year) (decode-universal-time time)
    (merge-pathnames (format nil "screenshot-~4,'0D-~2,'0D-~2,'0D-~2,'0D~2,'0D~2,'0D.png"
                             year month day hour minute second)
                     (uiop:ensure-directory-pathname *screenshot-directory*))))

(defun grim-geometry (x y width height)
  "The geometry argument of grim for the rectangle, in layout pixels."
  (format nil "~D,~D ~Dx~D" (round x) (round y) (round width) (round height)))

(defun %editor-available-p ()
  (and *screenshot-editor*
       (mahogany/system:find-program (first *screenshot-editor*))))

(defun %edit-wanted-p (edit)
  "What to do about the editor for EDIT, a *screenshot-edit* value: T,
:click or NIL."
  (if (eq edit :auto)
      (and (%editor-available-p) :click)
      edit))

(defun %screenshot-edit (file)
  (let ((args (substitute (uiop:native-namestring file) :file *screenshot-editor*)))
    (handler-case (uiop:launch-program args)
      (error (c)
        (log-string :error "Could not start the screenshot editor ~S: ~A" args c)
        (toast-message *compositor-state*
                       (format nil "Could not start ~A" (first args))
                       :theme *message-error-theme*)))))

(defun %screenshot-copy (file)
  (when (and *screenshot-copy-command*
             (mahogany/system:find-program (first *screenshot-copy-command*)))
    (handler-case (uiop:launch-program *screenshot-copy-command*
                                       :input (uiop:native-namestring file))
      (error (c)
        (log-string :warn "Could not copy the screenshot: ~A" c)))))

(defun screenshot-capture (geometry &key (edit *screenshot-edit*) (output nil))
  "Take a screenshot with grim: of the rectangle GEOMETRY (x y width
height, in layout pixels), or of OUTPUT (the current one by default)
when GEOMETRY is NIL. Save it, copy it to the clipboard and, when EDIT
says so, open it in the editor."
  (let* ((file (screenshot-file-name))
         (output (or output (group-current-output (state-current-group *compositor-state*))))
         (args (append (list "grim")
                       (if geometry
                           (list "-g" (apply #'grim-geometry geometry))
                           (list "-o" (hrt:output-name output)))
                       (list (uiop:native-namestring file)))))
    (ensure-directories-exist file)
    (run-async args
               (lambda (stdout exit-code)
                 (declare (ignore stdout))
                 (cond ((eql exit-code 0)
                        (log-string :info "Screenshot saved to ~A" file)
                        (%screenshot-copy file)
                        (let ((edit (%edit-wanted-p edit)))
                          (if (eq edit t)
                              (%screenshot-edit file)
                              (toast-message *compositor-state*
                                             (format nil "Screenshot saved: ~A~:[~; — click to edit~]"
                                                     (file-namestring file) (eq edit :click))
                                             :ms-delay *screenshot-message-delay*
                                             :on-click (and (eq edit :click)
                                                            (lambda () (%screenshot-edit file)))))))
                       (t
                        (toast-message *compositor-state*
                                       (if exit-code
                                           (format nil "grim failed (~D)" exit-code)
                                           "Could not run grim")
                                       :theme *message-error-theme*)))))
    file))

(defun %window-geometry ()
  "The geometry of the focused window's frame, inside its border, or
NIL without one."
  (let ((frame (state-current-frame *compositor-state*)))
    (when (and frame (typep frame 'tree:frame) (tree:frame-surface frame))
      (let ((inset (+ tree:*frame-border-width* (floor tree:*window-gap* 2))))
        (list (+ (tree:frame-x frame) inset)
              (+ (tree:frame-y frame) inset)
              (max 1 (- (tree:frame-width frame) (* 2 inset)))
              (max 1 (- (tree:frame-height frame) (* 2 inset))))))))

;;; Choosing an area: a translucent canvas over the current output. A
;;; drag with the left button chooses, Escape or a click with no drag
;;; cancels.

(defstruct (selection (:constructor %make-selection (output canvas on-done previous-grab)))
  output canvas on-done previous-grab
  (x0 0) (y0 0) (x1 0) (y1 0)
  (dragging nil))

(defglobal *selection* nil
  "The area selection going on, or NIL.")

(defun %selection-rectangle (selection)
  "The chosen rectangle as x y width height on the canvas."
  (let ((x (min (selection-x0 selection) (selection-x1 selection)))
        (y (min (selection-y0 selection) (selection-y1 selection))))
    (values x y
            (abs (- (selection-x1 selection) (selection-x0 selection)))
            (abs (- (selection-y1 selection) (selection-y0 selection))))))

(defun %selection-draw (selection)
  (let ((canvas (selection-canvas selection))
        (accent (or *screenshot-selection-color*
                    (and *theme* (theme-accent *theme*))
                    (colors:rgb 0.8 0.3 0.2)))
        (font (mh/theme:theme-font *menu-theme*)))
    (multiple-value-bind (width height) (hrt:output-logical-size (selection-output selection))
      (hrt:with-canvas-frame (cr canvas width height)
        (draw:clear cr (colors:rgb 0 0 0) 0.35)
        (if (selection-dragging selection)
            (multiple-value-bind (x y w h) (%selection-rectangle selection)
              (draw:save-restore (cr)
                (draw:clip-rectangle cr x y w h)
                (draw:clear cr (colors:rgb 0 0 0) 0))
              (draw:stroke-rectangle cr x y w h :color accent :line-width 2)
              (draw:draw-text cr (format nil "~D × ~D" (round w) (round h))
                              (+ x 6) (max 4 (- y 26))
                              :font font :color (colors:rgb 1 1 1)))
            (draw:draw-text cr "Drag to choose an area, Escape cancels"
                            20 20 :font font :color (colors:rgb 1 1 1)))))))

(defun %selection-end (selection result)
  "Take the selection down and, a moment later when it is off the
screen, call its function with RESULT."
  (when (eq *selection* selection)
    (setf *selection* nil)
    (ungrab-keys (selection-previous-grab selection))
    (unless (hrt:canvas-destroyed-p (selection-canvas selection))
      (hrt:canvas-destroy (selection-canvas selection)))
    (let ((timer (hrt:server-make-timer (state-server *compositor-state*)
                                        (lambda (timer)
                                          (hrt:timer-handle-destroy timer)
                                          (funcall (selection-on-done selection) result)))))
      (hrt:timer-handle-update timer 80))))

(defun %selection-key (selection key text)
  (declare (ignore text))
  (when (= (key-keysym key) +key-escape+)
    (%selection-end selection nil)))

(defun select-area (on-done)
  "Let the user choose a rectangle of the current output with the
pointer, then call ON-DONE with its x, y, width and height in layout
pixels as a list, or with NIL when they cancelled."
  (when *selection*
    (%selection-end *selection* nil))
  (let ((output (group-current-output (state-current-group *compositor-state*))))
    (unless output
      (return-from select-area (funcall on-done nil)))
    (let* ((canvas (hrt:make-canvas output :layer :layer-overlay))
           (selection (%make-selection output canvas on-done nil)))
      (setf (selection-previous-grab selection)
            (grab-keys (lambda (key text) (%selection-key selection key text))))
      (setf (hrt:canvas-on-motion canvas)
            (lambda (canvas x y)
              (declare (ignore canvas))
              (when (selection-dragging selection)
                (setf (selection-x1 selection) x
                      (selection-y1 selection) y)
                (%selection-draw selection)))
            (hrt:canvas-on-button canvas)
            (lambda (canvas x y button pressed)
              (declare (ignore canvas))
              (cond ((/= button hrt:+button-left+)
                     (when pressed (%selection-end selection nil)))
                    (pressed
                     (setf (selection-x0 selection) x (selection-y0 selection) y
                           (selection-x1 selection) x (selection-y1 selection) y
                           (selection-dragging selection) t)
                     (%selection-draw selection))
                    ((selection-dragging selection)
                     (multiple-value-bind (sx sy w h) (%selection-rectangle selection)
                       (if (and (>= w 2) (>= h 2))
                           (multiple-value-bind (ox oy) (hrt:output-position output)
                             (%selection-end selection (list (+ ox sx) (+ oy sy) w h)))
                           (%selection-end selection nil)))))))
      (setf *selection* selection)
      (hrt:canvas-set-position canvas 0 0)
      (%selection-draw selection)
      selection)))

;;; The commands

(defun take-screenshot (&optional (of :screen) &key (edit *screenshot-edit*))
  "Take a screenshot OF :screen (the current output), :window (the
focused window, or the output without one) or :area (chosen with the
pointer first). EDIT says whether it opens in the editor."
  (ecase of
    (:screen (screenshot-capture nil :edit edit))
    (:window (screenshot-capture (%window-geometry) :edit edit))
    (:area (select-area (lambda (geometry)
                          (when geometry
                            (screenshot-capture geometry :edit edit)))))))

(defcommand screenshot-screen ()
  (:documentation "Take a screenshot of the screen")
  (:method () (take-screenshot :screen)))

(defcommand screenshot-window ()
  (:documentation "Take a screenshot of the focused window")
  (:method () (take-screenshot :window)))

(defcommand screenshot-area ()
  (:documentation "Choose an area and take a screenshot of it")
  (:method () (take-screenshot :area)))

(defcommand screenshot-menu ()
  (:documentation "Choose what to take a screenshot of")
  (:method () (launcher :screenshot)))

(define-launcher-mode :screenshot (:prompt "Screenshot" :description "Screenshots")
  :items (list (make-menu-item "Area" :data '(:area nil)
                               :detail "drag to choose, saved and copied")
               (make-menu-item "Window" :data '(:window nil)
                               :detail "the focused window")
               (make-menu-item "Screen" :data '(:screen nil)
                               :detail "the whole output")
               (make-menu-item "Area, then edit" :data '(:area t)
                               :detail (format nil "opens in ~A" (first *screenshot-editor*)))
               (make-menu-item "Window, then edit" :data '(:window t))
               (make-menu-item "Screen, then edit" :data '(:screen t)))
  :action (lambda (choice) (take-screenshot (first choice) :edit (second choice))))

(define-key *top-map* (kbd "Print") #'screenshot-area)
(define-key *top-map* (kbd "S-Print") #'screenshot-window)
(define-key *top-map* (kbd "C-Print") #'screenshot-screen)
