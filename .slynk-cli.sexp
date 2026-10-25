;; Configuration for slynk-cli's `lisp` command (see CLAUDE.md).
;; The dev shell (nix develop / direnv) provides sbcl, the Lisp libraries,
;; Slynk and LD_LIBRARY_PATH for libheart.so.
(:system "mahogany"
 :init ("init-build-env.lisp"))
