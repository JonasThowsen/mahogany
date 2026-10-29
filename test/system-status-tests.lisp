(fiasco:define-test-package #:mahogany-tests/system-status
  (:use #:mahogany))

(in-package #:mahogany-tests/system-status)

(fiasco:deftest wpctl-volume-is-parsed-with-and-without-muted ()
  ;; Without [MUTED] wpctl's line ends right after the number:
  (is (equal '(:percent 30 :muted nil)
             (mahogany::%parse-wpctl-volume (format nil "Volume: 0.30~%"))))
  (is (equal '(:percent 30 :muted t)
             (mahogany::%parse-wpctl-volume (format nil "Volume: 0.30 [MUTED]~%"))))
  (is (equal '(:percent 30 :muted nil)
             (mahogany::%parse-wpctl-volume "Volume: 0.30")))
  (is (equal '(:percent 100 :muted nil)
             (mahogany::%parse-wpctl-volume (format nil "Volume: 1.00~%"))))
  (is (equal '(:percent 5 :muted nil)
             (mahogany::%parse-wpctl-volume (format nil "Volume: 0.05~%"))))
  (is (null (mahogany::%parse-wpctl-volume "No default sink")))
  (is (null (mahogany::%parse-wpctl-volume ""))))

(fiasco:deftest decimal-numbers-are-parsed-as-rationals ()
  (is (= 3/10 (mahogany::parse-number "0.30")))
  (is (= 1 (mahogany::parse-number "1")))
  (is (= 1 (mahogany::parse-number "1.00")))
  (is (= 1/20 (mahogany::parse-number "0.05"))))
