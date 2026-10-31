(in-package :mahogany/tree)

;; Since these hold forgein objects, we can't dump them to the image;
;; they need to be set before any frame is created.
;; Once present, they can be updated as needed using the
;; hrt:border-box-style-update function.
(defparameter *frame-focus-border-style*
  nil
  "Border of empty frames that are focused")

(defparameter *frame-unfocus-border-style*
  nil
  "Border of frames that are not focused")

(defparameter *frame-unfocus-empty-border-style*
  nil
  "Border of empty frames that are not focused")

;; Let's keep the border width a fixnum
;; to avoid half pixels:
(declaim (type fixnum *frame-border-width* *window-gap* *output-gap*))
(defglobal *frame-border-width* 2
  "The width of a frame's border in layout pixels.")

(defglobal *window-gap* 10
  "Layout pixels between the windows of neighbouring frames: each frame
keeps half of it around its border. With a gap every frame draws its
own border; without one, neighbours share theirs.")

(defglobal *output-gap* 10
  "Layout pixels between the windows and the edge of the output's
usable area (the mode-line, say).")

(defglobal *empty-frame-border* nil
  "Whether a frame with no window in it draws its border when it is the
only frame of its output: NIL leaves an empty screen bare. An empty
frame beside other frames always shows its border, so a split can be
seen.")

(defun %frame-border-shown-p (frame)
  "Whether FRAME's border is drawn: with a window in it, by
*empty-frame-border*, or when it is not the only frame of its output."
  (or (frame-surface frame)
      *empty-frame-border*
      (not (topmost-frame-p frame))))

(defun %update-frame-border-shown (frame)
  (alexandria:when-let ((box (slot-value frame 'border-box)))
    (hrt:hrt-border-box-set-enabled box (and (%frame-border-shown-p frame) t))))

(declaim (inline %half-gap))
(defun %half-gap ()
  (floor *window-gap* 2))

(defun output-gap-margin ()
  "What the usable area of an output is shrunk by on each side, so that
the windows at the edge are *output-gap* from it."
  (max 0 (- *output-gap* (%half-gap))))

(defun unfocused-border-width (width)
  "The line width of the unfocused border for a border WIDTH: twice it
when neighbours share their borders, to hide the gaps rounded corners
leave; the width itself when every frame has a border of its own."
  (if (plusp (%half-gap)) width (* width 2)))

(defun init-frame-border-styles ()
  ;; For border collapsing to work, all borders need to be the same
  ;; width:
  (let ((width (coerce *frame-border-width* 'double-float)))
    (setf *frame-focus-border-style*
          ;; Keep these the same width to avoid weird
          ;; frame resizing issues
          (hrt:border-box-style-create
           :hrt-border-solid (cl-colors2:as-rgb "#ACE1AF") ; 9900a4
           width)
          *frame-unfocus-border-style*
          (hrt:border-box-style-create
           :hrt-border-solid (cl-colors2:as-rgb "000000") ; 9900a4
           (unfocused-border-width width))
          *frame-unfocus-empty-border-style*
          (hrt:border-box-style-create
           :hrt-border-dotted (cl-colors2:as-rgb "cccccc")
           ;; Note: As long as the width isn't greater than the
           ;; declared width, we are fine, especially
           ;; for empty frames:
          width))))

(defclass view-frame (frame)
  ((view :initarg :view
         :accessor frame-surface
         :initform nil
         :type (or hrt:view null)
         :documentation "The client of the frame")
   (next :initarg next-frame
         :initform nil
         :type (or tree-node null)
         :reader frame-next)
   (prev :initarg prev-frame
         :initform nil
         :type (or tree-node null)
         :reader frame-prev)
   (border-box :initform nil
               :type (or null cffi:foreign-pointer))
   (seat :initform nil)))

;;; Where the window and the border box go inside a frame of the given
;;; place and size. With a gap (*window-gap*), the border box is inset
;;; by half the gap and the window by that and the border, ADJUST.
;;; Without one, neighbouring frames share a border: a frame bordered
;;; on the left or top by its neighbour leaves no room of its own there.

(defun %view-frame-get-dimensions (frame adjust width height)
  (let ((gap (%half-gap)))
    (if (plusp gap)
        (values (max 1 (- width (* 2 (+ gap adjust))))
                (max 1 (- height (* 2 (+ gap adjust)))))
        (values (- width (if (frame-bordered-left frame) adjust (+ adjust adjust)))
                (- height (if (frame-bordered-top frame) adjust (+ adjust adjust)))))))

(defun %view-frame-get-position (frame adjust x y)
  (let ((gap (%half-gap)))
    (if (plusp gap)
        (values (+ x gap adjust) (+ y gap adjust))
        (values (+ x (if (frame-bordered-left frame) 0 adjust))
                (+ y (if (frame-bordered-top frame) 0 adjust))))))

(defun %border-box-get-dimensions (frame adjust width height)
  (let ((gap (%half-gap)))
    (if (plusp gap)
        (values (max 1 (- width (* 2 gap))) (max 1 (- height (* 2 gap))))
        (values (+ width (if (frame-bordered-left frame) adjust 0))
                (+ height (if (frame-bordered-top frame) adjust 0))))))

(defun %border-box-get-position (frame adjust x y)
  (let ((gap (%half-gap)))
    (if (plusp gap)
        (values (+ x gap) (+ y gap))
        (values (- x (if (frame-bordered-left frame) adjust 0))
                (- y (if (frame-bordered-top frame) adjust 0))))))

(defmethod initialize-instance :after ((frame view-frame)
                                       &key focused view
                                         &allow-other-keys)
  (with-slots (border-box) frame
    (let* ((rounded-x (round (frame-x frame)))
           (rounded-y (round (frame-y frame)))
           (rounded-width (round (frame-width frame)))
           (rounded-height (round (frame-height frame)))
           (box-style (if focused
                          *frame-focus-border-style*
                          (if view
                              *frame-unfocus-border-style*
                              *frame-unfocus-empty-border-style*)))
           (adjust *frame-border-width*))
      (let* ((layer-container (frame-find-layer frame)))
        (multiple-value-bind (x y)
            (%border-box-get-position frame adjust rounded-x rounded-y)
          (multiple-value-bind (width height)
              (%border-box-get-dimensions frame adjust rounded-width rounded-height)
            (setf border-box (hrt:border-box-create
                              (layer-container-layer layer-container)
                              box-style
                              x
                              y
                              width
                              height)))))
      (hrt:hrt-border-box-lower-to-bottom border-box)
      (%update-frame-border-shown frame)
      (when view
        (multiple-value-bind (width height)
            (%view-frame-get-dimensions frame adjust rounded-width rounded-height)
          (set-dimensions view width height))
        (multiple-value-bind (x y)
            (%view-frame-get-position frame adjust rounded-x rounded-y)
          (set-position view x y))))))

(defmethod (setf frame-surface) :around (new-view (frame view-frame))
  (let ((old-view (frame-surface frame)))
    (call-next-method)
    (when old-view
      (setf (hrt::view-container old-view) nil))
    (when new-view
      (setf (hrt::view-container new-view) frame))))

(defun cleanup-frame (frame)
  (log-string :trace "Cleaning up frame ~S" frame)
  (hrt:hrt-border-box-destroy (slot-value frame 'border-box))
  (setf (slot-value frame 'border-box) nil)
  (alexandria:when-let ((view (frame-surface frame)))
    (setf (hrt::view-container view) nil)))

(defmethod replace-frame ((root view-frame) frame &optional (cleanup-func #'identity))
  (unless (eql root frame)
    (funcall cleanup-func frame)
    (cleanup-frame frame)
    (%replace-frame frame frame)))

(defmethod (setf %frame-prev) (prev (frame view-frame))
  (setf (slot-value frame 'prev) prev))

(defmethod (setf %frame-next) (next (frame view-frame))
  (setf (slot-value frame 'next) next))

(defun frame-view-dimensions (frame)
  (let ((adjust *frame-border-width*))
    (%view-frame-get-dimensions frame adjust
                                (round (frame-width frame))
                                (round (frame-height frame)))))

(defun %view-frame-set-dimensions (frame adjust width height)
  (multiple-value-call
      #'set-dimensions
    (frame-surface frame)
    (%view-frame-get-dimensions frame adjust width height)))

(defun %view-frame-set-position (frame adjust x y)
  (multiple-value-call
      #'set-position
    (frame-surface frame)
   (%view-frame-get-position frame adjust x y)))

(defun %border-box-set-position (frame adjust x y)
  (multiple-value-call
      #'hrt:hrt-border-box-set-relative
    (slot-value frame 'border-box)
    (%border-box-get-position frame adjust x y)))

(defun %border-box-set-dimensions (frame adjust width height)
  (multiple-value-call
      #'hrt:hrt-border-box-set-size
    (slot-value frame 'border-box)
    (%border-box-get-dimensions frame adjust width height))
  ;; A split or a removal resized the frame: alone on its output now,
  ;; or not; the border follows.
  (%update-frame-border-shown frame))

(defmethod (setf frame-surface) :after (view (frame view-frame))
  "Place the view in the frame and make it have the same dimensions
and position as the frame"
  (%update-frame-border-shown frame)
  (with-slots (border-box focused) frame
    (cond
      (view
       (unless focused
         (hrt:border-box-set-style (slot-value frame 'border-box)
                                   *frame-unfocus-border-style*))
       (hrt:with-view-transaction ()
         (let ((adjust *frame-border-width*))
           (multiple-value-bind (width height)
               (%view-frame-get-dimensions
                frame adjust
                (round (frame-width frame)) (round (frame-height frame)))
             (set-dimensions view width height))
           (multiple-value-bind (x y)
               (%view-frame-get-position
                frame adjust
                (round (frame-x frame))
                (round (frame-y frame)))
             (set-position view x y)))
         (when (frame-focused frame)
           (hrt:focus-view view (slot-value frame 'seat)))))
      (t
       (unless focused
         (hrt:border-box-set-style (slot-value frame 'border-box)
                                   *frame-unfocus-empty-border-style*))))))

(defmethod (setf frame-parent) :after (parent (frame view-frame))
  (declare (ignore parent))
  ;; Split off, or alone again after a removal: the border follows.
  (%update-frame-border-shown frame))

(defmethod mark-frame-focused :after ((frame view-frame) seat)
  (setf (slot-value frame 'seat) seat)
  (hrt:hrt-border-box-raise-to-top (slot-value frame 'border-box))
  (hrt:border-box-set-style (slot-value frame 'border-box) *frame-focus-border-style*)
  (%update-frame-border-shown frame)
  (alexandria:when-let ((hrt-view (frame-surface frame)))
    (log-string :trace "view frame focused")
    (hrt:focus-view hrt-view seat)))

(defmethod unmark-frame-focused :after ((frame view-frame) seat)
  (alexandria:if-let ((hrt-view (frame-surface frame)))
    (progn
      (log-string :trace "view frame unfocused")
      (hrt:unfocus-view hrt-view seat)
      (hrt:hrt-border-box-lower-to-bottom (slot-value frame 'border-box))
      (hrt:border-box-set-style (slot-value frame 'border-box)
                                *frame-unfocus-border-style*))
    (hrt:border-box-set-style (slot-value frame 'border-box)
                                *frame-unfocus-empty-border-style*))
  (setf (slot-value frame 'seat) nil))

(defmethod print-object ((object view-frame) stream)
  (print-unreadable-object (object stream :type t)
    (with-slots (width height x y view)
        object
      (let ((*print-circle* t))
        (format stream ":w ~A :h ~A :x ~A :y ~A view: ~S"
                (round width) (round height) (round x) (round y) view)))))

(defmethod (setf frame-x) :before (new-x (frame view-frame))
  (let ((round-x (round new-x))
        (round-y (round (frame-y frame)))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-position frame adjust
                                round-x round-y))
    (%border-box-set-position frame adjust round-x round-y)))

(defmethod (setf frame-y) :before (new-y (frame view-frame))
  (let ((round-y (round new-y))
        (round-x (round (frame-x frame)))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-position frame adjust round-x round-y))
    (%border-box-set-position frame adjust round-x round-y)))

(defmethod set-dimensions :before ((frame view-frame) width height)
  (let ((w-adjusted (round width))
        (h-adjusted (round height))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-dimensions frame adjust w-adjusted h-adjusted))
    (%border-box-set-dimensions frame adjust
                                w-adjusted h-adjusted)))

(defmethod set-position :before ((frame view-frame) x y)
  (let ((round-x (round x))
        (round-y (round y))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-position frame adjust round-x round-y))
    (%border-box-set-position frame adjust round-x round-y)))

(defmethod (setf frame-width) :before (new-width (frame view-frame))
  (let ((round-width (round new-width))
        (round-height (round (frame-height frame)))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-dimensions frame adjust round-width round-height))
    (%border-box-set-dimensions frame adjust
                                round-width round-height)))

(defmethod (setf frame-height) :before (new-height (frame view-frame))
  (let ((round-width (round (frame-width frame)))
        (round-height (round new-height))
        (adjust *frame-border-width*))
    (when (frame-surface frame)
      (%view-frame-set-dimensions frame adjust round-width round-height))
    (%border-box-set-dimensions frame adjust round-width round-height)))

(defmethod find-view-frame ((frame view-frame) view)
  (when (equal (frame-surface frame) view)
    frame))

;; (defmethod find-view-frame ((frame view-frame)
;;        (view sb-sys:system-area-pointer))
;;   (let ((hrt-view (frame-surface frame)))
;;  (when (and hrt-view
;;       (equal (hrt:view-hrt-view (frame-surface frame)) view))
;;    frame)))

;;; Floating frames

(defclass floating-frame (view-frame)
  ((layer :initarg :layer
          :reader floating-frame-layer
          :type layer-container
          :documentation "The group's floating layer, above the tiled one,
where the frame's border and its view are drawn."))
  (:documentation
   "A frame placed freely over the tiled frames of an output node: that
node is its parent, but does not list it among its children, so the
tree and the layouts leave it alone. Its next and previous frame are
itself."))

(defmethod frame-find-layer ((frame floating-frame))
  (floating-frame-layer frame))

(defmethod split-frame-v ((frame floating-frame) &key &allow-other-keys)
  (error 'mahogany/util:invalid-operation
         :text "A floating window's frame cannot be split"))

(defmethod split-frame-h ((frame floating-frame) &key &allow-other-keys)
  (error 'mahogany/util:invalid-operation
         :text "A floating window's frame cannot be split"))

(defmethod mark-frame-focused :after ((frame floating-frame) seat)
  (declare (ignore seat))
  ;; Above the other floating windows:
  (alexandria:when-let ((view (frame-surface frame)))
    (hrt:view-raise-to-top view)))

(defmethod print-object ((object floating-frame) stream)
  (print-unreadable-object (object stream :type t)
    ;; The view prints its container, this frame: circle back to it.
    (let ((*print-circle* t))
      (format stream "~A,~A ~Ax~A view: ~S"
              (round (frame-x object)) (round (frame-y object))
              (round (frame-width object)) (round (frame-height object))
              (frame-surface object)))))
