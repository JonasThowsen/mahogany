(in-package #:hrt)

(cffi:defcfun ("hrt_add_output" hrt-add-output) :boolean
  (server (:pointer (:struct hrt-server))))

(cffi:defcfun ("hrt_debug_pointer_warp" hrt-debug-pointer-warp) :void
  "Move the pointer to LX,LY in layout coordinates, as an input device would."
  (server (:pointer (:struct hrt-server)))
  (lx :double)
  (ly :double))

(cffi:defcfun ("hrt_debug_pointer_button" hrt-debug-pointer-button) :void
  "Press or release BUTTON (a linux input code: 272 is the left button)."
  (server (:pointer (:struct hrt-server)))
  (button :uint32)
  (pressed :bool))
