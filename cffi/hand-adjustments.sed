# Adjustments to cl-bindgen's output that the Makefile applies after
# regenerating lisp/heart/hrt-bindings.lisp: the generator cannot know
# these (see doc/devel/adding-new-protocols-to-heart.org).

# Enum types defined in other packages, or not defined at all in Lisp:
s/^  (wl-key-state wl-keyboard-key-state))$/  (wl-key-state :unsigned-int #| enum wl-keyboard-key-state |#))/
s/^  (flags xkb-keymap-compile-flags))$/  (flags xkb:keymap-compile-flags))/
s/^(cffi:defctype hrt-event-loop-timer-func-t wl-event-loop-timer-func-t)$/(cffi:defctype hrt-event-loop-timer-func-t :pointer #| wl-event-loop-timer-func-t |#)/
s/^(cffi:defctype hrt-event-loop-fd-func-t wl-event-loop-fd-func-t)$/(cffi:defctype hrt-event-loop-fd-func-t :pointer #| wl-event-loop-fd-func-t |#)/
# The keyboard interactivity constants, as the Lisp code names them:
s/^  (:hrt-layer-shell-keyboard-\(none\|exclusive\|on-demand\) \([0-9]\))/  (:layer-shell-keyboard-\1 \2)/
# Wrapped in Lisp by a function of the unprefixed name:
s/^(cffi:defcfun ("hrt_layer_surface_output" hrt-layer-surface-output)/(cffi:defcfun ("hrt_layer_surface_output" %hrt-layer-surface-output)/
