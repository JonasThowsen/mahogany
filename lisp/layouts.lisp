(in-package #:mahogany)

;;; Tiling layouts. A group tiles by hand, the StumpWM way (:manual:
;;; split-frame-v, remove-current-frame ...), or by a layout that
;;; rebuilds the frame tree of an output whenever the windows on it
;;; change: master-stack, columns, rows, grid, dwindle, monocle, or
;;; one defined with define-layout. The layout is per group, set live
;;; with layout-menu / layout-next or from init.lisp.
;;;
;;; A layout is a function of the number of windows, the main ratio
;;; and the output's size, returning a spec:
;;;   :leaf                  a frame for one window
;;;   (:h RATIO LEFT RIGHT)  split, RATIO the left part's share (0 < r < 1)
;;;   (:v RATIO TOP BOTTOM)  split, RATIO the top part's share
;;; Windows fill the leaves in order, depth first; windows beyond the
;;; leaves stay hidden behind the last frame.

(defstruct (layout (:constructor %make-layout (name description function)))
  (name nil :type keyword)
  (description "" :type string)
  (function nil :type function))

(defglobal *layouts* (make-hash-table :test 'eq)
  "The layouts known, by name.")

(defglobal *layout-order* '()
  "The names of the layouts in the order they were defined, which
layout-next follows.")

(config:defconfig *default-layout* :manual
  keyword
  "The layout of new groups: :manual (tile by hand, as StumpWM), or an
automatic one: :master-stack, :columns, :rows, :grid, :dwindle,
:monocle, or one of your own (define-layout).")

(config:defconfig *group-layout-defaults* '()
  list
  "Layouts of groups by name, an alist such as ((\"DEFAULT\" . :master-stack)
(\"GROUP-2\" . :manual)), used when the group has not been given one.")

(config:defconfig *layout-main-ratio* 0.6
  (real (0) (1))
  "The share of the output the main window takes in layouts with one,
until the group's own ratio is changed with layout-main-ratio.")

(config:defconfig *layout-ratio-step* 0.05
  (real (0) (1))
  "How much layout-main-ratio-increase and -decrease change the ratio.")

(defmacro define-layout (name (n ratio width height) description &body body)
  "Define the layout NAME: BODY computes the spec for N windows, the
main RATIO and an output WIDTH x HEIGHT (all may be ignored).

  (define-layout :wide (n ratio width height) \"Main on top\"
    (if (< n 2) :leaf (list :v ratio :leaf (layout-columns (1- n)))))"
  `(progn
     (setf (gethash ,name *layouts*)
           (%make-layout ,name ,description
                         (lambda (,n ,ratio ,width ,height)
                           (declare (ignorable ,n ,ratio ,width ,height))
                           ,@body)))
     (unless (member ,name *layout-order*)
       (setf *layout-order* (append *layout-order* (list ,name))))
     ,name))

(defun find-layout (name)
  (or (gethash name *layouts*)
      (error "No layout named ~S. Known: ~{~(~A~)~^, ~}" name *layout-order*)))

;;; Spec helpers, for layouts of your own

(defun layout-columns (n &optional (specs nil))
  "A spec of N equal columns (or of SPECS side by side)."
  (let ((specs (or specs (make-list n :initial-element :leaf))))
    (if (<= (length specs) 1)
        (or (first specs) :leaf)
        (list :h (/ 1 (length specs)) (first specs) (layout-columns nil (rest specs))))))

(defun layout-rows (n &optional (specs nil))
  "A spec of N equal rows (or of SPECS stacked)."
  (let ((specs (or specs (make-list n :initial-element :leaf))))
    (if (<= (length specs) 1)
        (or (first specs) :leaf)
        (list :v (/ 1 (length specs)) (first specs) (layout-rows nil (rest specs))))))

;;; The group's layout and ratio

(defglobal *group-layouts* (make-hash-table :test 'eq :weakness :key)
  "group -> (layout-name . main-ratio), for groups given one.")

(defun group-layout (group)
  "The name of GROUP's layout."
  (or (car (gethash group *group-layouts*))
      (cdr (assoc (mahogany-group-name group) *group-layout-defaults* :test #'string=))
      *default-layout*))

(defun group-main-ratio (group)
  (or (cdr (gethash group *group-layouts*)) *layout-main-ratio*))

(defun (setf group-layout) (name group)
  (unless (eq name :manual) (find-layout name))
  (setf (gethash group *group-layouts*) (cons name (group-main-ratio group)))
  (layout-apply group)
  name)

(defun (setf group-main-ratio) (ratio group)
  (let ((ratio (max 0.1 (min 0.9 ratio))))
    (setf (gethash group *group-layouts*) (cons (group-layout group) ratio))
    (layout-apply group)
    ratio))

(defun group-auto-layout-p (group)
  (not (eq (group-layout group) :manual)))

;;; Building the tree

(defvar *in-layout* nil
  "True while a layout is being applied, so the changes it makes to the
tree do not apply it again.")

(defun %hidden-views (group)
  (let ((views '()))
    (ring-list:foreach-item (view (mahogany-group-hidden-views group))
      (push view views))
    (nreverse views)))

(defun %node-leaves (node)
  "The leaves of NODE in tree order."
  (let ((leaves '()))
    (tree::foreach-leaf (leaf node) (push leaf leaves))
    (nreverse leaves)))

(defun %layout-build (frame spec)
  "Split FRAME as SPEC says; the leaves in order."
  (flet ((too-small-p (size ratio)
           (< (min (* size ratio) (* size (- 1 ratio))) 40)))
    (cond ((eq spec :leaf) (list frame))
          ((and (consp spec) (member (first spec) '(:h :v)))
           (destructuring-bind (kind ratio first-spec second-spec) spec
             (let ((ratio (float (max 0.05 (min 0.95 ratio)) 1d0)))
               (if (too-small-p (if (eq kind :h) (tree:frame-width frame) (tree:frame-height frame))
                                ratio)
                   (list frame)
                   (let ((new (let ((tree::*new-split-type* :binary))
                                (if (eq kind :h)
                                    (tree:split-frame-h frame :ratio (- 1 ratio) :direction :right)
                                    (tree:split-frame-v frame :ratio (- 1 ratio) :direction :bottom)))))
                     (append (%layout-build frame first-spec)
                             (%layout-build new second-spec)))))))
          (t (error "Bad layout spec ~S" spec)))))

(defun layout-apply (group &optional node)
  "Rebuild the frame tree of NODE (the output node the group focuses,
by default) for GROUP's layout: its windows there, and the hidden
ones, fill the layout's frames in order. Nothing happens for :manual
or under a fullscreen window."
  (let* ((name (group-layout group))
         (node (or node
                   (alexandria:when-let ((frame (mahogany-group-current-frame group)))
                     (tree:find-root-frame frame)))))
    (when (or (eq name :manual) *in-layout* (null node)
              (not (typep node 'tree:output-node))
              (tree::output-node-fullscreen node))
      (return-from layout-apply nil))
    (let* ((*in-layout* t)
           (state *compositor-state*)
           (seat (server-seat state))
           (layout (find-layout name))
           (hidden (mahogany-group-hidden-views group))
           (leaves (%node-leaves node))
           (shown (remove nil (mapcar #'tree:frame-surface leaves)))
           (views (append shown (set-difference (%hidden-views group) shown)))
           (current (mahogany-group-current-frame group))
           (current-here (and current (member current leaves)))
           (focused (and current-here (tree:frame-surface current)))
           (output (tree:output-container-output (tree:output-node-output node)))
           (first-leaf (first leaves)))
      (hrt:with-view-transaction ()
        ;; Let go of the frame about to be rebuilt, while it is whole:
        (when current-here
          (tree:unmark-frame-focused current seat))
        ;; One frame, every window hidden:
        (%maximize-frame group first-leaf)
        (alexandria:when-let ((view (tree:frame-surface first-leaf)))
          (setf (tree:frame-surface first-leaf) nil)
          (%add-hidden hidden view))
        ;; The layout's frames, and the windows into them:
        (multiple-value-bind (width height) (hrt:output-resolution output)
          (let* ((spec (funcall (layout-function layout) (length views)
                                (group-main-ratio group) width height))
                 (slots (%layout-build first-leaf spec))
                 (focused-slot (first slots)))
            (loop for view in views
                  for slot in slots
                  do (ring-list:remove-item hidden view)
                     (hrt:view-set-hidden view nil)
                     (setf (tree:frame-surface slot) view)
                     (when (eq view focused) (setf focused-slot slot)))
            (when (or current-here (null current))
              (setf (mahogany-group-current-frame group) focused-slot)
              (when (eq group (state-current-group state))
                (setf (state-%current-frame state) focused-slot)
                (tree:mark-frame-focused focused-slot seat))))))
      (hrt:dirty-view-transaction)
      t)))

(defun group-views-changed (group &optional node)
  "Called by the group when a window came, went or moved: apply an
automatic layout to the output node NODE."
  (when (and (not *in-layout*) (group-auto-layout-p group))
    (handler-case (layout-apply group node)
      (error (c)
        (log-string :error "Could not apply the layout ~S: ~A" (group-layout group) c)))))

;;; Commands

(defun layout-set (name &optional (group (state-current-group *compositor-state*)))
  "Give GROUP the layout NAME and apply it."
  (setf (group-layout group) name)
  (toast-message *compositor-state* (format nil "Layout: ~(~A~)" name))
  name)

(defun cycle-layout (&optional (step 1))
  "Switch the current group to the next layout (previous with a
negative STEP), :manual included."
  (let* ((names (cons :manual *layout-order*))
         (position (or (position (group-layout (state-current-group *compositor-state*)) names) 0)))
    (layout-set (nth (mod (+ position step) (length names)) names))))

(defcommand layout-next ()
  (:documentation "The next tiling layout for this group")
  (:method () (cycle-layout 1)))

(defcommand layout-previous ()
  (:documentation "The previous tiling layout for this group")
  (:method () (cycle-layout -1)))

(defcommand layout-manual ()
  (:documentation "Tile this group by hand, keeping the frames as they are")
  (:method () (layout-set :manual)))

(defcommand layout-main-ratio-increase ()
  (:documentation "Give the main window more room")
  (:method ()
    (let ((group (state-current-group *compositor-state*)))
      (setf (group-main-ratio group) (+ (group-main-ratio group) *layout-ratio-step*)))))

(defcommand layout-main-ratio-decrease ()
  (:documentation "Give the main window less room")
  (:method ()
    (let ((group (state-current-group *compositor-state*)))
      (setf (group-main-ratio group) (- (group-main-ratio group) *layout-ratio-step*)))))

(defcommand layout-apply-now ()
  (:documentation "Apply this group's layout again")
  (:method () (layout-apply (state-current-group *compositor-state*))))

(defcommand layout-menu ()
  (:documentation "Choose a tiling layout for this group")
  (:method () (launcher :layouts)))

(define-launcher-mode :layouts (:prompt "Layout" :description "Tiling layouts")
  :items (let ((current (group-layout (state-current-group *compositor-state*))))
           (cons (make-menu-item "manual" :data :manual
                                 :detail (if (eq current :manual) "current" "tile by hand, as StumpWM"))
                 (loop for name in *layout-order*
                       for layout = (gethash name *layouts*)
                       collect (make-menu-item (string-downcase name) :data name
                                               :detail (if (eq name current)
                                                           "current"
                                                           (layout-description layout))))))
  :action #'layout-set)

(define-keys *top-map*
  "s-l" #'layout-next
  "s-S-l" #'layout-menu
  "s-equal" #'layout-main-ratio-increase
  "s-minus" #'layout-main-ratio-decrease)

;;; The built-in layouts

(define-layout :master-stack (n ratio width height)
    "Main window left, the rest stacked right"
  (cond ((< n 2) :leaf)
        (t (list :h ratio :leaf (layout-rows (1- n))))))

(define-layout :master-stack-wide (n ratio width height)
    "Main window on top, the rest side by side below"
  (cond ((< n 2) :leaf)
        (t (list :v ratio :leaf (layout-columns (1- n))))))

(define-layout :columns (n ratio width height)
    "Side by side"
  (layout-columns (max 1 n)))

(define-layout :rows (n ratio width height)
    "Stacked"
  (layout-rows (max 1 n)))

(define-layout :grid (n ratio width height)
    "A grid"
  (if (< n 2)
      :leaf
      (let* ((columns (ceiling (sqrt n)))
             (rows (ceiling n columns)))
        ;; The columns take the windows in turn, the last ones shorter:
        (layout-columns nil
                        (loop for column below columns
                              for in-column = (- (min n (* (1+ column) rows)) (* column rows))
                              when (plusp in-column)
                                collect (layout-rows in-column))))))

(define-layout :dwindle (n ratio width height)
    "Each window halves the last one, spiralling"
  (labels ((spiral (n horizontal)
             (if (< n 2)
                 :leaf
                 (list (if horizontal :h :v) 1/2 :leaf (spiral (1- n) (not horizontal))))))
    (spiral n (>= width height))))

(define-layout :monocle (n ratio width height)
    "One window at a time, the others behind it (next-view)"
  :leaf)
