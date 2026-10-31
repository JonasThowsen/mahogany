(cl:in-package #:hrt)

;; next section imported from file heart/include/hrt/hrt_input.h

(cffi:defcstruct hrt-server)

(cffi:defcstruct hrt-seat-callbacks)

(cffi:defcstruct hrt-canvas)

(cffi:defcenum hrt-touchpad-state
  (:hrt-touchpad-default 0)
  (:hrt-touchpad-enabled 1)
  (:hrt-touchpad-disabled 2))

(cffi:defcstruct hrt-seat-destroy
  (seat (:struct wl-listener))
  (keyboard (:struct wl-listener)))

(cffi:defcstruct hrt-seat-touchpad
  (tap hrt-touchpad-state)
  (dwt hrt-touchpad-state)
  (natural-scroll hrt-touchpad-state)
  (accel-set :bool)
  (accel :double))

(cffi:defcstruct hrt-seat-mouse
  (natural-scroll hrt-touchpad-state)
  (accel-set :bool)
  (accel :double))

(cffi:defcstruct hrt-seat
  (server (:pointer (:struct hrt-server)))
  (cursor :pointer #| (:struct wlr-cursor) |#)
  (keyboard-group :pointer #| (:struct wlr-keyboard-group) |#)
  (xcursor-manager :pointer #| (:struct wlr-xcursor-manager) |#)
  (seat :pointer #| (:struct wlr-seat) |#)
  (inputs (:struct wl-list))
  (new-input (:struct wl-listener))
  (xkb-context :pointer #| (:struct xkb-context) |#)
  (motion (:struct wl-listener))
  (motion-absolute (:struct wl-listener))
  (button (:struct wl-listener))
  (axis (:struct wl-listener))
  (frame (:struct wl-listener))
  (request-cursor (:struct wl-listener))
  (request-set-shape (:struct wl-listener))
  (keyboard-key (:struct wl-listener))
  (keyboard-modifiers (:struct wl-listener))
  (request-selection (:struct wl-listener))
  (request-primary-selection (:struct wl-listener))
  (request-start-drag (:struct wl-listener))
  (start-drag (:struct wl-listener))
  (callbacks (:pointer (:struct hrt-seat-callbacks)))
  (cursor-image (:pointer :char))
  (cursor-img-buf-len :size)
  (grabbed :bool)
  (destroy (:struct hrt-seat-destroy))
  (canvas-under (:pointer (:struct hrt-canvas)))
  (canvas-under-destroy (:struct wl-listener))
  (touchpad (:struct hrt-seat-touchpad))
  (mouse (:struct hrt-seat-mouse))
  (numlock :bool))

(cffi:defcstruct hrt-keypress-info
  (keysyms :pointer #| xkb-keysym-t |#)
  (modifiers :uint32)
  (keysyms-len :size)
  (wl-key-state :unsigned-int #| enum wl-keyboard-key-state |#))

(cffi:defcstruct hrt-seat-callbacks
  (button-event :pointer #| function ptr void (struct hrt_seat *, struct wlr_pointer_button_event *) |#)
  (wheel-event :pointer #| function ptr void (struct hrt_seat *, struct wlr_pointer_axis_event *) |#)
  (keyboard-keypress-event :pointer #| function ptr _Bool (struct hrt_seat *, struct hrt_keypress_info *) |#)
  (switch-event :pointer #| function ptr void (struct hrt_seat *, int, _Bool) |#))

(cffi:defcstruct hrt-input
  (wlr-input-device :pointer #| (:struct wlr-input-device) |#)
  (seat (:pointer (:struct hrt-seat)))
  (link (:struct wl-list))
  (destroy (:struct wl-listener))
  (switch-toggle (:struct wl-listener)))

#-HRT-DEBUG
(declaim (inline hrt-seat-reset-view-under))
(cffi:defcfun ("hrt_seat_reset_view_under" hrt-seat-reset-view-under) :void
  "Send the appropriate cursor event to the view under the
cursor and ensure the cursor has the correct image
for what it is hovering over."
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-seat-grab))
(cffi:defcfun ("hrt_seat_grab" hrt-seat-grab) :void
  "Unfocus all clients and prevent input events from being emitted
and set the cursor image to the given image name."
  (seat (:pointer (:struct hrt-seat)))
  (img-name (:pointer :char)))

#-HRT-DEBUG
(declaim (inline hrt-seat-ungrab))
(cffi:defcfun ("hrt_seat_ungrab" hrt-seat-ungrab) :void
  "Reactivate input events and return to normal cursor image behavior."
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-seat-notify-button))
(cffi:defcfun ("hrt_seat_notify_button" hrt-seat-notify-button) :void
  (seat (:pointer (:struct hrt-seat)))
  (event :pointer #| (:struct wlr-pointer-button-event) |#))

#-HRT-DEBUG
(declaim (inline hrt-seat-notify-axis))
(cffi:defcfun ("hrt_seat_notify_axis" hrt-seat-notify-axis) :void
  (seat (:pointer (:struct hrt-seat)))
  (event :pointer #| (:struct wlr-pointer-axis-event) |#))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-keymap))
(cffi:defcfun ("hrt_seat_set_keymap" hrt-seat-set-keymap) :bool
  (seat (:pointer (:struct hrt-seat)))
  (rules :pointer #| (:struct xkb-rule-names) |#)
  (flags xkb:keymap-compile-flags))

#-HRT-DEBUG
(declaim (inline hrt-seat-cursor-set-theme))
(cffi:defcfun ("hrt_seat_cursor_set_theme" hrt-seat-cursor-set-theme) :bool
  "Set the xcursor theme used by the cursor as well as the cursor size."
  (seat (:pointer (:struct hrt-seat)))
  (theme-name (:pointer :char))
  (base-size :uint32))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-repeat-info))
(cffi:defcfun ("hrt_seat_set_repeat_info" hrt-seat-set-repeat-info) :void
  "RATE_HZ repeats per second after DELAY_MS milliseconds.
A rate of 0 disables repeat."
  (seat (:pointer (:struct hrt-seat)))
  (rate-hz :int32)
  (delay-ms :int32))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-touchpad-tap))
(cffi:defcfun ("hrt_seat_set_touchpad_tap" hrt-seat-set-touchpad-tap) :void
  (seat (:pointer (:struct hrt-seat)))
  (state hrt-touchpad-state))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-touchpad-dwt))
(cffi:defcfun ("hrt_seat_set_touchpad_dwt" hrt-seat-set-touchpad-dwt) :void
  (seat (:pointer (:struct hrt-seat)))
  (state hrt-touchpad-state))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-touchpad-accel))
(cffi:defcfun ("hrt_seat_set_touchpad_accel" hrt-seat-set-touchpad-accel) :void
  "Pointer acceleration, from -1.0 (slowest) through 0.0 (libinput's default)
to 1.0 (fastest)."
  (seat (:pointer (:struct hrt-seat)))
  (speed :double))

#-HRT-DEBUG
(declaim (inline hrt-seat-reset-touchpad-accel))
(cffi:defcfun ("hrt_seat_reset_touchpad_accel" hrt-seat-reset-touchpad-accel) :void
  "Return the pointer acceleration to libinput's default for each device."
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-touchpad-natural-scroll))
(cffi:defcfun ("hrt_seat_set_touchpad_natural_scroll" hrt-seat-set-touchpad-natural-scroll) :void
  "Natural (reversed) scrolling on touchpads, or on mice and other
pointers that are not touchpads."
  (seat (:pointer (:struct hrt-seat)))
  (state hrt-touchpad-state))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-mouse-natural-scroll))
(cffi:defcfun ("hrt_seat_set_mouse_natural_scroll" hrt-seat-set-mouse-natural-scroll) :void
  (seat (:pointer (:struct hrt-seat)))
  (state hrt-touchpad-state))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-mouse-accel))
(cffi:defcfun ("hrt_seat_set_mouse_accel" hrt-seat-set-mouse-accel) :void
  "Pointer acceleration for mice and other pointers that are not
touchpads, from -1.0 through 0.0 (libinput's default) to 1.0."
  (seat (:pointer (:struct hrt-seat)))
  (speed :double))

#-HRT-DEBUG
(declaim (inline hrt-seat-reset-mouse-accel))
(cffi:defcfun ("hrt_seat_reset_mouse_accel" hrt-seat-reset-mouse-accel) :void
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-seat-set-numlock))
(cffi:defcfun ("hrt_seat_set_numlock" hrt-seat-set-numlock) :void
  "Hold Num Lock on (or let it go) on every keyboard, now and as
keyboards and keymaps come."
  (seat (:pointer (:struct hrt-seat)))
  (on :bool))

#-HRT-DEBUG
(declaim (inline hrt-seat-cursor-lx))
(cffi:defcfun ("hrt_seat_cursor_lx" hrt-seat-cursor-lx) :double
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-seat-cursor-ly))
(cffi:defcfun ("hrt_seat_cursor_ly" hrt-seat-cursor-ly) :double
  (seat (:pointer (:struct hrt-seat))))

;; next section imported from file heart/include/hrt/hrt_view.h

(cffi:defcstruct hrt-view)

(cffi:defcstruct wlr-xdg-toplevel-decoration-v1)

(cffi:defctype view-destroy-handler :pointer #| function ptr void (struct hrt_view *) |#)

(cffi:defctype view-commit-handler :pointer #| function ptr void (struct hrt_view *) |#)

(cffi:defctype view-mapped-handler :pointer #| function ptr void (struct hrt_view *) |#)

(cffi:defctype view-request-fullscreen :pointer #| function ptr _Bool (struct hrt_view *, struct hrt_output *, _Bool) |#)

(cffi:defcstruct hrt-view-callbacks
  (new-view view-commit-handler)
  (view-size-changed view-commit-handler)
  (view-mapped view-mapped-handler)
  (view-unmapped view-mapped-handler)
  (request-minimize view-mapped-handler)
  (request-maximize view-mapped-handler)
  (view-destroyed view-destroy-handler)
  (request-fullscreen view-request-fullscreen)
  (get-view-output :pointer #| function ptr struct hrt_output *(struct hrt_view *) |#)
  (request-activate view-mapped-handler))

(cffi:defcstruct hrt-view
  (width :int)
  (height :int)
  (xdg-surface :pointer #| (:struct wlr-xdg-surface) |#)
  (xdg-toplevel :pointer #| (:struct wlr-xdg-toplevel) |#)
  (server (:pointer (:struct hrt-server)))
  (scene-tree :pointer #| (:struct wlr-scene-tree) |#)
  (xdg-scene :pointer #| (:struct wlr-scene-tree) |#)
  (map (:struct wl-listener))
  (unmap (:struct wl-listener))
  (commit (:struct wl-listener))
  (destroy (:struct wl-listener))
  (new-popup (:struct wl-listener))
  (request-maximize (:struct wl-listener))
  (request-minimize (:struct wl-listener))
  (request-fullscreen (:struct wl-listener))
  (callbacks (:pointer (:struct hrt-view-callbacks)))
  (decoration :pointer #| (:struct wlr-xdg-toplevel-decoration-v1) |#)
  (decoration-request-mode (:struct wl-listener))
  (decoration-destroy (:struct wl-listener)))

#-HRT-DEBUG
(declaim (inline hrt-view-info))
(cffi:defcfun ("hrt_view_info" hrt-view-info) :void
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-fullscreen))
(cffi:defcfun ("hrt_view_fullscreen" hrt-view-fullscreen) :uint32
  (view (:pointer (:struct hrt-view)))
  (fullscreen :bool))

#-HRT-DEBUG
(declaim (inline hrt-view-fullscreened))
(cffi:defcfun ("hrt_view_fullscreened" hrt-view-fullscreened) :bool
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-set-size))
(cffi:defcfun ("hrt_view_set_size" hrt-view-set-size) :uint32
  "Request that this view be the given size. Returns the associated configure
serial."
  (view (:pointer (:struct hrt-view)))
  (width :int)
  (height :int))

#-HRT-DEBUG
(declaim (inline hrt-view-mapped))
(cffi:defcfun ("hrt_view_mapped" hrt-view-mapped) :bool
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-set-relative))
(cffi:defcfun ("hrt_view_set_relative" hrt-view-set-relative) :void
  "Sets the view to the given coordinates relative to its parent."
  (view (:pointer (:struct hrt-view)))
  (x :int)
  (y :int))

#-HRT-DEBUG
(declaim (inline hrt-view-focus))
(cffi:defcfun ("hrt_view_focus" hrt-view-focus) :void
  "Focus the given view and perform the needed tasks to make
it visible to the user."
  (view (:pointer (:struct hrt-view)))
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-view-unfocus))
(cffi:defcfun ("hrt_view_unfocus" hrt-view-unfocus) :void
  "Unfocus the given view."
  (view (:pointer (:struct hrt-view)))
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-view-focused))
(cffi:defcfun ("hrt_view_focused" hrt-view-focused) :bool
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-set-hidden))
(cffi:defcfun ("hrt_view_set_hidden" hrt-view-set-hidden) :void
  "Stop the given view from being displayed"
  (view (:pointer (:struct hrt-view)))
  (hidden :bool))

#-HRT-DEBUG
(declaim (inline hrt-view-reparent))
(cffi:defcfun ("hrt_view_reparent" hrt-view-reparent) :void
  (view (:pointer (:struct hrt-view)))
  (node :pointer #| (:struct wlr-scene-tree) |#))

#-HRT-DEBUG
(declaim (inline hrt-view-raise-to-top))
(cffi:defcfun ("hrt_view_raise_to_top" hrt-view-raise-to-top) :void
  "Put the view above its siblings in its scene layer: a floating window
that was clicked, say."
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-request-close))
(cffi:defcfun ("hrt_view_request_close" hrt-view-request-close) :void
  "Request that the view be closed. This is the \"nice\" version
that is the same as clicking the close button on window decorations.
It does not garentee that the application actually closes, but
well behaved ones should."
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-send-configure))
(cffi:defcfun ("hrt_view_send_configure" hrt-view-send-configure) :void
  "Send a configure event to the view"
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-title))
(cffi:defcfun ("hrt_view_title" hrt-view-title) :string
  "Return the view's title."
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-app-id))
(cffi:defcfun ("hrt_view_app_id" hrt-view-app-id) :string
  "Return the view's application id (the client sets it before the view
maps, so it may be NULL on a new view), such as \"foot\" or
\"com.gabm.satty\"."
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-view-transient))
(cffi:defcfun ("hrt_view_transient" hrt-view-transient) :bool
  "Whether the view is a dialog of another view: its toplevel has a
parent."
  (view (:pointer (:struct hrt-view))))

;; next section imported from file heart/include/hrt/hrt_output.h

(cffi:defcstruct hrt-scene-output)

(cffi:defcstruct hrt-output-config
  (scale :double)
  (custom-mode :bool)
  (width :int)
  (height :int)
  (refresh-rate :float)
  (custom-position :bool)
  (x :int)
  (y :int)
  (enabled :bool))

(cffi:defcstruct hrt-output
  (wlr-output :pointer #| (:struct wlr-output) |#)
  (server (:pointer (:struct hrt-server)))
  (scene (:pointer (:struct hrt-scene-output)))
  (wlr-scene :pointer #| (:struct wlr-scene-output) |#)
  (usable-area (:struct wlr-box))
  (reserved-top :int)
  (reserved-right :int)
  (reserved-bottom :int)
  (reserved-left :int)
  (layer-surfaces (:struct wl-list))
  (request-state (:struct wl-listener))
  (frame (:struct wl-listener))
  (destroy (:struct wl-listener))
  (powered-off :bool))

(cffi:defcstruct hrt-output-callbacks
  (output-added :pointer #| function ptr void (struct hrt_output *) |#)
  (output-removed :pointer #| function ptr void (struct hrt_output *) |#)
  (output-layout-changed :pointer #| function ptr void () |#))

#-HRT-DEBUG
(declaim (inline hrt-output-configure))
(cffi:defcfun ("hrt_output_configure" hrt-output-configure) :bool
  (output (:pointer (:struct hrt-output)))
  (config (:pointer (:struct hrt-output-config))))

#-HRT-DEBUG
(declaim (inline hrt-output-configure-atomic))
(cffi:defcfun ("hrt_output_configure_atomic" hrt-output-configure-atomic) :bool
  (outputs (:pointer (:pointer (:struct hrt-output)) #| array |#))
  (configs (:pointer (:struct hrt-output-config) #| array |#))
  (length :size))

#-HRT-DEBUG
(declaim (inline hrt-output-resolution))
(cffi:defcfun ("hrt_output_resolution" hrt-output-resolution) :void
  "Get the effective output resolution of the output that can be used to
set the width and height of views."
  (output (:pointer (:struct hrt-output)))
  (width (:pointer :int))
  (height (:pointer :int)))

#-HRT-DEBUG
(declaim (inline hrt-output-position))
(cffi:defcfun ("hrt_output_position" hrt-output-position) :void
  (output (:pointer (:struct hrt-output)))
  (x (:pointer :int))
  (y (:pointer :int)))

#-HRT-DEBUG
(declaim (inline hrt-output-set-reserved))
(cffi:defcfun ("hrt_output_set_reserved" hrt-output-set-reserved) :void
  "Keep space free at the edges of the output, in layout coordinates, the
way a layer surface's exclusive zone does: the usable area shrinks by
it, layer surfaces are arranged inside what is left, and the
layers_reconfigured callback runs if the usable area changed.
Negative values count as 0."
  (output (:pointer (:struct hrt-output)))
  (top :int)
  (right :int)
  (bottom :int)
  (left :int))

#-HRT-DEBUG
(declaim (inline hrt-output-enabled))
(cffi:defcfun ("hrt_output_enabled" hrt-output-enabled) :bool
  "Whether the output is in use: configured on, whether or not its power
is off at the moment."
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-set-power))
(cffi:defcfun ("hrt_output_set_power" hrt-output-set-power) :bool
  "Turn the output's power off, or on again. It keeps its place in the
layout and its windows; this is for idling, not for configuration.
Returns false if the output refused."
  (output (:pointer (:struct hrt-output)))
  (on :bool))

#-HRT-DEBUG
(declaim (inline hrt-output-powered-off))
(cffi:defcfun ("hrt_output_powered_off" hrt-output-powered-off) :bool
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-scale))
(cffi:defcfun ("hrt_output_scale" hrt-output-scale) :double
  "The output's scale: layout coordinates times it are pixels."
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-name))
(cffi:defcfun ("hrt_output_name" hrt-output-name) :string
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-make))
(cffi:defcfun ("hrt_output_make" hrt-output-make) :string
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-model))
(cffi:defcfun ("hrt_output_model" hrt-output-model) :string
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-output-serial))
(cffi:defcfun ("hrt_output_serial" hrt-output-serial) :string
  (output (:pointer (:struct hrt-output))))

;; next section imported from file heart/include/hrt/hrt_scene.h

(cffi:defcstruct hrt-scene-root-listeners
  (scene-destroy (:struct wl-listener)))

(cffi:defcstruct hrt-scene-root
  (background :pointer #| (:struct wlr-scene-tree) |#)
  (bottom :pointer #| (:struct wlr-scene-tree) |#)
  (normal :pointer #| (:struct wlr-scene-tree) |#)
  (fullscreen :pointer #| (:struct wlr-scene-tree) |#)
  (top :pointer #| (:struct wlr-scene-tree) |#)
  (overlay :pointer #| (:struct wlr-scene-tree) |#)
  (listeners (:struct hrt-scene-root-listeners))
  (session-lock :pointer #| (:struct wlr-scene-tree) |#))

(cffi:defcstruct hrt-scene-output
  (background :pointer #| (:struct wlr-scene-tree) |#)
  (bottom :pointer #| (:struct wlr-scene-tree) |#)
  (top :pointer #| (:struct wlr-scene-tree) |#)
  (overlay :pointer #| (:struct wlr-scene-tree) |#)
  (output (:pointer (:struct hrt-output)))
  (session-lock :pointer #| (:struct wlr-scene-tree) |#))

(cffi:defcstruct hrt-scene-group
  (layers :pointer #| (:struct wlr-scene-tree) |#)
  (fullscreen :pointer #| (:struct wlr-scene-tree) |#)
  (server (:pointer (:struct hrt-server))))

(cffi:defcstruct hrt-scene-fullscreen-node
  (layer :pointer #| (:struct wlr-scene-tree) |#)
  (background :pointer #| (:struct wlr-scene-rect) |#)
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-scene-root-destroy))
(cffi:defcfun ("hrt_scene_root_destroy" hrt-scene-root-destroy) :void
  (scene-root (:pointer (:struct hrt-scene-root))))

#-HRT-DEBUG
(declaim (inline hrt-scene-output-create))
(cffi:defcfun ("hrt_scene_output_create" hrt-scene-output-create) (:pointer (:struct hrt-scene-output))
  (scene (:pointer (:struct hrt-scene-root))))

#-HRT-DEBUG
(declaim (inline hrt-scene-output-destroy))
(cffi:defcfun ("hrt_scene_output_destroy" hrt-scene-output-destroy) :void
  (output (:pointer (:struct hrt-scene-output))))

#-HRT-DEBUG
(declaim (inline hrt-scene-output-get-layer))
(cffi:defcfun ("hrt_scene_output_get_layer" hrt-scene-output-get-layer) :pointer #| (:struct wlr-scene-tree) |#
  (output (:pointer (:struct hrt-scene-output)))
  (layer-type zwlr-layer-shell-v1-layer))

#-HRT-DEBUG
(declaim (inline hrt-scene-group-destroy))
(cffi:defcfun ("hrt_scene_group_destroy" hrt-scene-group-destroy) :void
  (group (:pointer (:struct hrt-scene-group))))

#-HRT-DEBUG
(declaim (inline hrt-scene-group-set-enabled))
(cffi:defcfun ("hrt_scene_group_set_enabled" hrt-scene-group-set-enabled) :void
  (group (:pointer (:struct hrt-scene-group)))
  (enabled :bool))

#-HRT-DEBUG
(declaim (inline hrt-scene-group-fullscreen-layer))
(cffi:defcfun ("hrt_scene_group_fullscreen_layer" hrt-scene-group-fullscreen-layer) :pointer #| (:struct wlr-scene-tree) |#
  "The group's tree in the fullscreen layer, for hrt_scene_create_fullscreen_node."
  (group (:pointer (:struct hrt-scene-group))))

#-HRT-DEBUG
(declaim (inline hrt-scene-layer-create))
(cffi:defcfun ("hrt_scene_layer_create" hrt-scene-layer-create) :pointer #| (:struct wlr-scene-tree) |#
  (group (:pointer (:struct hrt-scene-group))))

#-HRT-DEBUG
(declaim (inline hrt-scene-layer-destroy))
(cffi:defcfun ("hrt_scene_layer_destroy" hrt-scene-layer-destroy) :void
  (layer :pointer #| (:struct wlr-scene-tree) |#))

#-HRT-DEBUG
(declaim (inline hrt-scene-layer-add-view))
(cffi:defcfun ("hrt_scene_layer_add_view" hrt-scene-layer-add-view) :void
  (layer :pointer #| (:struct wlr-scene-tree) |#)
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-scene-layer-transfer))
(cffi:defcfun ("hrt_scene_layer_transfer" hrt-scene-layer-transfer) :void
  "Transfer all of the views in the source layer to the
destination layer"
  (server (:pointer (:struct hrt-server)))
  (source :pointer #| (:struct wlr-scene-tree) |#)
  (destination :pointer #| (:struct wlr-scene-tree) |#))

#-HRT-DEBUG
(declaim (inline hrt-scene-group-layers))
(cffi:defcfun ("hrt_scene_group_layers" hrt-scene-group-layers) :pointer #| (:struct wlr-scene-tree) |#
  (group (:pointer (:struct hrt-scene-group))))

#-HRT-DEBUG
(declaim (inline hrt-scene-create-fullscreen-node))
(cffi:defcfun ("hrt_scene_create_fullscreen_node" hrt-scene-create-fullscreen-node) (:pointer (:struct hrt-scene-fullscreen-node))
  "Create a hrt_scene_fullscreen_layer with a black bacground of the given size.
Mode the hrt_view inside the node, removing it from where ever it was in the scene tree."
  (layer :pointer #| (:struct wlr-scene-tree) |#)
  (view (:pointer (:struct hrt-view)))
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-scene-fullscreen-swap))
(cffi:defcfun ("hrt_scene_fullscreen_swap" hrt-scene-fullscreen-swap) (:pointer (:struct hrt-view))
  (node (:pointer (:struct hrt-scene-fullscreen-node)))
  (view (:pointer (:struct hrt-view))))

#-HRT-DEBUG
(declaim (inline hrt-scene-fullscreen-node-destroy))
(cffi:defcfun ("hrt_scene_fullscreen_node_destroy" hrt-scene-fullscreen-node-destroy) (:pointer (:struct hrt-view))
  "Destroy the given background node, moving the struct hrt_view to the
normral layer.
Returns the view that was in the node."
  (node (:pointer (:struct hrt-scene-fullscreen-node))))

#-HRT-DEBUG
(declaim (inline hrt-scene-node-set-dimensions))
(cffi:defcfun ("hrt_scene_node_set_dimensions" hrt-scene-node-set-dimensions) :uint32
  (node (:pointer (:struct hrt-scene-fullscreen-node)))
  (width :int)
  (height :int))

#-HRT-DEBUG
(declaim (inline hrt-scene-node-set-position))
(cffi:defcfun ("hrt_scene_node_set_position" hrt-scene-node-set-position) :void
  (node (:pointer (:struct hrt-scene-fullscreen-node)))
  (x :int)
  (y :int))

#-HRT-DEBUG
(declaim (inline hrt-scene-fullscreen-configure))
(cffi:defcfun ("hrt_scene_fullscreen_configure" hrt-scene-fullscreen-configure) :uint32
  (group (:pointer (:struct hrt-scene-fullscreen-node)))
  (output (:pointer (:struct hrt-output))))

;; next section imported from file heart/include/hrt/hrt_message.h

(cffi:defcenum window-gravity
  (:gravity-top-right 0)
  (:gravity-top-left 1)
  (:gravity-bottom-right 2)
  (:gravity-bottom-left 3)
  (:gravity-right 4)
  (:gravity-left 5)
  (:gravity-top 6)
  (:gravity-bottom 7)
  (:gravity-center 8)
  (:gravity-max 8))

(cffi:defcstruct hrt-message-theme
  (font (:pointer :char))
  (font-color :float :count 4)
  (background-color :float :count 4)
  (border-color :float :count 4)
  (message-padding :int)
  (message-border-width :int)
  (margin-x :int)
  (margin-y :int))

#-HRT-DEBUG
(declaim (inline hrt-toast-message))
(cffi:defcfun ("hrt_toast_message" hrt-toast-message) :bool
  (server (:pointer (:struct hrt-server)))
  (output (:pointer (:struct hrt-output)))
  (text (:pointer :char))
  (gravity window-gravity)
  (theme (:pointer (:struct hrt-message-theme)))
  (ms-delay :int))

#-HRT-DEBUG
(declaim (inline hrt-toast-message-close))
(cffi:defcfun ("hrt_toast_message_close" hrt-toast-message-close) :void
  "Take down the message hrt_toast_message shows, if there is one, before
its time is up."
  (server (:pointer (:struct hrt-server))))

;; next section imported from file heart/include/hrt/hrt_event_loop.h

(cffi:defcenum hrt-event-mask
  (+hrt-event-readable+ 1)
  (+hrt-event-writable+ 2)
  (+hrt-event-hangup+ 4)
  (+hrt-event-error+ 8))

(cffi:defcstruct hrt-fd-semaphore
  (fd :int)
  (event-source :pointer #| (:struct wl-event-source) |#))

(cffi:defcstruct hrt-event-loop-timer
  (event-source :pointer #| (:struct wl-event-source) |#))

(cffi:defctype hrt-event-loop-timer-func-t :pointer #| wl-event-loop-timer-func-t |#)

(cffi:defctype hrt-event-loop-fd-func-t :pointer #| wl-event-loop-fd-func-t |#)

#-HRT-DEBUG
(declaim (inline hrt-event-loop-add-fd))
(cffi:defcfun ("hrt_event_loop_add_fd" hrt-event-loop-add-fd) :pointer #| (:struct wl-event-source) |#
  (server (:pointer (:struct hrt-server)))
  (fd :int)
  (mask :uint32)
  (callback hrt-event-loop-fd-func-t)
  (data (:pointer :void)))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-remove))
(cffi:defcfun ("hrt_event_loop_remove" hrt-event-loop-remove) :void
  (source :pointer #| (:struct wl-event-source) |#))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-semaphore-add))
(cffi:defcfun ("hrt_event_loop_semaphore_add" hrt-event-loop-semaphore-add) (:pointer (:struct hrt-fd-semaphore))
  "Create a semaphore fd (via eventfd(2)), and call the provided function
whenever the semaphore is non-zero."
  (server (:pointer (:struct hrt-server)))
  (initval :int)
  (callback hrt-event-loop-fd-func-t))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-semaphore-increment))
(cffi:defcfun ("hrt_event_loop_semaphore_increment" hrt-event-loop-semaphore-increment) :bool
  "Increment the given semaphore by the given value."
  (fd (:pointer (:struct hrt-fd-semaphore)))
  (increment :uint64))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-semaphore-decrement))
(cffi:defcfun ("hrt_event_loop_semaphore_decrement" hrt-event-loop-semaphore-decrement) :bool
  "Decrement the semaphore by 1"
  (fd (:pointer (:struct hrt-fd-semaphore))))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-semaphore-close))
(cffi:defcfun ("hrt_event_loop_semaphore_close" hrt-event-loop-semaphore-close) :void
  "Close the semaphore fd and remove it from the event loop."
  (fd (:pointer (:struct hrt-fd-semaphore))))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-timer-add))
(cffi:defcfun ("hrt_event_loop_timer_add" hrt-event-loop-timer-add) (:pointer (:struct hrt-event-loop-timer))
  (server (:pointer (:struct hrt-server)))
  (callback hrt-event-loop-timer-func-t))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-timer-update))
(cffi:defcfun ("hrt_event_loop_timer_update" hrt-event-loop-timer-update) :int
  (timer (:pointer (:struct hrt-event-loop-timer)))
  (ms-delay :int))

#-HRT-DEBUG
(declaim (inline hrt-event-loop-timer-destroy))
(cffi:defcfun ("hrt_event_loop_timer_destroy" hrt-event-loop-timer-destroy) :void
  (timer (:pointer (:struct hrt-event-loop-timer))))

;; next section imported from file heart/include/hrt/hrt_layer_shell.h

(cffi:defcstruct hrt-layer-shell-callbacks)

(cffi:defcstruct hrt-layer-shell-surface-events
  (commit (:struct wl-listener))
  (map (:struct wl-listener))
  (unmap (:struct wl-listener))
  (new-popup (:struct wl-listener))
  (layer-surface-destroy (:struct wl-listener)))

(cffi:defcstruct hrt-layer-shell-surface
  (layer-surface :pointer #| (:struct wlr-layer-surface-v1) |#)
  (scene-surface :pointer #| (:struct wlr-scene-layer-surface-v1) |#)
  (output (:pointer (:struct hrt-output)))
  (link (:struct wl-list))
  (tree :pointer #| (:struct wlr-scene-tree) |#)
  (mapped :bool)
  (callbacks (:pointer (:struct hrt-layer-shell-callbacks)))
  (events (:struct hrt-layer-shell-surface-events)))

(cffi:defctype layer-shell-event-handler :pointer #| function ptr void (struct hrt_layer_shell_surface *) |#)

(cffi:defcstruct hrt-layer-shell-callbacks
  (new-layer-surface layer-shell-event-handler)
  (layer-surface-mapped layer-shell-event-handler)
  (layer-surface-unmapped layer-shell-event-handler)
  (layers-reconfigured :pointer #| function ptr void (struct hrt_output *) |#)
  (keyboard-interactivity-updated layer-shell-event-handler)
  (layer-changed layer-shell-event-handler))

(cffi:defcenum hrt-layer-shell-keyboard-interactivity
  (:layer-shell-keyboard-none 0)
  (:layer-shell-keyboard-exclusive 1)
  (:layer-shell-keyboard-on-demand 2))

#-HRT-DEBUG
(declaim (inline hrt-layer-shell-surface-abort))
(cffi:defcfun ("hrt_layer_shell_surface_abort" hrt-layer-shell-surface-abort) :void
  "Destroy a partially created hrt_layer_shell-surface object"
  (surface (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-close))
(cffi:defcfun ("hrt_layer_surface_close" hrt-layer-surface-close) :void
  "Send the layer surface the `closed` event and take it down.
`closed` means the surface will no longer be shown and further changes
to it are ignored, so the surface is unmapped and freed.
The client wlr_layer_surface destroy is up for the client to handle once it sees the event."
  (surface (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-output))
(cffi:defcfun ("hrt_layer_surface_output" %hrt-layer-surface-output) (:pointer (:struct hrt-output))
  (layer-shell (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-shell-surface-set-output))
(cffi:defcfun ("hrt_layer_shell_surface_set_output" hrt-layer-shell-surface-set-output) :void
  (layer-shell (:pointer (:struct hrt-layer-shell-surface)))
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-layer-shell-surface-place))
(cffi:defcfun ("hrt_layer_shell_surface_place" hrt-layer-shell-surface-place) :void
  "Place a freshly-initialized surface in an output. Should only be called once during
intial placement."
  (surface (:pointer (:struct hrt-layer-shell-surface)))
  (output (:pointer (:struct hrt-output))))

#-HRT-DEBUG
(declaim (inline hrt-layer-shell-finish-init))
(cffi:defcfun ("hrt_layer_shell_finish_init" hrt-layer-shell-finish-init) :void
  "Finish initializing the layer shell object"
  (surface (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-focus))
(cffi:defcfun ("hrt_layer_surface_focus" hrt-layer-surface-focus) :void
  (surface (:pointer (:struct hrt-layer-shell-surface)))
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-unfocus))
(cffi:defcfun ("hrt_layer_surface_unfocus" hrt-layer-surface-unfocus) :void
  (surface (:pointer (:struct hrt-layer-shell-surface)))
  (seat (:pointer (:struct hrt-seat))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-keyboard-interactivity))
(cffi:defcfun ("hrt_layer_surface_keyboard_interactivity" hrt-layer-surface-keyboard-interactivity) hrt-layer-shell-keyboard-interactivity
  (surface (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-layer))
(cffi:defcfun ("hrt_layer_surface_layer" hrt-layer-surface-layer) zwlr-layer-shell-v1-layer
  (surface (:pointer (:struct hrt-layer-shell-surface))))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-position))
(cffi:defcfun ("hrt_layer_surface_position" hrt-layer-surface-position) :void
  (surface (:pointer (:struct hrt-layer-shell-surface)))
  (x (:pointer :int))
  (y (:pointer :int)))

#-HRT-DEBUG
(declaim (inline hrt-layer-surface-dimensions))
(cffi:defcfun ("hrt_layer_surface_dimensions" hrt-layer-surface-dimensions) :void
  (surface (:pointer (:struct hrt-layer-shell-surface)))
  (width (:pointer :int))
  (height (:pointer :int)))

;; next section imported from file heart/include/hrt/hrt_server.h

(cffi:defcstruct wlr-xdg-decoration-manager-v1)

(cffi:defcstruct wlr-xdg-activation-v1)

(cffi:defcstruct wlr-cursor-shape-manager-v1)

(cffi:defcstruct wlr-session-lock-manager-v1)

(cffi:defcstruct hrt-session-lock)

(cffi:defcstruct hrt-session-lock-callbacks)

(cffi:defcstruct hrt-canvas-callbacks)

(cffi:defcstruct hrt-server-destroy-listener
  (backend (:struct wl-listener))
  (headless (:struct wl-listener))
  (output-manager (:struct wl-listener))
  (layer-shell (:struct wl-listener))
  (idle-inhibit-manager (:struct wl-listener)))

(cffi:defcstruct hrt-server
  (wl-display :pointer #| (:struct wl-display) |#)
  (backend :pointer #| (:struct wlr-backend) |#)
  (headless-backend :pointer #| (:struct wlr-backend) |#)
  (session :pointer #| (:struct wlr-session) |#)
  (renderer :pointer #| (:struct wlr-renderer) |#)
  (compositor :pointer #| (:struct wlr-compositor) |#)
  (allocator :pointer #| (:struct wlr-allocator) |#)
  (scene :pointer #| (:struct wlr-scene) |#)
  (scene-layout :pointer #| (:struct wlr-scene-output-layout) |#)
  (new-output (:struct wl-listener))
  (output-manager :pointer #| (:struct wlr-output-manager-v1) |#)
  (output-layout :pointer #| (:struct wlr-output-layout) |#)
  (output-layout-changed (:struct wl-listener))
  (output-manager-apply (:struct wl-listener))
  (output-manager-test (:struct wl-listener))
  (seat (:struct hrt-seat))
  (scene-root (:pointer (:struct hrt-scene-root)))
  (fallback-output (:pointer (:struct hrt-output)))
  (xdg-shell :pointer #| (:struct wlr-xdg-shell) |#)
  (new-xdg-toplevel (:struct wl-listener))
  (layer-shell :pointer #| (:struct wlr-layer-shell-v1) |#)
  (new-layer-shell (:struct wl-listener))
  (ext-image-copy-capture-manager-v1 :pointer #| (:struct wlr-ext-image-copy-capture-manager-v1) |#)
  (idle-notifier :pointer #| (:struct wlr-idle-notifier-v1) |#)
  (idle-inhibit-manager :pointer #| (:struct wlr-idle-inhibit-manager-v1) |#)
  (new-idle-inhibitor (:struct wl-listener))
  (idle-inhibit-scheduled-update :pointer #| (:struct wl-event-source) |#)
  (destroy-listener (:struct hrt-server-destroy-listener))
  (output-callback (:pointer (:struct hrt-output-callbacks)))
  (view-callbacks (:pointer (:struct hrt-view-callbacks)))
  (layer-shell-callbacks (:pointer (:struct hrt-layer-shell-callbacks)))
  (message-timer-source :pointer #| (:struct wl-event-source) |#)
  (message-buffer :pointer #| (:struct wlr-scene-buffer) |#)
  (xdg-decoration-manager :pointer #| (:struct wlr-xdg-decoration-manager-v1) |#)
  (new-xdg-decoration (:struct wl-listener))
  (xdg-activation :pointer #| (:struct wlr-xdg-activation-v1) |#)
  (request-activate (:struct wl-listener))
  (cursor-shape-manager :pointer #| (:struct wlr-cursor-shape-manager-v1) |#)
  (session-lock-manager :pointer #| (:struct wlr-session-lock-manager-v1) |#)
  (new-session-lock (:struct wl-listener))
  (session-lock (:pointer (:struct hrt-session-lock)))
  (session-locked :bool)
  (session-lock-callbacks (:pointer (:struct hrt-session-lock-callbacks)))
  (idle-timeouts (:struct wl-list))
  (idle-last-activity-msec :int64)
  (idle-inhibited :bool)
  (canvas-callbacks (:pointer (:struct hrt-canvas-callbacks))))

#-HRT-DEBUG
(declaim (inline hrt-server-init))
(cffi:defcfun ("hrt_server_init" hrt-server-init) :bool
  (server (:pointer (:struct hrt-server)))
  (output-callbacks (:pointer (:struct hrt-output-callbacks)))
  (seat-callbacks (:pointer (:struct hrt-seat-callbacks)))
  (view-callbacks (:pointer (:struct hrt-view-callbacks)))
  (layer-shell-callbacks (:pointer (:struct hrt-layer-shell-callbacks)))
  (log-level wlr-log-importance))

#-HRT-DEBUG
(declaim (inline hrt-server-start))
(cffi:defcfun ("hrt_server_start" hrt-server-start) :bool
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-stop))
(cffi:defcfun ("hrt_server_stop" hrt-server-stop) :void
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-finish))
(cffi:defcfun ("hrt_server_finish" hrt-server-finish) :void
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-scene-tree))
(cffi:defcfun ("hrt_server_scene_tree" hrt-server-scene-tree) :pointer #| (:struct wlr-scene-tree) |#
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-seat))
(cffi:defcfun ("hrt_server_seat" hrt-server-seat) (:pointer (:struct hrt-seat))
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-group-create))
(cffi:defcfun ("hrt_server_group_create" hrt-server-group-create) (:pointer (:struct hrt-scene-group))
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-server-struct-size))
(cffi:defcfun ("hrt_server_struct_size" hrt-server-struct-size) :size)

;; next section imported from file heart/include/hrt/hrt_theme.h

(cffi:defcenum hrt-border-style
  (:hrt-border-solid 0)
  (:hrt-border-dotted 1))

;; next section imported from file heart/include/hrt/hrt_border_box.h

(cffi:defcstruct hrt-border-box-style)

(cffi:defcstruct hrt-border-box)

#-HRT-DEBUG
(declaim (inline hrt-border-box-style-create))
(cffi:defcfun ("hrt_border_box_style_create" hrt-border-box-style-create) (:pointer (:struct hrt-border-box-style))
  (border hrt-border-style)
  (color :pointer #| :float :count 4 |#)
  (line-width :double))

#-HRT-DEBUG
(declaim (inline hrt-border-box-style-ref))
(cffi:defcfun ("hrt_border_box_style_ref" hrt-border-box-style-ref) :void
  (style (:pointer (:struct hrt-border-box-style))))

#-HRT-DEBUG
(declaim (inline hrt-border-box-style-unref))
(cffi:defcfun ("hrt_border_box_style_unref" hrt-border-box-style-unref) :void
  (unknown (:pointer (:struct hrt-border-box-style))))

#-HRT-DEBUG
(declaim (inline hrt-border-box-style-update))
(cffi:defcfun ("hrt_border_box_style_update" hrt-border-box-style-update) :void
  (style (:pointer (:struct hrt-border-box-style)))
  (border hrt-border-style)
  (color :pointer #| :float :count 4 |#)
  (line-width :double))

#-HRT-DEBUG
(declaim (inline hrt-border-box-create))
(cffi:defcfun ("hrt_border_box_create" hrt-border-box-create) (:pointer (:struct hrt-border-box))
  (parent :pointer #| (:struct wlr-scene-tree) |#)
  (style (:pointer (:struct hrt-border-box-style)))
  (x :int)
  (y :int)
  (width :int)
  (height :int))

#-HRT-DEBUG
(declaim (inline hrt-border-box-destroy))
(cffi:defcfun ("hrt_border_box_destroy" hrt-border-box-destroy) :void
  (box (:pointer (:struct hrt-border-box))))

#-HRT-DEBUG
(declaim (inline hrt-border-box-set-size))
(cffi:defcfun ("hrt_border_box_set_size" hrt-border-box-set-size) :void
  (box (:pointer (:struct hrt-border-box)))
  (width :int)
  (height :int))

#-HRT-DEBUG
(declaim (inline hrt-border-box-set-relative))
(cffi:defcfun ("hrt_border_box_set_relative" hrt-border-box-set-relative) :void
  (box (:pointer (:struct hrt-border-box)))
  (x :int)
  (y :int))

#-HRT-DEBUG
(declaim (inline hrt-border-box-set-enabled))
(cffi:defcfun ("hrt_border_box_set_enabled" hrt-border-box-set-enabled) :void
  (box (:pointer (:struct hrt-border-box)))
  (enabled :bool))

#-HRT-DEBUG
(declaim (inline hrt-border-box-set-style))
(cffi:defcfun ("hrt_border_box_set_style" hrt-border-box-set-style) :void
  (box (:pointer (:struct hrt-border-box)))
  (style (:pointer (:struct hrt-border-box-style))))

#-HRT-DEBUG
(declaim (inline hrt-border-box-raise-to-top))
(cffi:defcfun ("hrt_border_box_raise_to_top" hrt-border-box-raise-to-top) :void
  (box (:pointer (:struct hrt-border-box))))

#-HRT-DEBUG
(declaim (inline hrt-border-box-lower-to-bottom))
(cffi:defcfun ("hrt_border_box_lower_to_bottom" hrt-border-box-lower-to-bottom) :void
  (box (:pointer (:struct hrt-border-box))))

;; next section imported from file heart/include/hrt/hrt_canvas.h

(cffi:defcstruct hrt-canvas-callbacks
  "Pointer input over canvases. X and Y are in the canvas's coordinates,
layout pixels from its top left corner. While the pointer is over a
canvas, no client has pointer focus. May be NULL, each of them."
  (pointer-motion :pointer #| function ptr void (struct hrt_canvas *, double, double) |#)
  (pointer-leave :pointer #| function ptr void (struct hrt_canvas *) |#)
  (pointer-button :pointer #| function ptr void (struct hrt_canvas *, double, double, uint32_t, _Bool) |#)
  (pointer-axis :pointer #| function ptr void (struct hrt_canvas *, double, double, _Bool, double) |#))

#-HRT-DEBUG
(declaim (inline hrt-canvas-set-callbacks))
(cffi:defcfun ("hrt_canvas_set_callbacks" hrt-canvas-set-callbacks) :void
  "Set the callbacks for pointer input over every canvas. The struct must
outlive the server."
  (server (:pointer (:struct hrt-server)))
  (callbacks (:pointer (:struct hrt-canvas-callbacks))))

#-HRT-DEBUG
(declaim (inline hrt-canvas-create))
(cffi:defcfun ("hrt_canvas_create" hrt-canvas-create) (:pointer (:struct hrt-canvas))
  "Create a canvas as a child of PARENT. It shows nothing until the first
hrt_canvas_commit.

If PARENT is destroyed, the canvas stays valid but shows nothing, and
the other functions do nothing; it still has to be destroyed."
  (parent :pointer #| (:struct wlr-scene-tree) |#))

#-HRT-DEBUG
(declaim (inline hrt-canvas-destroy))
(cffi:defcfun ("hrt_canvas_destroy" hrt-canvas-destroy) :void
  (canvas (:pointer (:struct hrt-canvas))))

#-HRT-DEBUG
(declaim (inline hrt-canvas-begin))
(cffi:defcfun ("hrt_canvas_begin" hrt-canvas-begin) :pointer #| cairo-surface-t |#
  "Start a new frame of WIDTH x HEIGHT, in layout coordinates, for an
output with the given SCALE. Return the cairo surface to draw it on:
its device scale is set, so draw in layout coordinates. The surface
belongs to the canvas; don't destroy it.

Return NULL if the frame could not be made. Starting a frame drops one
that was started and not committed."
  (canvas (:pointer (:struct hrt-canvas)))
  (width :int)
  (height :int)
  (scale :double))

#-HRT-DEBUG
(declaim (inline hrt-canvas-commit))
(cffi:defcfun ("hrt_canvas_commit" hrt-canvas-commit) :bool
  "Show the frame started by hrt_canvas_begin in place of the previous
one. Return false if there is no frame to show."
  (canvas (:pointer (:struct hrt-canvas))))

#-HRT-DEBUG
(declaim (inline hrt-canvas-set-position))
(cffi:defcfun ("hrt_canvas_set_position" hrt-canvas-set-position) :void
  "Place the canvas at X,Y relative to its parent."
  (canvas (:pointer (:struct hrt-canvas)))
  (x :int)
  (y :int))

#-HRT-DEBUG
(declaim (inline hrt-canvas-set-enabled))
(cffi:defcfun ("hrt_canvas_set_enabled" hrt-canvas-set-enabled) :void
  (canvas (:pointer (:struct hrt-canvas)))
  (enabled :bool))

;; next section imported from file heart/include/hrt/hrt_session_lock.h

(cffi:defcstruct hrt-session-lock-callbacks
  "ext-session-lock: a client such as swaylock locks the session. While
it is locked, every output shows only the client's lock surface (or
black until it has one), keyboard and pointer input go only to those
surfaces, and nothing else can take the focus. Should the client go
away without unlocking, the session stays locked and blank, red, until
another client locks it."
  (locked :pointer #| function ptr void (void) |#)
  (unlocked :pointer #| function ptr void (void) |#))

#-HRT-DEBUG
(declaim (inline hrt-session-lock-set-callbacks))
(cffi:defcfun ("hrt_session_lock_set_callbacks" hrt-session-lock-set-callbacks) :void
  "Set the callbacks run when the session is locked and unlocked. The
struct must outlive the server."
  (server (:pointer (:struct hrt-server)))
  (callbacks (:pointer (:struct hrt-session-lock-callbacks))))

#-HRT-DEBUG
(declaim (inline hrt-session-locked))
(cffi:defcfun ("hrt_session_locked" hrt-session-locked) :bool
  "Whether the session is locked, including left locked by a client that
went away."
  (server (:pointer (:struct hrt-server))))

;; next section imported from file heart/include/hrt/hrt_idle.h

(cffi:defcstruct hrt-idle-timeout)

(cffi:defctype hrt-idle-timeout-func :pointer #| function ptr void (struct hrt_idle_timeout *, void *) |#)

#-HRT-DEBUG
(declaim (inline hrt-idle-timeout-add))
(cffi:defcfun ("hrt_idle_timeout_add" hrt-idle-timeout-add) (:pointer (:struct hrt-idle-timeout))
  "Add a timeout of TIMEOUT_MSEC. RESUME may be NULL. DATA is handed to
both functions. Returns NULL when it could not be made."
  (server (:pointer (:struct hrt-server)))
  (timeout-msec :uint32)
  (idle hrt-idle-timeout-func)
  (resume hrt-idle-timeout-func)
  (data (:pointer :void)))

#-HRT-DEBUG
(declaim (inline hrt-idle-timeout-destroy))
(cffi:defcfun ("hrt_idle_timeout_destroy" hrt-idle-timeout-destroy) :void
  (timeout (:pointer (:struct hrt-idle-timeout))))

#-HRT-DEBUG
(declaim (inline hrt-idle-milliseconds))
(cffi:defcfun ("hrt_idle_milliseconds" hrt-idle-milliseconds) :uint64
  "Milliseconds since the last input, or since the start."
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-idle-inhibited))
(cffi:defcfun ("hrt_idle_inhibited" hrt-idle-inhibited) :bool
  "Whether a visible client asks that the user not be considered idle."
  (server (:pointer (:struct hrt-server))))

#-HRT-DEBUG
(declaim (inline hrt-idle-activity))
(cffi:defcfun ("hrt_idle_activity" hrt-idle-activity) :void
  "Count as input: restart the timeouts and run the resume functions of
those that had run out. For waking up from Lisp, say on a lid opening."
  (server (:pointer (:struct hrt-server))))
