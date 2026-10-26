(fiasco:define-test-package #:mahogany-tests/directions
  (:use #:mahogany))

(in-package #:mahogany-tests/directions)

;; Finding the frame or output in a direction is geometry on
;; rectangles (x y width height), tested here without a compositor.

(defun nearest (direction from candidates)
  (destructuring-bind (x y w h) from
    (mahogany::%nearest-in-direction direction x y w h candidates
                                     (lambda (r) (values-list r)))))

(fiasco:deftest the-neighbour-in-a-direction ()
  (let ((left '(0 0 640 720))
        (right '(640 0 640 720)))
    (is (equal right (nearest :right left (list left right))))
    (is (equal left (nearest :left right (list left right))))
    (is (null (nearest :left left (list left right))))
    (is (null (nearest :up left (list left right))))))

(fiasco:deftest the-nearest-wins-then-the-one-straight-ahead ()
  (let ((from '(0 0 400 300))
        (near-top '(400 0 400 200))
        (near-bottom '(400 200 400 200))
        (far '(800 0 400 400)))
    (is (equal near-top (nearest :right from (list far near-bottom near-top))))
    ;; From the lower half, the lower neighbour is straight ahead:
    (is (equal near-bottom (nearest :right '(0 250 400 100) (list far near-top near-bottom))))))

(fiasco:deftest a-pixel-of-tolerance-and-no-false-neighbours ()
  (let ((from '(0 0 640 720)))
    ;; A border puts the neighbour a pixel over or short:
    (is (equal '(641 0 640 720) (nearest :right from '((641 0 640 720)))))
    (is (equal '(639 0 640 720) (nearest :right from '((639 0 640 720)))))
    ;; Overlapping rectangles are not neighbours:
    (is (null (nearest :right from '((300 0 640 720)))))))

(fiasco:deftest outputs-beside-each-other-are-neighbours-too ()
  ;; A laptop screen to the right of an external one, lower and smaller:
  (let ((external '(0 0 2560 1440))
        (laptop '(2560 440 1600 1000)))
    (is (equal laptop (nearest :right external (list laptop))))
    (is (equal external (nearest :left laptop (list external))))
    (is (null (nearest :down external (list laptop))))))

(fiasco:deftest key-help-columns-split-evenly ()
  (is (equal '((1 2 3) (4 5 6) (7)) (mahogany::%key-help-columns '(1 2 3 4 5 6 7) 3)))
  (is (equal '((1 2)) (mahogany::%key-help-columns '(1 2) 5)))
  (is (null (mahogany::%key-help-columns '() 5))))
