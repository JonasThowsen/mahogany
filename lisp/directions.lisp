(in-package #:mahogany)

;;; Focus and windows by direction, the way niri, Hyprland and i3 move
;;; them: the frame to the left, right, above or below the focused one,
;;; on this output or on the one beside it, the focused window into
;;; that frame, and the outputs themselves by direction. Frames are
;;; in layout coordinates, every output's tree in the same space, so
;;; the frame to the right of the rightmost frame on one output is the
;;; leftmost on the output to the right.

(deftype direction () '(member :left :right :up :down))

(defun %shown-leaf-frames ()
  "Every leaf frame shown: those of the group each output shows."
  (let ((leaves '()))
    (loop for group being the hash-values of (state-output-groups *compositor-state*)
          do (alexandria:when-let ((node (group-output-node group)))
               (tree::foreach-leaf (leaf node) (push leaf leaves))))
    leaves))

(defun %rectangle-in-direction (direction x y width height cx cy cwidth cheight)
  "Whether the rectangle at CX CY lies in DIRECTION from the one at X Y,
and how far: (values distance offset), or NIL. The offset ranks
candidates at the same distance: those overlapping this rectangle on
the other axis come first, then by how far their center is from this
one's center."
  (flet ((offset (other other-size cother cother-size)
           ;; OTHER..OTHER+SIZE is this rectangle on the other axis,
           ;; COTHER the candidate's:
           (+ (abs (- (+ cother (/ cother-size 2))
                      (+ other (/ other-size 2))))
              (if (and (< cother (+ other other-size))
                       (> (+ cother cother-size) other))
                  0
                  100000))))
    ;; A pixel of tolerance: borders and rounding put neighbours a
    ;; pixel apart or over.
    (ecase direction
      (:right (when (>= cx (+ x width -1))
                (values (max 0 (- cx (+ x width))) (offset y height cy cheight))))
      (:left (when (<= (+ cx cwidth) (1+ x))
               (values (max 0 (- x (+ cx cwidth))) (offset y height cy cheight))))
      (:down (when (>= cy (+ y height -1))
               (values (max 0 (- cy (+ y height))) (offset x width cx cwidth))))
      (:up (when (<= (+ cy cheight) (1+ y))
             (values (max 0 (- y (+ cy cheight))) (offset x width cx cwidth)))))))

(defun %nearest-in-direction (direction x y width height candidates rectangle)
  "The candidate nearest in DIRECTION from the rectangle X Y WIDTH
HEIGHT; RECTANGLE gives a candidate's (values x y width height). The
nearest along the direction wins, and among those side by side the
one straight ahead."
  (let ((best nil) (best-distance nil) (best-offset nil))
    (dolist (candidate candidates best)
      (multiple-value-bind (cx cy cwidth cheight) (funcall rectangle candidate)
        (multiple-value-bind (distance offset)
            (%rectangle-in-direction direction x y width height cx cy cwidth cheight)
          (when (and distance
                     (or (null best)
                         (< distance best-distance)
                         (and (= distance best-distance) (< offset best-offset))))
            (setf best candidate best-distance distance best-offset offset)))))))

(defun frame-in-direction (direction &optional (frame (state-current-frame *compositor-state*)))
  "The leaf frame nearest in DIRECTION from FRAME among the frames shown,
on any output, or NIL at the edge."
  (declare (type direction direction))
  (when (typep frame 'tree:frame)
    (%nearest-in-direction direction
                           (tree:frame-x frame) (tree:frame-y frame)
                           (tree:frame-width frame) (tree:frame-height frame)
                           (remove frame (%shown-leaf-frames))
                           (lambda (f)
                             (values (tree:frame-x f) (tree:frame-y f)
                                     (tree:frame-width f) (tree:frame-height f))))))

(defun %output-rectangle (output)
  "OUTPUT's place in the layout: (values x y width height), in layout
coordinates (pixels divided by the scale)."
  (multiple-value-bind (x y) (hrt:output-position output)
    (multiple-value-bind (width height) (hrt:output-logical-size output)
      (values x y width height))))

(defun output-in-direction (direction &optional (output (current-output)))
  "The output nearest in DIRECTION from OUTPUT, or NIL."
  (declare (type direction direction))
  (when output
    (multiple-value-bind (x y width height) (%output-rectangle output)
      (%nearest-in-direction direction x y width height
                             (remove output (outputs) :test #'hrt:output=)
                             #'%output-rectangle))))

(defun focus-in-direction (direction)
  "Focus the frame in DIRECTION; returns it, or NIL at the edge."
  (alexandria:when-let ((frame (frame-in-direction direction)))
    (state-focus-frame *compositor-state* frame (server-seat *compositor-state*))
    frame))

(defun move-window-in-direction (direction)
  "Move the focused window into the frame in DIRECTION and follow it:
exchanged with what that frame shows on this output, or, on the output
beside it, into the group shown there, what that frame showed going
behind it. A window moved out of its frame leaves it to a hidden
window, if there is one. Returns the frame, or NIL at the edge."
  (let* ((state *compositor-state*)
         (source (state-current-frame state))
         (target (frame-in-direction direction source)))
    (when target
      (let ((view (and (typep source 'tree:frame) (tree:frame-surface source))))
        (unless (typep view 'hrt:view)
          (error 'mahogany/util:invalid-operation :text "No window to move"))
        (move-view-to-frame view target :swap t)
        target))))

(defun focus-output-in-direction (direction)
  "Focus the output in DIRECTION; returns its frame, or NIL."
  (alexandria:when-let ((output (output-in-direction direction)))
    (focus-output output)))

(defun move-window-to-output-in-direction (direction)
  "Move the focused window to the output in DIRECTION and follow it."
  (alexandria:when-let ((output (output-in-direction direction)))
    (move-window-to-output output)))

;;; Fullscreen

(defun %fullscreen-view (group)
  "The view fullscreen on the current output, or NIL."
  (find-if #'hrt:view-fullscreen-p (mahogany-group-views group)))

(defun toggle-fullscreen ()
  "Make the focused window fullscreen, or take it back out."
  (let* ((state *compositor-state*)
         (group (state-current-group state))
         (frame (state-current-frame state))
         (view (if (typep frame 'tree:frame)
                   (tree:frame-surface frame)
                   (%fullscreen-view group))))
    (unless (typep view 'hrt:view)
      (error 'mahogany/util:invalid-operation :text "No window to make fullscreen"))
    (mahogany-state-view-fullscreen state view (current-output)
                                    (not (hrt:view-fullscreen-p view)))))

;;; Commands

(macrolet ((define-direction-commands (&rest specs)
             `(progn
                ,@(loop for (prefix function doc) in specs
                        append (loop for direction in '(:left :right :up :down)
                                     collect `(defcommand ,(alexandria:symbolicate prefix (symbol-name direction)) ()
                                                (:documentation ,(format nil doc (string-downcase direction)))
                                                (:method () (,function ,direction))))))))
  (define-direction-commands
    ("FOCUS-" focus-in-direction "Focus the frame to the ~A")
    ("MOVE-WINDOW-" move-window-in-direction "Move the window to the frame to the ~A")
    ("FOCUS-OUTPUT-" focus-output-in-direction "Focus the output to the ~A")
    ("MOVE-WINDOW-TO-OUTPUT-" move-window-to-output-in-direction "Move the window to the output to the ~A")))

(defcommand fullscreen-toggle ()
  (:documentation "Make the window fullscreen, or take it back out")
  (:method () (toggle-fullscreen)))
