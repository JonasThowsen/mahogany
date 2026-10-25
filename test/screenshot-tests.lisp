(fiasco:define-test-package #:mahogany-tests/screenshot
  (:use #:mahogany))

(in-package #:mahogany-tests/screenshot)

(fiasco:deftest grim-geometry-is-rounded-layout-pixels ()
  (is (string= "10,20 300x200" (mahogany::grim-geometry 10 20 300 200)))
  (is (string= "10,21 300x200" (mahogany::grim-geometry 10.2 20.6 299.6 200))))

(fiasco:deftest screenshot-file-name-is-dated-and-in-the-directory ()
  (let ((mahogany::*screenshot-directory* "/tmp/shots"))
    (let ((file (mahogany::screenshot-file-name
                 (encode-universal-time 5 4 3 2 1 2026))))
      (is (string= "screenshot-2026-01-02-030405.png" (file-namestring file)))
      (is (equal '(:absolute "tmp" "shots") (pathname-directory file))))))
