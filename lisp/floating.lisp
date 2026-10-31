(in-package #:mahogany)

;;; Floating windows: a window shown over the tiled frames of its
;;; group's output, in a frame of its own (tree:floating-frame) in the
;;; group's floating layer, above the tiled one. A new window floats
;;; when *floating-rules* say so (a screenshot editor, a mixer, a
;;; dialog of another window); float-toggle (s-v) floats the focused
;;; window or tiles it again, float-focus-toggle (s-S-v) moves the
;;; focus between the floating windows and the tiled frames. Floating
;;; windows go with their group: hidden with it, shown with it, and
;;; along to another group when moved there.

(config:defconfig *floating-rules*
    '("com.gabm.satty" "swappy" "pavucontrol" "org.pulseaudio.pavucontrol"
      "nm-connection-editor" "blueman-manager" :transient)
  list
  "Which new windows float, and how big: a list of rules, each an
application id (a string, compared whole, case ignored: \"pavucontrol\",
\"com.gabm.satty\"), :transient for the dialogs of other windows, or a
function of the view returning true; a rule inside a list, as
(\"com.gabm.satty\" :width 0.9 :height 0.9), gives the window's size
as fractions of the output's usable area (0 to 1) or in pixels.
Others get *floating-size*.")

(config:defconfig *floating-size* '(0.6 0.6)
  list
  "The width and height of a floating window that has no size of its
own in *floating-rules*: fractions of the output's usable area (0 to
1), or pixels above 1.")

;;; Rules

(defun %floating-rule (app-id transient rules)
  "The first rule in RULES for a window with APP-ID (a string or NIL)
that is TRANSIENT or not, functions aside: the rule itself, or NIL."
  (flet ((matches (spec)
           (cond ((stringp spec) (and app-id (string-equal spec app-id)))
                 ((eq spec :transient) transient))))
    (find-if (lambda (rule)
               (cond ((functionp rule) nil)
                     ((consp rule) (matches (first rule)))
                     (t (matches rule))))
             rules)))

(defun %floating-rule-size (rule)
  "The :width and :height a rule asks for, each or NIL."
  (if (consp rule)
      (values (getf (rest rule) :width) (getf (rest rule) :height))
      (values nil nil)))

(defun view-floats-p (view)
  "The rule in *floating-rules* by which VIEW, a new window, floats, or
NIL for a window that is tiled."
  (or (%floating-rule (hrt:view-app-id view) (hrt:view-transient-p view) *floating-rules*)
      (find-if (lambda (rule) (and (functionp rule) (funcall rule view)))
               *floating-rules*)))

;;; Geometry

(defun %floating-rectangle (area-x area-y area-width area-height width height)
  "Where a floating window of WIDTH x HEIGHT (fractions of the area, or
pixels above 1, each or NIL for *floating-size*) goes in the area:
centred, and no bigger than the area. Returns x y width height."
  (flet ((size (spec whole default)
           (let ((spec (or spec default)))
             (max 1 (min whole (if (<= spec 1) (round (* spec whole)) (round spec)))))))
    (let ((w (size width area-width (first *floating-size*)))
          (h (size height area-height (second *floating-size*))))
      (values (+ area-x (floor (- area-width w) 2))
              (+ area-y (floor (- area-height h) 2))
              w h))))

(defun %floating-frame-inset ()
  "What a floating frame adds around its window: the border, and the
half gap every frame keeps."
  (+ tree:*frame-border-width* (floor tree:*window-gap* 2)))

;;; The group's floating frames

(defun %leaf-in-tree-p (frame node)
  (tree::foreach-leaf (leaf node)
    (when (eq leaf frame)
      (return-from %leaf-in-tree-p t)))
  nil)

(defun %group-tiled-frame (group)
  "The tiled frame GROUP's keys act on: the current frame unless that
floats, then the tiled frame focused last while it is in the tree,
else the tree's focused or first leaf. NIL for a group without an output."
  (let ((current (mahogany-group-current-frame group))
        (node (group-output-node group)))
    (cond ((and current (not (typep current 'tree:floating-frame)))
           current)
          ((null node) nil)
          ((let ((last (mahogany-group-tiled-frame group)))
             (and last (%leaf-in-tree-p last node) last)))
          (t (or (tree:find-focused-frame node)
                 (tree:find-first-leaf node))))))

(defun group-floating-frame-at (group x y)
  "The floating frame of GROUP under the layout point X Y, the one
focused last first, or NIL."
  (find-if (lambda (frame) (tree:in-frame-p frame x y))
           (mahogany-group-floating-frames group)))

(defun %destroy-floating-frame (group frame)
  "Take FRAME, a floating frame of GROUP, down: its window is left in
no frame. When it had the focus, the tiled frame focused last becomes
the group's current frame (the caller focuses it)."
  (let ((seat (server-seat *compositor-state*)))
    (setf (mahogany-group-floating-frames group)
          (remove frame (mahogany-group-floating-frames group)))
    (when (eq (mahogany-group-current-frame group) frame)
      (tree:unmark-frame-focused frame seat)
      (setf (mahogany-group-current-frame group) nil)
      (setf (mahogany-group-current-frame group) (%group-tiled-frame group)))
    (setf (tree:frame-surface frame) nil)
    (tree:cleanup-frame frame)))

(defun group-float-view (group view &key width height x y (focus t))
  "Show VIEW, a window of GROUP, floating over the tiled frames of
GROUP's output, WIDTH x HEIGHT (fractions of the usable area or pixels;
*floating-size* by default) at X Y, or centred. Out of its tiled frame
or from behind the others, as the case may be; the frame it leaves
shows a hidden window if there is one. Focused unless FOCUS is NIL.
Returns the floating frame, or NIL for a group with no output."
  (declare (type mahogany-group group)
           (type hrt:view view))
  (let ((node (group-output-node group))
        (frame (hrt::view-container view)))
    (when (null node)
      (return-from group-float-view nil))
    (when (typep frame 'tree:floating-frame)
      (return-from group-float-view frame))
    (cond ((typep frame 'tree:output-node)
           (error 'mahogany/util:invalid-operation
                  :text "A fullscreen window cannot float"))
          ((typep frame 'tree:view-frame)
           (setf (tree:frame-surface frame) nil)
           (%fill-frame-from-hidden group frame))
          (t
           (ring-list:remove-item (mahogany-group-hidden-views group) view)
           (hrt:view-set-hidden view nil)))
    (let* ((output (tree:output-container-output (tree:output-node-output node)))
           (layer (mahogany-group-floating-container group))
           (inset (%floating-frame-inset)))
      (multiple-value-bind (fx fy fw fh)
          (multiple-value-call #'%floating-rectangle
            (hrt:output-usable-area output) width height)
        (let ((floating (make-instance 'tree:floating-frame
                                       :x (- (or x fx) inset) :y (- (or y fy) inset)
                                       :width (+ fw (* 2 inset)) :height (+ fh (* 2 inset))
                                       :parent node :layer layer)))
          (setf (tree::%frame-next floating) floating
                (tree::%frame-prev floating) floating)
          (hrt:scene-layer-add-view (tree:layer-container-layer layer) view)
          (setf (tree:frame-surface floating) view)
          (push floating (mahogany-group-floating-frames group))
          ;; The tiles close up behind it:
          (group-views-changed group node)
          (when focus
            (group-focus-frame group floating (server-seat *compositor-state*)))
          floating)))))

(defun group-unfloat-view (group view)
  "Put VIEW, a floating window of GROUP, back among the tiled windows:
into the tiled frame focused last, what that showed going behind it.
Returns that frame, or NIL when VIEW was not floating."
  (declare (type mahogany-group group)
           (type hrt:view view))
  (let ((frame (hrt::view-container view)))
    (unless (typep frame 'tree:floating-frame)
      (return-from group-unfloat-view nil))
    (%destroy-floating-frame group frame)
    (let ((target (%group-tiled-frame group)))
      (hrt:scene-layer-add-view
       (tree:layer-container-layer (mahogany-group-tiled-container group)) view)
      (alexandria:when-let ((shown (tree:frame-surface target)))
        (%add-hidden (mahogany-group-hidden-views group) shown))
      (%swap-view-into-frame group target view)
      (group-focus-frame group target (server-seat *compositor-state*))
      (group-views-changed group (tree:find-root-frame target))
      target)))

;;; Commands

(defun %focused-window ()
  "The focused window, or an error."
  (let* ((frame (state-current-frame *compositor-state*))
         (view (and (typep frame 'tree:frame) (tree:frame-surface frame))))
    (unless (typep view 'hrt:view)
      (error 'mahogany/util:invalid-operation :text "No window has the focus"))
    view))

(defun toggle-floating (&optional (view (%focused-window)))
  "Float VIEW (the focused window), or tile it again when it floats.
Returns VIEW."
  (let* ((state *compositor-state*)
         (group (%find-view-in-groups view (state-groups state))))
    (unless group
      (error 'mahogany/util:invalid-operation :text "The window has no group"))
    (hrt:with-view-transaction ()
      (if (typep (hrt::view-container view) 'tree:floating-frame)
          (group-unfloat-view group view)
          (group-float-view group view)))
    (when (eq group (state-current-group state))
      (%cur-frame-set-from-group state group))
    (hrt:dirty-view-transaction)
    (mode-line-update)
    view))

(defun toggle-floating-focus ()
  "Move the focus from the tiled frames to the floating window focused
last, or back to the tiled frame focused last. Returns the frame."
  (let* ((state *compositor-state*)
         (group (state-current-group state))
         (frame (state-current-frame state))
         (target (if (typep frame 'tree:floating-frame)
                     (%group-tiled-frame group)
                     (first (mahogany-group-floating-frames group)))))
    (unless target
      (error 'mahogany/util:invalid-operation :text "No floating window"))
    (state-focus-frame state target (server-seat state))
    target))

(defcommand float-toggle ()
  (:documentation "Float the focused window, or tile it again")
  (:method () (toggle-floating)))

(defcommand float-focus-toggle ()
  (:documentation "Focus the floating window, or the tiled frames again")
  (:method () (toggle-floating-focus)))
