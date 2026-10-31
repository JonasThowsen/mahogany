(fiasco:define-test-package #:mahogany-tests/floating
  (:use #:mahogany))

(in-package #:mahogany-tests/floating)

(fiasco:deftest floating-rules-match-app-ids-and-dialogs ()
  (let ((rules '("com.gabm.satty" ("pavucontrol" :width 0.5 :height 800) :transient)))
    (is (equal "com.gabm.satty" (mahogany::%floating-rule "com.gabm.satty" nil rules)))
    ;; Case does not matter, the whole id does:
    (is (equal "com.gabm.satty" (mahogany::%floating-rule "Com.Gabm.Satty" nil rules)))
    (is (null (mahogany::%floating-rule "satty" nil rules)))
    (is (null (mahogany::%floating-rule "foot" nil rules)))
    (is (null (mahogany::%floating-rule nil nil rules)))
    ;; A dialog of another window floats whatever its id:
    (is (eq :transient (mahogany::%floating-rule "foot" t rules)))
    ;; A rule in a list carries a size:
    (let ((rule (mahogany::%floating-rule "pavucontrol" nil rules)))
      (is (equal '("pavucontrol" :width 0.5 :height 800) rule))
      (is (equal '(0.5 800) (multiple-value-list (mahogany::%floating-rule-size rule)))))
    (is (equal '(nil nil) (multiple-value-list (mahogany::%floating-rule-size "com.gabm.satty"))))))

(fiasco:deftest a-floating-window-is-centred-in-the-usable-area ()
  (let ((mahogany::*floating-size* '(0.5 0.5)))
    ;; Fractions of the area, centred in it (the area starts below a bar):
    (is (equal '(250 135 500 210)
               (multiple-value-list (mahogany::%floating-rectangle 0 30 1000 420 nil nil))))
    ;; Pixels, and no bigger than the area:
    (is (equal '(300 30 400 420)
               (multiple-value-list (mahogany::%floating-rectangle 0 30 1000 420 400 900))))))
