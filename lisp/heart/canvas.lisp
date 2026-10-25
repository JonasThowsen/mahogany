(in-package #:hrt)

;;; Canvases: rectangles on an output that the compositor draws into
;;; itself, with cairo. Bars, menus and on-screen displays are drawn on
;;; them. The C side is hrt_canvas (heart/include/hrt/hrt_canvas.h): a
;;; scene buffer that gets a fresh buffer each frame.

(defstruct (canvas (:constructor %make-canvas (pointer output)))
  "A canvas in the scene of OUTPUT. POINTER is the hrt_canvas, null once
destroyed. WIDTH and HEIGHT are those of the last frame committed, in
layout coordinates. The ON- slots hold functions called with the canvas
for pointer input over it (see canvas-pointer-handlers), or NIL."
  (pointer (cffi:null-pointer) :type cffi:foreign-pointer)
  (output nil :type output :read-only t)
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  ;; (canvas x y): the pointer entered or moved, X,Y in layout pixels
  ;; from the canvas's top left corner
  (on-motion nil :type (or null function))
  ;; (canvas): the pointer left
  (on-leave nil :type (or null function))
  ;; (canvas x y button pressed-p): BUTTON is a linux input code, 272 for
  ;; the left button, 273 right, 274 middle
  (on-button nil :type (or null function))
  ;; (canvas x y vertical-p delta): the wheel, DELTA in pixels
  (on-axis nil :type (or null function)))

(declaim (type hash-table *canvases*))
(mahogany/util::defglobal *canvases* (make-hash-table)
  "Every live canvas, by the address of its hrt_canvas, for the pointer
callbacks from heart.")

(defconstant +button-left+ 272)
(defconstant +button-right+ 273)
(defconstant +button-middle+ 274)

(declaim (type hash-table *output-canvases*))
(mahogany/util::defglobal *output-canvases* (make-hash-table)
  "The canvases of each output, by the address of its hrt_output, so
they are destroyed with it.")

(defun %output-key (output)
  (declare (type output output))
  (cffi:pointer-address (output-hrt-output output)))

(defun make-canvas (output &key (layer :layer-top))
  "A canvas on OUTPUT, in its scene LAYER: :layer-background,
:layer-bottom, :layer-top or :layer-overlay, the layer-shell layers.
It shows nothing until the first frame is committed. It is destroyed
with the output, or earlier with canvas-destroy."
  (declare (type output output))
  (let* ((tree (output-scene-layer (output-scene output) layer))
         (pointer (hrt-canvas-create tree)))
    (when (cffi:null-pointer-p pointer)
      (error 'mahogany/util:mahogany-panic
             :text (format nil "Could not create a canvas on output ~S"
                           (output-full-name output))))
    (let ((canvas (%make-canvas pointer output)))
      (push canvas (gethash (%output-key output) *output-canvases*))
      (setf (gethash (cffi:pointer-address pointer) *canvases*) canvas)
      canvas)))

(defun canvas-destroyed-p (canvas)
  (declare (type canvas canvas))
  (cffi:null-pointer-p (canvas-pointer canvas)))

(defun canvas-destroy (canvas)
  "Remove CANVAS from the screen and free it. Destroying it twice is
harmless."
  (declare (type canvas canvas))
  (unless (canvas-destroyed-p canvas)
    (remhash (cffi:pointer-address (canvas-pointer canvas)) *canvases*)
    (hrt-canvas-destroy (canvas-pointer canvas))
    (setf (canvas-pointer canvas) (cffi:null-pointer))
    (let ((key (%output-key (canvas-output canvas))))
      (alexandria:deletef (gethash key *output-canvases*) canvas)
      (unless (gethash key *output-canvases*)
        (remhash key *output-canvases*)))))

(defun output-canvases (output)
  "The canvases on OUTPUT that have not been destroyed."
  (declare (type output output))
  (gethash (%output-key output) *output-canvases*))

(defun %destroy-output-canvases (output)
  "Destroy the canvases of OUTPUT: called when the output goes away.
Their scene nodes are already gone with the output's scene; this frees
the rest."
  (declare (type output output))
  (dolist (canvas (output-canvases output))
    (canvas-destroy canvas)))

(defun canvas-set-position (canvas x y)
  "Place CANVAS at X,Y of its output, in layout coordinates."
  (declare (type canvas canvas))
  (hrt-canvas-set-position (canvas-pointer canvas) x y))

(defun canvas-set-enabled (canvas enabled)
  "Show CANVAS, or hide it without destroying it."
  (declare (type canvas canvas))
  (hrt-canvas-set-enabled (canvas-pointer canvas) (and enabled t)))

(defun canvas-begin (canvas width height)
  "Start a frame of WIDTH x HEIGHT layout pixels on CANVAS at its
output's scale; return the cairo surface to draw it on, or NIL."
  (declare (type canvas canvas))
  (let ((surface (hrt-canvas-begin (canvas-pointer canvas) width height
                                   (output-scale (canvas-output canvas)))))
    (if (cffi:null-pointer-p surface)
        nil
        surface)))

(defun canvas-commit (canvas width height)
  "Show the frame started by canvas-begin; return true when it was shown."
  (declare (type canvas canvas))
  (when (hrt-canvas-commit (canvas-pointer canvas))
    (setf (canvas-width canvas) width
          (canvas-height canvas) height)
    t))

(defmacro with-canvas-frame ((cr canvas width height) &body body)
  "Draw a frame of WIDTH x HEIGHT layout pixels on CANVAS: run BODY with
CR bound to a cairo context for the frame, then show it. The context is
destroyed afterwards, also if BODY exits early, and the frame is shown
only when BODY finishes. Returns true when the frame was shown."
  (alexandria:with-gensyms (surface canvas-var width-var height-var shown)
    `(let* ((,canvas-var ,canvas)
            (,width-var ,width)
            (,height-var ,height)
            (,surface (canvas-begin ,canvas-var ,width-var ,height-var))
            (,shown nil))
       (when ,surface
         (draw:with-context (,cr ,surface)
           ,@body
           (setf ,shown t))
         (and ,shown (canvas-commit ,canvas-var ,width-var ,height-var))))))

;;; Pointer input, from heart

(defmacro %with-canvas-of ((var pointer) &body body)
  `(alexandria:when-let ((,var (gethash (cffi:pointer-address ,pointer) *canvases*)))
     ,@body))

(define-hrt-callback %canvas-pointer-motion :void
    ((pointer :pointer) (x :double) (y :double))
    ()
  (%with-canvas-of (canvas pointer)
    (alexandria:when-let ((handler (canvas-on-motion canvas)))
      (funcall handler canvas x y))))

(define-hrt-callback %canvas-pointer-leave :void
    ((pointer :pointer))
    ()
  (%with-canvas-of (canvas pointer)
    (alexandria:when-let ((handler (canvas-on-leave canvas)))
      (funcall handler canvas))))

(define-hrt-callback %canvas-pointer-button :void
    ((pointer :pointer) (x :double) (y :double) (button :uint32) (pressed :bool))
    ()
  (%with-canvas-of (canvas pointer)
    (alexandria:when-let ((handler (canvas-on-button canvas)))
      (funcall handler canvas x y button pressed))))

(define-hrt-callback %canvas-pointer-axis :void
    ((pointer :pointer) (x :double) (y :double) (vertical :bool) (delta :double))
    ()
  (%with-canvas-of (canvas pointer)
    (alexandria:when-let ((handler (canvas-on-axis canvas)))
      (funcall handler canvas x y vertical delta))))

(defun canvas-callbacks-init (server callbacks)
  "Fill the hrt_canvas_callbacks struct CALLBACKS, which must outlive the
server, and hand it to SERVER."
  (cffi:with-foreign-slots ((pointer-motion pointer-leave pointer-button pointer-axis)
                            callbacks (:struct hrt-canvas-callbacks))
    (setf pointer-motion (cffi:callback %canvas-pointer-motion)
          pointer-leave (cffi:callback %canvas-pointer-leave)
          pointer-button (cffi:callback %canvas-pointer-button)
          pointer-axis (cffi:callback %canvas-pointer-axis)))
  (hrt-canvas-set-callbacks server callbacks))
