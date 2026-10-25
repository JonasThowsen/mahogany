;; Configuration for slynk-cli's `lisp` command (see CLAUDE.md).
;; The dev shell (nix develop / direnv) provides sbcl, the Lisp libraries,
;; `lisp` and LD_LIBRARY_PATH for libheart.so.
;;
;; `lisp start` loads the mahogany system and then runs the compositor,
;; mahogany::main, in the image's main thread. `lisp eval --main FORM`
;; runs FORM there through hrt:run-in-main-thread, which the compositor's
;; event loop services.
(:system "mahogany"
 :init ("init-build-env.lisp")
 :main "mahogany::main"
 :main-thread-dispatcher "hrt:run-in-main-thread")
