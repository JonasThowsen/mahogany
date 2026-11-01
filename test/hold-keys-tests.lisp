(fiasco:define-test-package #:mahogany-tests/hold-keys
  (:use #:mahogany))

(in-package #:mahogany-tests/hold-keys)

(defmacro with-clean-hold-keys (&body body)
  "BODY with no hold keys defined or held; the globals (defglobal, so
not bindable) are put back after."
  (alexandria:with-gensyms (keys held)
    `(let ((,keys mahogany::*hold-keys*)
           (,held mahogany::*held-keys*))
       (setf mahogany::*hold-keys* '()
             mahogany::*held-keys* '())
       (unwind-protect (progn ,@body)
         (setf mahogany::*hold-keys* ,keys
               mahogany::*held-keys* ,held)))))

(fiasco:deftest a-hold-key-runs-press-then-release-by-keycode ()
  (with-clean-hold-keys
    (let ((events '()))
      (mahogany::define-hold-key "s-z"
                                 (lambda () (push :press events))
                                 (lambda () (push :release events)))
      ;; Pressed with Super: the press runs, the key is swallowed.
      (is (mahogany::%hold-key-press (mahogany:kbd "s-z") 44))
      (is (equal '(:press) events))
      ;; A repeat of the key still down runs nothing, and is swallowed.
      (is (mahogany::%hold-key-press (mahogany:kbd "s-z") 44))
      (is (equal '(:press) events))
      ;; Another key is not a hold key.
      (is (null (mahogany::%hold-key-press (mahogany:kbd "s-x") 45)))
      ;; Let go after Super came up: matched by the keycode alone.
      (is (mahogany::%hold-key-release 44))
      (is (equal '(:release :press) events))
      ;; Not held any more: the next release is nobody's.
      (is (null (mahogany::%hold-key-release 44)))
      (is (null mahogany::*held-keys*)))))

(fiasco:deftest hold-key-actions-may-be-nil-and-redefined ()
  (with-clean-hold-keys
    (mahogany::define-hold-key "s-z" nil nil)
    (is (= 1 (length mahogany::*hold-keys*)))
    (mahogany::define-hold-key (mahogany:kbd "s-z") nil nil)
    (is (= 1 (length mahogany::*hold-keys*)))
    (is (mahogany::%hold-key-press (mahogany:kbd "s-z") 44))
    (is (mahogany::%hold-key-release 44))
    (mahogany::undefine-hold-key "s-z")
    (is (null mahogany::*hold-keys*))
    (is (null (mahogany::%hold-key-press (mahogany:kbd "s-z") 44)))))

(fiasco:deftest a-failing-hold-action-is-logged-not-raised ()
  (with-clean-hold-keys
    (mahogany::define-hold-key "s-z" (lambda () (error "boom")) nil)
    (is (mahogany::%hold-key-press (mahogany:kbd "s-z") 44))
    (is (mahogany::%hold-key-release 44))))
