(fiasco:define-test-package #:mahogany-tests/slynk
  (:use #:mahogany))

(in-package #:mahogany-tests/slynk)

(fiasco:deftest slynk-port-file-follows-the-runtime-directory ()
  (let ((dir (uiop:getenv "XDG_RUNTIME_DIR")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "XDG_RUNTIME_DIR") "/run/user/42")
           (is (equal #p"/run/user/42/mahogany/slynk-port" (mahogany::%slynk-port-file)))
           (setf (uiop:getenv "XDG_RUNTIME_DIR") "")
           (is (null (mahogany::%slynk-port-file))))
      (setf (uiop:getenv "XDG_RUNTIME_DIR") (or dir "")))))
