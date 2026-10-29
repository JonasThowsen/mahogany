;;; Loaded by `lisp start` (.slynk-cli.sexp :init), after
;;; init-build-env.lisp: bring build/heart/libheart.so up to date before
;;; the system loads it. Lisp is compiled anew by every start, heart
;;; only by make or ninja, and an image started with a stale libheart
;;; refuses to start (server-init checks the struct size) or faults.
;;; Only `lisp start` loads this file: `make test` builds heart itself,
;;; and the tests run from run-tests.lisp must not rebuild the library
;;; under a compositor running from it.

(let ((build-dir (merge-pathnames "build/heart/" (uiop/os:getcwd))))
  (cond
    ((uiop:getenv "MAHOGANY_NO_HEART_BUILD"))
    ((not (probe-file (merge-pathnames "build.ninja" build-dir)))
     (format t "~&init-heart-build: no build/heart; run make once to build heart.~%"))
    (t
     (handler-case
         (multiple-value-bind (output error-output code)
             (uiop:run-program (list "ninja" "-C" (uiop:native-namestring build-dir))
                               :output :string :error-output :output
                               :ignore-error-status t)
           (declare (ignore error-output))
           (cond ((not (zerop code))
                  (format t "~&~%init-heart-build: WARNING: building heart failed ~
                             (ninja -C build/heart exited ~D). The compositor would ~
                             run with a stale build/heart/libheart.so.~%~A~%"
                          code output))
                 ((search "no work to do" output)
                  (format t "~&init-heart-build: heart is up to date.~%"))
                 (t
                  (format t "~&init-heart-build: heart rebuilt:~%~A~%" output))))
       (error (c)
         (format t "~&~%init-heart-build: WARNING: could not run ninja to build heart ~
                    (~A); build/heart/libheart.so may be stale.~%" c))))))
