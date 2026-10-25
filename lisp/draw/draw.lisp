(in-package #:mahogany/draw)

;;; Contexts and surfaces

(defmacro with-context ((cr surface) &body body)
  "Run BODY with CR bound to a cairo context for SURFACE, destroyed
afterwards."
  `(let ((,cr (cairo-create ,surface)))
     (unwind-protect (progn ,@body)
       (cairo-destroy ,cr))))

(defmacro with-image-surface ((surface width height) &body body)
  "Run BODY with SURFACE bound to a new ARGB32 image surface of
WIDTH x HEIGHT pixels, destroyed afterwards. For tests and for drawing
off screen."
  `(let ((,surface (cairo-image-surface-create +format-argb32+ ,width ,height)))
     (unwind-protect (progn ,@body)
       (cairo-surface-destroy ,surface))))

(defmacro save-restore ((cr) &body body)
  "Run BODY between cairo_save and cairo_restore of CR, so its changes
to the state (color, clip, transform) stay inside."
  `(progn
     (cairo-save ,cr)
     (unwind-protect (progn ,@body)
       (cairo-restore ,cr))))

(defun surface-write-png (surface pathname)
  "Write SURFACE to PATHNAME as PNG; return true on success."
  (cairo-surface-flush surface)
  (zerop (cairo-surface-write-to-png surface (namestring pathname))))

(defun image-surface-pixel (surface x y)
  "The pixel at X,Y of the ARGB32 image SURFACE, as four values from 0 to
255: red, green, blue, alpha, with the premultiplied alpha undone."
  (cairo-surface-flush surface)
  (let* ((data (cairo-image-surface-get-data surface))
         (offset (+ (* y (cairo-image-surface-get-stride surface)) (* x 4)))
         ;; ARGB32 is one native-endian 32-bit word per pixel:
         (word (cffi:mem-ref data :uint32 offset))
         (alpha (ldb (byte 8 24) word)))
    (flet ((channel (position)
             (let ((premultiplied (ldb (byte 8 position) word)))
               (if (zerop alpha)
                   0
                   (round (* premultiplied 255) alpha)))))
      (values (channel 16) (channel 8) (channel 0) alpha))))

;;; Colors

(deftype color ()
  "A cl-colors2 rgb, or a list of red, green, blue and an optional alpha,
each from 0 to 1."
  '(or colors:rgb list))

(defun set-color (cr color &optional alpha)
  "Make COLOR the source of CR. ALPHA, from 0 to 1, overrides the
color's own."
  (declare (type color color))
  (multiple-value-bind (red green blue color-alpha)
      (etypecase color
        (colors:rgb (values (colors:rgb-red color)
                            (colors:rgb-green color)
                            (colors:rgb-blue color)
                            1))
        (list (values (first color) (second color) (third color)
                      (or (fourth color) 1))))
    (cairo-set-source-rgba cr
                           (float red 1d0) (float green 1d0) (float blue 1d0)
                           (float (or alpha color-alpha) 1d0))))

;;; Shapes

(defun clear (cr color &optional alpha)
  "Fill the whole surface with COLOR, replacing what was there,
transparency included."
  (save-restore (cr)
    (cairo-set-operator cr +operator-source+)
    (set-color cr color alpha)
    (cairo-paint cr)))

(defun fill-rectangle (cr x y width height &optional color)
  "Fill the rectangle at X,Y of WIDTH x HEIGHT with COLOR, or with the
current source."
  (when color
    (set-color cr color))
  (cairo-rectangle cr (float x 1d0) (float y 1d0)
                   (float width 1d0) (float height 1d0))
  (cairo-fill cr))

(defun stroke-rectangle (cr x y width height &key color (line-width 1))
  "Draw the outline of the rectangle at X,Y of WIDTH x HEIGHT, inside
it, LINE-WIDTH wide, with COLOR or the current source."
  (when color
    (set-color cr color))
  (let ((inset (/ line-width 2)))
    (cairo-set-line-width cr (float line-width 1d0))
    (cairo-rectangle cr (float (+ x inset) 1d0) (float (+ y inset) 1d0)
                     (float (- width line-width) 1d0)
                     (float (- height line-width) 1d0))
    (cairo-stroke cr)))

(defun fill-rounded-rectangle (cr x y width height radius &optional color)
  "Fill the rectangle at X,Y of WIDTH x HEIGHT with corners rounded by
RADIUS, with COLOR or the current source."
  (when color
    (set-color cr color))
  (let* ((x (float x 1d0)) (y (float y 1d0))
         (w (float width 1d0)) (h (float height 1d0))
         (r (float (min radius (/ w 2) (/ h 2)) 1d0))
         (half-pi (/ pi 2)))
    (cairo-new-path cr)
    (cairo-arc cr (+ x w (- r)) (+ y r) r (- half-pi) 0d0)
    (cairo-arc cr (+ x w (- r)) (+ y h (- r)) r 0d0 half-pi)
    (cairo-arc cr (+ x r) (+ y h (- r)) r half-pi pi)
    (cairo-arc cr (+ x r) (+ y r) r pi (* 3 half-pi))
    (cairo-close-path cr)
    (cairo-fill cr)))

(defun translate (cr x y)
  "Move the origin of CR by X,Y."
  (cairo-translate cr (float x 1d0) (float y 1d0)))

(defun clip-rectangle (cr x y width height)
  "Restrict drawing on CR to the rectangle at X,Y of WIDTH x HEIGHT,
until the enclosing save-restore ends."
  (cairo-rectangle cr (float x 1d0) (float y 1d0)
                   (float width 1d0) (float height 1d0))
  (cairo-clip cr))

;;; Text

(defmacro with-layout ((layout cr &rest options &key text markup font width
                                                      ellipsize alignment)
                       &body body)
  "Run BODY with LAYOUT bound to a pango layout for CR, set up as
MAKE-LAYOUT does, and released afterwards."
  (declare (ignore text markup font width ellipsize alignment))
  `(let ((,layout (make-layout ,cr ,@options)))
     (unwind-protect (progn ,@body)
       (g-object-unref ,layout))))

(defun make-layout (cr &key text markup font width ellipsize alignment)
  "A pango layout for CR showing TEXT, or MARKUP in pango's markup
language, in FONT (a pango font description such as \"monospace 12\").
WIDTH, in pixels, wraps or, with ELLIPSIZE (:start, :middle or :end),
shortens the text to fit; ALIGNMENT is :left, :center or :right.
Release it with g-object-unref; with-layout does."
  (let ((layout (pango-cairo-create-layout cr)))
    (when font
      (let ((description (pango-font-description-from-string font)))
        (pango-layout-set-font-description layout description)
        (pango-font-description-free description)))
    (when width
      (pango-layout-set-width layout (round (* width +pango-scale+))))
    (when ellipsize
      (pango-layout-set-ellipsize layout (ecase ellipsize
                                           (:none +ellipsize-none+)
                                           (:start +ellipsize-start+)
                                           (:middle +ellipsize-middle+)
                                           (:end +ellipsize-end+))))
    (when alignment
      (pango-layout-set-alignment layout (ecase alignment
                                           (:left +align-left+)
                                           (:center +align-center+)
                                           (:right +align-right+))))
    (cond (markup (pango-layout-set-markup layout markup -1))
          (text (pango-layout-set-text layout text -1)))
    layout))

(defun layout-pixel-size (layout)
  "The width and height of LAYOUT in pixels, as two values."
  (cffi:with-foreign-objects ((width :int) (height :int))
    (pango-layout-get-pixel-size layout width height)
    (values (cffi:mem-ref width :int) (cffi:mem-ref height :int))))

(defun show-layout (cr layout x y &optional color)
  "Draw LAYOUT with its top left corner at X,Y, with COLOR or the current
source."
  (when color
    (set-color cr color))
  (cairo-move-to cr (float x 1d0) (float y 1d0))
  (pango-cairo-update-layout cr layout)
  (pango-cairo-show-layout cr layout))

(defun draw-text (cr text x y &key font color markup width ellipsize alignment)
  "Draw TEXT (or, with MARKUP true, pango markup) with its top left
corner at X,Y; see make-layout for the other arguments. Return the
width and height drawn, in pixels."
  (with-layout (layout cr :text (unless markup text) :markup (when markup text)
                          :font font :width width :ellipsize ellipsize
                          :alignment alignment)
    (show-layout cr layout x y color)
    (layout-pixel-size layout)))

(defun text-size (cr text &key font markup)
  "The width and height TEXT would take in FONT, in pixels, as two values."
  (with-layout (layout cr :text (unless markup text) :markup (when markup text)
                          :font font)
    (layout-pixel-size layout)))

;;; Images

(defun load-png (pathname)
  "A cairo image surface with the PNG at PATHNAME, to destroy with
cairo-surface-destroy, or NIL when it cannot be read."
  (let ((surface (cairo-image-surface-create-from-png (namestring pathname))))
    (if (zerop (cairo-surface-status surface))
        surface
        (progn (cairo-surface-destroy surface) nil))))

(defun image-size (surface)
  "The width and height of the image SURFACE, as two values."
  (values (cairo-image-surface-get-width surface)
          (cairo-image-surface-get-height surface)))

(defun draw-image-cover (cr image width height)
  "Draw the image surface IMAGE scaled to cover WIDTH x HEIGHT at the
origin, keeping its proportions, centered, cropping what does not fit."
  (multiple-value-bind (iw ih) (image-size image)
    (when (and (plusp iw) (plusp ih))
      (let* ((scale (max (/ width iw) (/ height ih)))
             (dx (/ (- width (* iw scale)) 2))
             (dy (/ (- height (* ih scale)) 2)))
        (save-restore (cr)
          (clip-rectangle cr 0 0 width height)
          (cairo-translate cr (float dx 1d0) (float dy 1d0))
          (cairo-scale cr (float scale 1d0) (float scale 1d0))
          (cairo-set-source-surface cr image 0d0 0d0)
          (cairo-pattern-set-filter (cairo-get-source cr) +filter-good+)
          (cairo-paint cr))))))
