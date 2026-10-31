;;;; mahogany.asd

#+sbcl
(require 'sb-posix)

(asdf:defsystem #:mahogany
  :description "Mahogany is a tiling window manager for wayland a la stumpwm"
  :author "Stuart Dilts"
  :license  "GPL 2.0"
  :version "0.0.1"
  :depends-on (#:uiop
               #:alexandria
               #:cl-ansi-text
               #:cl-colors2
               #:terminfo
               #:adopt
               #:xkbcommon
               #:iterate
               #:atomics
               #:fset
               #:bordeaux-threads
               #:float-features
               #:cl-interactive
               #:closer-mop
               #:trivial-garbage
               #:cffi)
  :in-order-to ((test-op (test-op mahogany-test)))
  :pathname #p"lisp/"
  :components ((:file "log")
               (:file "util")
               (:file "system" :depends-on ("util" "config" "log"))
               (:module config
                :components ((:file "config-system")))
               (:module ring-list
                :components ((:file "ring-list")))
               (:module interfaces
                :components ((:file "view-interface")))
               (:module theme
                :components ((:file "theme")))
               (:module draw
                :serial t
                :components ((:file "package")
                             (:file "cairo")
                             (:file "draw")))
               (:module heart
                :depends-on ("interfaces" "theme" "draw" "util" "log")
                :components ((:file "package")
                             (:file "wl-bindings" :depends-on ("package"))
                             (:file "wlr-bindings" :depends-on ("wl-bindings"))
                             (:file "hrt-libs" :depends-on ("package"))
                             (:file "hrt-bindings" :depends-on ("wlr-bindings"))
                             (:file "callback" :depends-on ("package"))
                             (:file "cffi-util" :depends-on ("package"))
                             (:file "hrt-debug" :depends-on ("hrt-bindings")
                              :if-feature :hrt-debug)
                             (:file "message"
                              :depends-on ("cffi-util" "hrt-bindings" "output"))
                             (:file "output"
                              :depends-on ("cffi-util" "hrt-bindings"))
                             (:file "canvas"
                              :depends-on ("cffi-util" "hrt-bindings" "output" "callback"))
                             (:file "idle"
                              :depends-on ("hrt-bindings" "callback"))
                             (:file "subprocess"
                              :depends-on ("cffi-util" "hrt-bindings" "callback"))
                             (:file "view"
                              :depends-on ("cffi-util" "hrt-bindings"))
                             (:file "scene-group"
                              :depends-on ("cffi-util" "hrt-bindings" "output"))
                             (:file "border-box"
                              :depends-on ("cffi-util" "hrt-bindings"))
                             (:file "seat"
                              :depends-on ("package"))
                             (:file "server"
                              :depends-on ("package" "hrt-bindings" "callback"))
                             (:file "layer-shell")
                             (:file "transaction" :depends-on ("server"))))
               (:module keyboard
                :depends-on ("util")
                :serial t
                :components ((:file "package")
                             (:file "keytrans")
                             (:file "key")
                             ;; hashing tested on 64 bit SBCL,
                             ;; needs testing on 32 bit SBCL:
                             #+(and sbcl 64-bit)
                             (:file "key-hash")
                             (:file "kmap")))
               (:module tree
                :depends-on ("log" "util" "interfaces" "heart")
                :components ((:file "package")
                             (:file "tree-interface")
                             (:file "layer-shell"
                              :depends-on ("package"))
                             (:file "output-container"
                              :depends-on ("tree-interface" "layer-shell"))
                             (:file "tree-parent" :depends-on ("tree-interface"))
                             (:file "output-node"
                              :depends-on ("tree-interface" "output-container"))
                             (:file "frame" :depends-on ("tree-interface"))
                             (:file "view" :depends-on ("tree-interface"))))
               (:module input-methods
                :depends-on ("package")
                ;; It would be cool to figure out module loading
                ;; so that we could have a bunch of input methods
                ;; but not have them loaded until needed:
                :components ((:file "rofi-input-method")
                             #+(and sbcl linux)
                             (:file "foot-input-method")))
               (:file "package")
               (:file "command" :depends-on ("input-methods" "globals" "message"))
               (:file "objects" :depends-on ("package" "ring-list"))
               (:file "output-config" :depends-on ("heart" "package"))
               (:file "message" :depends-on ("heart" "config" "objects"))
               (:file "group" :depends-on ("objects" "heart" "globals"))
               (:file "state" :depends-on ("objects" "keyboard" "heart" "group" "output-config"))
               (:file "floating" :depends-on ("state" "group" "objects" "heart" "command" "message" "tree"))
               (:file "globals" :depends-on ("objects" "system"))
               (:file "kmap-modes"
                :depends-on ("objects" "globals" "keyboard" "input" "command"))
               (:file "events"
                :depends-on ("globals" "state" "objects" "heart" "util"))
               (:file "input"
                :depends-on ("state" "floating" "keyboard" "heart" "command" "message"))
               (:file "key-bindings"
                :depends-on ("kmap-modes" "state" "floating" "tree" "input" "command"))
               (:file "system-status"
                :depends-on ("state" "globals" "heart"))
               (:file "mode-line"
                :depends-on ("state" "command" "message" "globals" "tree" "system-status"))
               (:file "osd"
                :depends-on ("mode-line" "menu" "key-bindings" "command"))
               (:file "idle"
                :depends-on ("state" "command" "message" "globals"))
               (:file "menu"
                :depends-on ("state" "command" "message" "globals" "input" "tree"))
               (:file "launcher"
                :depends-on ("menu" "key-bindings" "command" "system"))
               (:file "themes"
                :depends-on ("mode-line" "menu" "osd" "message" "launcher" "tree" "globals"))
               (:file "screenshot"
                :depends-on ("themes" "menu" "launcher" "key-bindings" "system-status" "tree"))
               (:file "scratchpad"
                :depends-on ("state" "group" "launcher" "key-bindings" "command" "tree"))
               (:file "outputs"
                :depends-on ("state" "group" "floating" "launcher" "key-bindings" "command" "tree" "scratchpad"))
               (:file "directions"
                :depends-on ("state" "group" "outputs" "key-bindings" "command" "tree"))
               (:file "key-help"
                :depends-on ("state" "outputs" "key-bindings" "menu" "themes" "input" "heart" "draw"))
               (:file "xwayland" :depends-on ("system" "config" "log" "state" "heart" "command" "message"))
               (:file "default-bindings"
                :depends-on ("key-bindings" "floating" "launcher" "osd" "idle" "themes" "screenshot" "scratchpad" "outputs" "directions" "xwayland"))
               (:file "layouts"
                :depends-on ("group" "state" "launcher" "key-bindings" "default-bindings" "tree"))
               (:file "lid" :depends-on ("state" "idle" "command" "themes" "mode-line" "heart"))
               (:file "notifications"
                :depends-on ("state" "command" "themes" "menu" "launcher" "default-bindings" "mode-line" "heart" "draw"))
               (:file "wifi"
                :depends-on ("system-status" "menu" "launcher" "mode-line" "notifications" "command" "message"))
               (:file "main" :depends-on ("heart" "keyboard" "input" "package" "mode-line" "idle" "launcher" "osd" "themes" "screenshot" "scratchpad" "outputs" "default-bindings" "layouts" "xwayland" "lid" "notifications"))))

(asdf:defsystem #:mahogany/executable
  :build-operation program-op
  :entry-point "mahogany::main"
  :build-pathname "build/mahogany"
  :depends-on (#:mahogany))
