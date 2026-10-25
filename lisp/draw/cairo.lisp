(in-package #:mahogany/draw)

;;; The parts of cairo and pango the compositor draws with. Written by
;;; hand rather than taken from cl-cairo2/cl-pango: heart already links
;;; both libraries, and the dozen functions below cover bars, menus and
;;; messages. Add here when something is missing.

(cffi:define-foreign-library libcairo
  (:unix (:or "libcairo.so.2" "libcairo.so")))

(cffi:define-foreign-library libpangocairo
  (:unix (:or "libpangocairo-1.0.so.0" "libpangocairo-1.0.so")))

(cffi:define-foreign-library libgobject
  (:unix (:or "libgobject-2.0.so.0" "libgobject-2.0.so")))

(defun load-libraries ()
  "Load cairo, pango and gobject, once. In the compositor they are
already loaded as libheart's dependencies, and this finds those; the
tests call it so they can draw without heart.

Loading a library SBCL has loaded before re-opens it (dlclose, dlopen),
which unloads pango under GObject's type registry: pango then fails to
register its types again and hangs. So a loaded library is left alone."
  (dolist (library '(libcairo libpangocairo libgobject))
    (unless (cffi:foreign-library-loaded-p library)
      (cffi:load-foreign-library library))))

;;; cairo

(defconstant +format-argb32+ 0)

(defconstant +operator-clear+ 0)
(defconstant +operator-source+ 1)
(defconstant +operator-over+ 2)

(cffi:defcfun ("cairo_create" cairo-create) :pointer
  (surface :pointer))

(cffi:defcfun ("cairo_destroy" cairo-destroy) :void
  (cr :pointer))

(cffi:defcfun ("cairo_save" cairo-save) :void
  (cr :pointer))

(cffi:defcfun ("cairo_restore" cairo-restore) :void
  (cr :pointer))

(cffi:defcfun ("cairo_set_source_rgba" cairo-set-source-rgba) :void
  (cr :pointer)
  (red :double)
  (green :double)
  (blue :double)
  (alpha :double))

(cffi:defcfun ("cairo_set_operator" cairo-set-operator) :void
  (cr :pointer)
  (operator :int))

(cffi:defcfun ("cairo_set_line_width" cairo-set-line-width) :void
  (cr :pointer)
  (width :double))

(cffi:defcfun ("cairo_rectangle" cairo-rectangle) :void
  (cr :pointer)
  (x :double)
  (y :double)
  (width :double)
  (height :double))

(cffi:defcfun ("cairo_arc" cairo-arc) :void
  (cr :pointer)
  (xc :double)
  (yc :double)
  (radius :double)
  (angle1 :double)
  (angle2 :double))

(cffi:defcfun ("cairo_move_to" cairo-move-to) :void
  (cr :pointer)
  (x :double)
  (y :double))

(cffi:defcfun ("cairo_line_to" cairo-line-to) :void
  (cr :pointer)
  (x :double)
  (y :double))

(cffi:defcfun ("cairo_close_path" cairo-close-path) :void
  (cr :pointer))

(cffi:defcfun ("cairo_new_path" cairo-new-path) :void
  (cr :pointer))

(cffi:defcfun ("cairo_fill" cairo-fill) :void
  (cr :pointer))

(cffi:defcfun ("cairo_stroke" cairo-stroke) :void
  (cr :pointer))

(cffi:defcfun ("cairo_paint" cairo-paint) :void
  (cr :pointer))

(cffi:defcfun ("cairo_clip" cairo-clip) :void
  (cr :pointer))

(cffi:defcfun ("cairo_translate" cairo-translate) :void
  (cr :pointer)
  (tx :double)
  (ty :double))

(cffi:defcfun ("cairo_image_surface_create" cairo-image-surface-create) :pointer
  (format :int)
  (width :int)
  (height :int))

(cffi:defcfun ("cairo_surface_destroy" cairo-surface-destroy) :void
  (surface :pointer))

(cffi:defcfun ("cairo_surface_flush" cairo-surface-flush) :void
  (surface :pointer))

(cffi:defcfun ("cairo_image_surface_get_data" cairo-image-surface-get-data) :pointer
  (surface :pointer))

(cffi:defcfun ("cairo_image_surface_get_stride" cairo-image-surface-get-stride) :int
  (surface :pointer))

(cffi:defcfun ("cairo_surface_write_to_png" cairo-surface-write-to-png) :int
  (surface :pointer)
  (filename :string))

;;; pango

(defconstant +pango-scale+ 1024
  "Pango units per pixel.")

(defconstant +ellipsize-none+ 0)
(defconstant +ellipsize-start+ 1)
(defconstant +ellipsize-middle+ 2)
(defconstant +ellipsize-end+ 3)

(defconstant +align-left+ 0)
(defconstant +align-center+ 1)
(defconstant +align-right+ 2)

(cffi:defcfun ("pango_cairo_create_layout" pango-cairo-create-layout) :pointer
  (cr :pointer))

(cffi:defcfun ("pango_cairo_update_layout" pango-cairo-update-layout) :void
  (cr :pointer)
  (layout :pointer))

(cffi:defcfun ("pango_cairo_show_layout" pango-cairo-show-layout) :void
  (cr :pointer)
  (layout :pointer))

(cffi:defcfun ("pango_layout_set_text" pango-layout-set-text) :void
  (layout :pointer)
  (text :string)
  (length :int))

(cffi:defcfun ("pango_layout_set_markup" pango-layout-set-markup) :void
  (layout :pointer)
  (markup :string)
  (length :int))

(cffi:defcfun ("pango_layout_set_font_description" pango-layout-set-font-description) :void
  (layout :pointer)
  (description :pointer))

(cffi:defcfun ("pango_layout_set_width" pango-layout-set-width) :void
  (layout :pointer)
  (width :int))

(cffi:defcfun ("pango_layout_set_ellipsize" pango-layout-set-ellipsize) :void
  (layout :pointer)
  (ellipsize :int))

(cffi:defcfun ("pango_layout_set_alignment" pango-layout-set-alignment) :void
  (layout :pointer)
  (alignment :int))

(cffi:defcfun ("pango_layout_get_pixel_size" pango-layout-get-pixel-size) :void
  (layout :pointer)
  (width (:pointer :int))
  (height (:pointer :int)))

(cffi:defcfun ("pango_font_description_from_string" pango-font-description-from-string) :pointer
  (string :string))

(cffi:defcfun ("pango_font_description_free" pango-font-description-free) :void
  (description :pointer))

(cffi:defcfun ("g_object_unref" g-object-unref) :void
  (object :pointer))
