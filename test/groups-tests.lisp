(fiasco:define-test-package #:mahogany-tests/groups
  (:use #:mahogany))

(in-package #:mahogany-tests/groups)

;; Groups are per output. These tests build groups without a
;; compositor: a group is attached to an output by an entry in its
;; output map, which is all the bookkeeping looks at.

(defun make-group (name number home &optional attached)
  (let ((group (mahogany::%make-mahogany-group
                name number (cffi:null-pointer)
                (make-instance 'mahogany/tree:layer-container :hrt-layer nil))))
    (setf (mahogany::mahogany-group-home group) home)
    (when attached
      (setf (gethash home (mahogany::mahogany-group-output-map group)) :node))
    group))

(defun make-state (&rest groups)
  (let ((state (mahogany::make-mahogany-state)))
    (dolist (group groups state)
      (vector-push-extend group (mahogany::state-groups state)))))

(fiasco:deftest an-outputs-groups-are-its-own-by-number ()
  (let* ((a1 (make-group "1" 1 "DP-1" t))
         (a3 (make-group "3" 3 "DP-1" t))
         (a2 (make-group "2" 2 "DP-1" t))
         (b1 (make-group "1" 1 "eDP-1" t))
         (waiting (make-group "1" 1 "HDMI-1"))
         (scratch (make-group ".scratchpad" 0 :none))
         (state (make-state a1 a3 a2 b1 waiting scratch)))
    (is (equal (list a1 a2 a3) (mahogany::output-groups state "DP-1")))
    (is (equal (list b1) (mahogany::output-groups state "eDP-1")))
    ;; A group waiting for its output is not among an output's groups:
    (is (null (mahogany::output-groups state "HDMI-1")))
    (is (eq a2 (mahogany::%state-select-group state 2 "DP-1")))
    (is (null (mahogany::%state-select-group state 2 "eDP-1")))))

(fiasco:deftest group-numbers-are-free-per-output ()
  (let ((state (make-state (make-group "1" 1 "DP-1" t)
                           (make-group "2" 2 "DP-1" t)
                           (make-group "1" 1 "eDP-1" t)
                           (make-group ".scratchpad" 0 :none))))
    (is (= 3 (mahogany::%next-group-index state "DP-1")))
    (is (= 2 (mahogany::%next-group-index state "eDP-1")))
    (is (= 1 (mahogany::%next-group-index state "HDMI-1")))
    (is (equal "3" (mahogany::state-next-group-name state "DP-1")))))

(fiasco:deftest the-shown-group-is-per-output ()
  (let* ((a1 (make-group "1" 1 "DP-1" t))
         (b2 (make-group "2" 2 "eDP-1" t))
         (state (make-state a1 b2)))
    (setf (gethash "DP-1" (mahogany::state-output-groups state)) a1
          (gethash "eDP-1" (mahogany::state-output-groups state)) b2)
    (is (eq a1 (mahogany::state-output-group state "DP-1")))
    (is (eq b2 (mahogany::state-output-group state "eDP-1")))
    (is (null (mahogany::state-output-group state "HDMI-1")))
    (setf (mahogany::state-%current-group state) b2)
    (is (equal "eDP-1" (mahogany::state-current-home state)))
    ;; The current group's output is the one s-N acts on:
    (is (eq b2 (mahogany::%state-select-group state 2)))
    (is (null (mahogany::%state-select-group state 1)))))

(fiasco:deftest attached-and-waiting-groups ()
  (is (mahogany::group-attached-p (make-group "1" 1 "DP-1" t)))
  (is (not (mahogany::group-attached-p (make-group "1" 1 "DP-1"))))
  (is (eq :node (mahogany::group-output-node (make-group "1" 1 "DP-1" t))))
  (is (null (mahogany::group-output-node (make-group "1" 1 nil)))))
