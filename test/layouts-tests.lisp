(fiasco:define-test-package #:mahogany-tests/layouts
  (:use #:mahogany))

(in-package #:mahogany-tests/layouts)

;; The layout functions are pure: a spec from the number of windows,
;; the main ratio and the output's size. Applying them needs a
;; running compositor, so only the specs are tested here.

(defun spec (name n &optional (ratio 0.6) (width 1280) (height 720))
  (funcall (mahogany::layout-function (mahogany::find-layout name)) n ratio width height))

(defun count-leaves (spec)
  (if (eq spec :leaf)
      1
      (+ (count-leaves (third spec)) (count-leaves (fourth spec)))))

(fiasco:deftest one-window-is-one-leaf ()
  (dolist (name '(:master-stack :master-stack-wide :columns :rows :grid :dwindle :monocle))
    (is (eq :leaf (spec name 1)))
    (is (eq :leaf (spec name 0)))))

(fiasco:deftest master-stack-gives-the-main-window-the-ratio ()
  (is (equal '(:h 0.6 :leaf :leaf) (spec :master-stack 2)))
  (is (equal '(:h 0.6 :leaf (:v 1/2 :leaf :leaf)) (spec :master-stack 3)))
  (is (equal '(:v 0.6 :leaf (:h 1/2 :leaf :leaf)) (spec :master-stack-wide 3))))

(fiasco:deftest layouts-have-a-leaf-per-window ()
  (loop for n from 1 to 7
        do (dolist (name '(:master-stack :master-stack-wide :columns :rows :grid :dwindle))
             (is (= n (count-leaves (spec name n)))))))

(fiasco:deftest monocle-shows-one ()
  (is (eq :leaf (spec :monocle 5))))

(fiasco:deftest dwindle-starts-along-the-long-side ()
  (is (eq :h (first (spec :dwindle 2 0.6 1280 720))))
  (is (eq :v (first (spec :dwindle 2 0.6 720 1280)))))

(fiasco:deftest grid-is-columns-of-rows ()
  (is (equal '(:h 1/2 (:v 1/2 :leaf :leaf) (:v 1/2 :leaf :leaf)) (spec :grid 4)))
  ;; Five windows: three columns, the last one shorter
  (is (equal '(:h 1/3 (:v 1/2 :leaf :leaf) (:h 1/2 (:v 1/2 :leaf :leaf) :leaf)) (spec :grid 5))))

(fiasco:deftest define-layout-registers-and-cycles ()
  (let ((before (copy-list mahogany::*layout-order*)))
    (mahogany::define-layout :test-two (n ratio width height) "Two columns at most"
      (if (< n 2) :leaf (list :h ratio :leaf :leaf)))
    (is (member :test-two mahogany::*layout-order*))
    (is (equal '(:h 0.3 :leaf :leaf) (spec :test-two 4 0.3)))
    (remhash :test-two mahogany::*layouts*)
    (setf mahogany::*layout-order* before)))
