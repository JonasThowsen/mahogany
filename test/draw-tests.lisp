(fiasco:define-test-package #:mahogany-tests/draw
  (:use #:mahogany/draw)
  (:local-nicknames (#:colors #:cl-colors2)))

(in-package #:mahogany-tests/draw)

(defun call-with-drawing (width height function)
  "Call FUNCTION with a cairo context on a new WIDTH x HEIGHT surface
and the surface, cairo and pango loaded."
  (load-libraries)
  (with-image-surface (surface width height)
    (with-context (cr surface)
      (funcall function cr surface))))

(defmacro with-drawing ((cr surface width height) &body body)
  `(call-with-drawing ,width ,height (lambda (,cr ,surface) ,@body)))

(fiasco:deftest clear-fills-everything ()
  (with-drawing (cr surface 8 8)
    (clear cr (colors:rgb 1 0 0))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 0 0)
      (is (= r 255)) (is (= g 0)) (is (= b 0)) (is (= a 255)))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 7 7)
      (is (= r 255)) (is (= g 0)) (is (= b 0)) (is (= a 255)))))

(fiasco:deftest fill-rectangle-stays-inside-its-bounds ()
  (with-drawing (cr surface 10 10)
    (clear cr '(0 0 0 0))
    (fill-rectangle cr 2 2 4 4 (colors:rgb 0 0 1))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 3 3)
      (is (= r 0)) (is (= g 0)) (is (= b 255)) (is (= a 255)))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 1 1)
      (declare (ignore r g b))
      (is (= a 0)))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 6 6)
      (declare (ignore r g b))
      (is (= a 0)))))

(fiasco:deftest set-color-takes-a-list-with-alpha ()
  (with-drawing (cr surface 4 4)
    (clear cr '(0 0 0 0))
    (fill-rectangle cr 0 0 4 4 '(0 1 0 0.5))
    (multiple-value-bind (r g b a) (image-surface-pixel surface 1 1)
      (is (= r 0)) (is (= g 255)) (is (= b 0))
      (is (<= 126 a 129)))))

(fiasco:deftest text-has-a-size-and-draws-pixels ()
  (with-drawing (cr surface 200 40)
    (clear cr (colors:rgb 0 0 0))
    (multiple-value-bind (width height) (text-size cr "Mahogany" :font "monospace 12")
      (is (< 0 width 200))
      (is (< 0 height 40)))
    (multiple-value-bind (width height)
        (draw-text cr "Mahogany" 2 2 :font "monospace 12" :color (colors:rgb 1 1 1))
      (is (plusp width))
      (is (plusp height))
      ;; Some pixel inside the text's box is lit:
      (is (loop for y from 2 below (+ 2 height)
                thereis (loop for x from 2 below (+ 2 width)
                              thereis (plusp (image-surface-pixel surface x y))))))))

(fiasco:deftest ellipsized-text-fits-its-width ()
  (with-drawing (cr surface 100 40)
    (with-layout (layout cr :text "A rather long line of text that cannot fit"
                            :font "monospace 12" :width 60 :ellipsize :end)
      (multiple-value-bind (width height) (layout-pixel-size layout)
        (is (<= width 60))
        (is (plusp height))))))
