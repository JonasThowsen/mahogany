(defpackage #:mahogany/draw
  (:use :cl)
  (:nicknames #:draw)
  (:local-nicknames (#:colors #:cl-colors2))
  (:documentation
   "Drawing with cairo and pango, for what the compositor draws itself:
bars, menus, on-screen displays. The functions take a cairo context
and draw in the coordinates of the surface it was made for; the
compositor's canvases (hrt:canvas) are made with their output's scale,
so those coordinates are layout pixels.")
  (:export
   ;; libraries
   #:load-libraries
   ;; contexts and surfaces
   #:with-context
   #:with-image-surface
   #:surface-write-png
   #:image-surface-pixel
   #:save-restore
   ;; colors
   #:color
   #:set-color
   ;; shapes
   #:clear
   #:fill-rectangle
   #:stroke-rectangle
   #:fill-rounded-rectangle
   #:translate
   #:clip-rectangle
   ;; text
   #:with-layout
   #:layout-pixel-size
   #:show-layout
   #:draw-text
   #:text-size
   ;; the bindings, for what the helpers don't cover
   #:cairo-create #:cairo-destroy #:cairo-save #:cairo-restore
   #:cairo-set-source-rgba #:cairo-set-operator #:cairo-set-line-width
   #:cairo-rectangle #:cairo-arc #:cairo-move-to #:cairo-line-to
   #:cairo-close-path #:cairo-new-path #:cairo-fill #:cairo-stroke
   #:cairo-paint #:cairo-clip #:cairo-translate
   #:cairo-image-surface-create #:cairo-surface-destroy #:cairo-surface-flush
   #:cairo-image-surface-get-data #:cairo-image-surface-get-stride
   #:cairo-surface-write-to-png
   #:pango-cairo-create-layout #:pango-cairo-update-layout
   #:pango-cairo-show-layout #:pango-layout-set-text
   #:pango-layout-set-markup #:pango-layout-set-font-description
   #:pango-layout-set-width #:pango-layout-set-ellipsize
   #:pango-layout-set-alignment #:pango-layout-get-pixel-size
   #:pango-font-description-from-string #:pango-font-description-free
   #:g-object-unref
   #:+operator-clear+ #:+operator-source+ #:+operator-over+
   #:+ellipsize-none+ #:+ellipsize-start+ #:+ellipsize-middle+ #:+ellipsize-end+
   #:+align-left+ #:+align-center+ #:+align-right+
   #:+pango-scale+))
