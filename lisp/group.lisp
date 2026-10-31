(in-package #:mahogany)

;; In layouts.lisp and floating.lisp, which load after this file:
(declaim (ftype function group-views-changed group-auto-layout-p layout-apply
                view-floats-p group-float-view
                %destroy-floating-frame %group-tiled-frame))

(defun make-mahogany-group (name number hrt-server)
  (let* ((hrt-group (hrt:server-group-create hrt-server))
         (tiled-layer (tree:make-layer-container hrt-group))
         ;; Made after the tiled layer, so it is drawn above it:
         (floating-layer (tree:make-layer-container hrt-group))
         (group (%make-mahogany-group name number hrt-group tiled-layer)))
    (hrt:hrt-scene-group-set-enabled hrt-group nil)
    (setf (mahogany-group-floating-container group) floating-layer)
    (log-string :debug "Created group ~A" name)
    group))

(defun destroy-mahogany-group (group scene-tree seat)
  (group-suspend group seat)
  (with-accessors ((views mahogany-group-views)
                   (hrt-group mahogany-group-hrt-group)
                   (tiled-layer mahogany-group-tiled-container)
                   (group-name mahogany-group-name))
      group
    (when views
      (log-string :error "The following views are associated with a group that is being deleted. They will be orphaned:~%~4T ~S" views)
      (dolist (v views)
        (hrt:view-reparent v scene-tree)))
    (tree:destroy-layer-container tiled-layer)
    (alexandria:when-let ((floating (mahogany-group-floating-container group)))
      (tree:destroy-layer-container floating))
    (hrt:hrt-scene-group-destroy hrt-group)
    (log-string :debug "Destroyed group ~A" group-name)))

(defun %add-hidden (hidden-list view)
  (log-string :trace "Hiding view ~S" view)
  (ring-list:add-item hidden-list view)
  (hrt:view-set-hidden view t))

(defun %swap-next-hidden (hidden-list view)
  (let ((swapped (ring-list:swap-next hidden-list view)))
    (hrt:view-set-hidden view t)
    (hrt:view-set-hidden swapped nil)
    swapped))

(defun %swap-prev-hidden (hidden-list view)
  (let ((swapped (ring-list:swap-previous hidden-list view)))
    (hrt:view-set-hidden view t)
    (hrt:view-set-hidden swapped nil)
    swapped))

(defun %pop-hidden-item (hidden-list)
  (alexandria:when-let ((popped (ring-list:pop-item hidden-list)))
    (hrt:view-set-hidden popped nil)
    popped))

(defun group-unfocus (group seat)
  "Unfocus the group, but don't stop displaying it"
  (declare (type mahogany-group group))
  (with-accessors ((focused-frame mahogany-group-current-frame))
      group
    (when focused-frame
      (tree:unmark-frame-focused focused-frame seat))))

(defun group-focus (group seat)
  "Focus the group, but don't stop displaying it"
  (declare (type mahogany-group group))
  (with-accessors ((focused-frame mahogany-group-current-frame))
      group
    (when focused-frame
      (tree:mark-frame-focused focused-frame seat))))

(defun group-suspend (group seat)
  "Stop displaying the group"
  (declare (type mahogany-group group))
  (with-accessors ((hrt-group mahogany-group-hrt-group))
      group
    (log-string :debug "Suspending group ~A" (mahogany-group-name group))
    (group-unfocus group seat)
    (setf (mahogany-group-active-p group) nil)
    (hrt:hrt-scene-group-set-enabled hrt-group nil)))

(defun %first-hash-table-value (table)
  (declare (type hash-table table)
           (optimize (speed 3) (safety 0)))
  (with-hash-table-iterator (iter table)
    (multiple-value-bind (found key value) (iter)
      (declare (ignore found key))
      value)))

(defun group-show (group)
  "Start displaying the group, without focusing it: what the output it
belongs to shows while another output has the focus."
  (declare (type mahogany-group group))
  (unless (mahogany-group-active-p group)
    (log-string :debug "Showing group ~A" (mahogany-group-name group))
    (setf (mahogany-group-active-p group) t)
    (hrt:hrt-scene-group-set-enabled (mahogany-group-hrt-group group) t)))

(defun group-wakeup (group seat)
  "Start displaying the group and focus its frame"
  (declare (type mahogany-group group))
  (log-string :debug "Waking up group ~A" (mahogany-group-name group))
  (group-show group)
  (group-focus group seat))

(defun group-attached-p (group)
  "Whether GROUP has an output to be shown on."
  (plusp (hash-table-count (mahogany-group-output-map group))))

(defun group-output-node (group)
  "The output node of GROUP's frame tree: a group belongs to one
output. NIL while it waits for one."
  (%first-hash-table-value (mahogany-group-output-map group)))

(defun %fill-frame-from-hidden (group frame)
  "Show a hidden window of GROUP in FRAME when it is an empty frame."
  (when (and (typep frame 'tree:view-frame)
             (null (tree:frame-surface frame)))
    (alexandria:when-let ((view (%pop-hidden-item (mahogany-group-hidden-views group))))
      (%swap-view-into-frame group frame view))))

(defun group-move-view (source destination view)
  "Move VIEW from the group SOURCE to DESTINATION, where it is shown in
the current frame when that is empty, else kept hidden behind it."
  (declare (type mahogany-group destination source))
  (let ((dest-layer (mahogany-group-tiled-container destination))
        (hidden-list (mahogany-group-hidden-views destination))
        (floating (typep (hrt::view-container view) 'tree:floating-frame)))
    (group-remove-view source view)
    (tree:layer-container-transfer-view dest-layer view)
    (push view (mahogany-group-views destination))
    (when (hrt:view-mapped-p view)
      (cond
        ;; A floating window floats in its new group too, when that
        ;; has an output to float over:
        ((and floating (group-attached-p destination))
         (group-float-view destination view :focus nil))
        (t
         (%add-hidden hidden-list view)
         (%fill-frame-from-hidden destination (%group-tiled-frame destination))
         (group-views-changed destination))))))

(defun group-transfer-views (destination source)
  "Transfer the all views from the SOURCE group to the DESTINATION group"
  (declare (type mahogany-group destination source))
  (dolist (view (mahogany-group-views source))
    (group-move-view source destination view)))

(defun group-focus-frame (group frame seat)
  (with-accessors ((current-frame mahogany-group-current-frame)) group
    (when current-frame
      (group-unfocus-frame group current-frame seat))
    (tree:mark-frame-focused frame seat)
    (setf current-frame frame)
    (cond ((typep frame 'tree:floating-frame)
           ;; The one focused last comes first:
           (setf (mahogany-group-floating-frames group)
                 (cons frame (remove frame (mahogany-group-floating-frames group)))))
          ((typep frame 'tree:view-frame)
           (setf (mahogany-group-tiled-frame group) frame)))))

(defun group-unfocus-frame (group frame seat)
  (with-accessors ((current-frame mahogany-group-current-frame)) group
    (tree:unmark-frame-focused frame seat)
    (setf current-frame nil)))

(defun group-add-output (group output-container
                               &aux (output (tree::output-container-output output-container)))
  (declare (type tree:output-container output-container)
           (type mahogany-group group))
  (with-accessors ((output-map mahogany-group-output-map)
                   (tiled-container mahogany-group-tiled-container)
                   (current-frame mahogany-group-current-frame)
                   (hidden-views mahogany-group-hidden-views))
      group
    (let ((new-tree (tree:tree-output-add tiled-container output-container)))
      ;; The new tree covers the output; fit it to the usable area (the
      ;; mode-line's and the layer shell's reserved space, the gaps) now,
      ;; not at the next change of that area:
      (tree:reconfigure-node new-tree output)
      (setf (gethash (hrt:output-full-name output) output-map) new-tree)
      (when (not current-frame)
        (let ((first-leaf (tree:find-first-leaf new-tree)))
          (setf current-frame first-leaf)
          (alexandria:when-let ((spare (%pop-hidden-item hidden-views)))
            (setf (tree:frame-surface first-leaf) spare))))
      (log-string :trace "Group map: ~S" output-map)
      new-tree)))

(defun group-rearrange-output (group output)
  (declare (type mahogany-group group)
           (type hrt:output output))
  (let ((full-name (hrt:output-full-name output))
        (output-map (mahogany-group-output-map group)))
    (alexandria:when-let ((tree (gethash full-name output-map)))
      (tree:reconfigure-node tree output))))

(defun group-reconfigure-outputs (group outputs)
  (declare (type mahogany-group group))
  "Re-examine where the outputs are and adjust the trees that are associated with them
to match."
  (log-string :debug "Reconfiguring group ~S outputs"
              (mahogany-group-name group))
  (loop for output across outputs
        do (group-rearrange-output group (tree:output-container-output output))))

(defun %group-current-output-node (group)
  (alexandria:when-let ((cur-frame (mahogany-group-current-frame group)))
    (tree:find-root-frame cur-frame)))

(declaim (ftype (function (mahogany-group) (or null hrt:output)) group-current-output))
(defun group-current-output (group)
  "Return the output that contains the group's currently focused frame"
  (alexandria:when-let ((cur-output-node (%group-current-output-node group)))
    (tree:output-container-output (tree:output-node-output cur-output-node))))

(defun group-remove-output (group output-container seat
                            &aux (output (tree::output-container-output output-container)))
  (declare (type tree:output-container output-container)
           (type mahogany-group group))
  (with-accessors ((output-map mahogany-group-output-map)
                   (hidden-views mahogany-group-hidden-views)
                   (cur-frame mahogany-group-current-frame))
      group
    (let* ((output-name (hrt:output-full-name output))
           (tree (gethash output-name output-map)))
      (remhash output-name output-map)
      (when (equalp output (group-current-output group))
        (group-unfocus-frame group (mahogany-group-current-frame group) seat)
        (alexandria:when-let ((other-tree (%first-hash-table-value output-map)))
          (setf cur-frame (tree:find-first-leaf other-tree))))
      ;; The floating windows over this output go behind the tiled
      ;; ones, to come out tiled where the group goes:
      (dolist (frame (remove-if-not (lambda (f) (eq (tree:frame-parent f) tree))
                                    (mahogany-group-floating-frames group)))
        (let ((view (tree:frame-surface frame)))
          (%destroy-floating-frame group frame)
          (when view
            (%add-hidden hidden-views view))))
      (tree:remove-frame tree (lambda (x) (alexandria:when-let ((v (tree:frame-surface x)))
				                            (%add-hidden hidden-views v)))))))

(defun group-add-initialize-view (group view-ptr)
  (declare (type mahogany-group group)
           (type cffi:foreign-pointer view-ptr))
  (let* ((tiled-layer (mahogany-group-tiled-container group))
         (hrt-tiled-layer (tree:layer-container-layer tiled-layer))
         (view (hrt:view-init view-ptr)))
    (hrt:scene-layer-add-view hrt-tiled-layer view)
    (push view (mahogany-group-views group))
    ;; We need to send a configure event, so we might as well
    ;; guess the size of the window:
    (alexandria:if-let ((focused-frame (mahogany-group-current-frame group)))
      (etypecase focused-frame
        (tree:output-node
         (let ((focused-underneath (tree:find-focused-frame focused-frame)))
           (multiple-value-bind (w h)
               (tree::frame-view-dimensions focused-underneath)
           (set-dimensions view w h))))
        (tree:frame
         (multiple-value-bind (w h)
               (tree::frame-view-dimensions focused-frame)
         (set-dimensions view w h))))
      ;; There's no focused frame, we have no information:
      (set-dimensions view 0 0))
    view))

(defun group-map-view (group view)
  (declare (type mahogany-group group)
	   (type hrt:view view))
  (with-accessors ((views mahogany-group-views)
		   (outputs mahogany-group-output-map)
		   (hidden mahogany-group-hidden-views))
      group
    (when (mahogany-group-current-frame group)
      (if (view-floats-p view)
          ;; A window that floats, by the rules: over the tiled frames.
          (group-float-view group view)
          ;; Else into the tiled frame that has the focus, or had it last:
          (let ((current-frame (%group-tiled-frame group))
                (hrt-layer (tree:layer-container-layer (mahogany-group-tiled-container group))))
            (hrt:scene-layer-add-view hrt-layer view)
            (alexandria:when-let ((to-hide (tree:frame-surface current-frame)))
              (%add-hidden hidden to-hide))
            (%swap-view-into-frame group current-frame view)
            (unless (eq current-frame (mahogany-group-current-frame group))
              (group-focus-frame group current-frame (server-seat *compositor-state*)))
            (group-views-changed group (tree:find-root-frame current-frame)))))))

(defun group-unmap-view (group view)
  (declare (type mahogany-group group))
  (with-accessors ((view-list mahogany-group-views)
                   (output-map mahogany-group-output-map)
                   (hidden mahogany-group-hidden-views))
      group
    (log-string :trace "unmapping view ~S" view)
    (alexandria:if-let ((f (hrt::view-container view)))
      (hrt:with-view-transaction ()
        (etypecase f
          (tree:output-node
           (log-string :trace "unmapping fullscreen view ~S" view)
           (let ((to-replace (ring-list:peek-item hidden)))
             (cond
               ((and to-replace (hrt:view-fullscreen-p to-replace))
                (tree:set-fullscreen f (%pop-hidden-item hidden)))
               (t
                (%clear-fullscreen-state group f)
                ;; reset the current frame:
                (let ((to-focus (tree:find-focused-frame f)))
                  ;; Don't pull from the hidden list unless we land on an empty frame:
                  (when (and to-replace
                             (not (tree:frame-surface to-focus)))
                    (setf (tree:frame-surface to-focus) (%pop-hidden-item hidden)))
                  (setf (mahogany-group-current-frame group) to-focus))))))
          (tree:floating-frame
           (%destroy-floating-frame group f))
          (tree:view-frame
           (setf (tree:frame-surface f) nil)
           (when (> (ring-list:ring-list-size hidden) 0)
             (%swap-view-into-frame group f (%pop-hidden-item hidden)))
           (group-views-changed group (tree:find-root-frame f))))
        (hrt:dirty-view-transaction))
      (ring-list:remove-item hidden view))))

(defun group-remove-view (group view)
  (declare (type mahogany-group group))
  (with-accessors ((view-list mahogany-group-views)
                   (output-map mahogany-group-output-map)
                   (hidden mahogany-group-hidden-views)
                   (tiled-container mahogany-group-tiled-container))
      group
    (when (hrt:view-mapped-p view)
      ;; if the view is hidden, it won't be in a frame:
      (or
       (ring-list:remove-item hidden view)
       (alexandria:when-let ((f (hrt::view-container view)))
         (cond ((typep f 'tree:floating-frame)
                (%destroy-floating-frame group f))
               (t
                (setf (tree:frame-surface f) nil)
                (when (typep f 'tree:view-frame)
                  (group-views-changed group (tree:find-root-frame f))))))))
    (setf view-list (remove view view-list :test #'equalp))))

(defmethod tree:find-empty-frame ((group mahogany-group))
  (with-hash-table-iterator (iter (mahogany-group-output-map group))
    (tagbody
     :top (multiple-value-bind (found name frame) (iter)
            (declare (ignore name))
            (when found
              (alexandria:if-let ((view-frame (tree:find-empty-frame frame)))
                (return-from tree:find-empty-frame view-frame)
                (go :top)))))))

(defun %maximize-frame (group frame)
  "Maximize FRAME. Returns NIL if FRAME is already the topmost frame in its tree"
  (declare (type mahogany-group group))
  (when (tree:topmost-frame-p frame)
    (return-from %maximize-frame nil))
  (let ((topmost-frame (mahogany/tree:find-topmost-frame frame)))
    (flet ((hide-and-disable (view-frame)
             (alexandria:when-let ((view (tree:frame-surface view-frame)))
               (%add-hidden (mahogany-group-hidden-views group) view))))
      (tree:replace-frame topmost-frame frame #'hide-and-disable)))
  (hrt:dirty-view-transaction)
  t)

(defun group-maximize-current-frame (group)
  "Remove all of the splits in the current window tree and replace it
with the currently focused frame; when it is the only frame already,
apply the group's layout again, so the key toggles (a :manual layout
has nothing to go back to)."
  (declare (type mahogany-group group))
  (let ((current-frame (mahogany-group-current-frame group)))
    (unless current-frame
      (error 'mahogany/util:invalid-operation
             :text "No frame to maximize!"))
    (when (typep current-frame 'tree:floating-frame)
      (error 'mahogany/util:invalid-operation
             :text "The window floats; float-toggle (s-v) tiles it first"))
    (unless (%maximize-frame group current-frame)
      (cond ((group-auto-layout-p group)
             (layout-apply group))
            (t
             (error 'mahogany/util:invalid-operation
                    :text "Frame is already maximized, and the layout is manual"))))))

(defstruct (%hidden-view-info (:constructor %make-hidden-view-info (output frame)))
  (output nil :type tree:output-node :read-only t)
  (frame nil :type tree:view-frame :read-only t))

;; In order to swap between hidden views, we need to record which views are under
;; a fullscreen view so that we can remove the view from its frame if it gets placed
;; in a different one.
(defun %hide-views-under-fullscreen (group output-node &optional (add-fun #'ring-list:add-item-prev))
  (declare (optimize (speed 3))
           (type mahogany-group group)
           (type tree:output-node output-node)
           (type (function (ring-list:ring-list T) (values fixnum)) add-fun))
  (let ((hidden-views (mahogany-group-hidden-views group))
        (hidden-set (make-hash-table))) ; eql should be okay, as view objects get reused
    (ring-list:foreach-item (v hidden-views)
      (setf (gethash v hidden-set) t))
    (dolist (f (tree:get-populated-frames output-node))
      (let ((v (tree:frame-surface f)))
        (unless (gethash v hidden-set)
          (funcall add-fun hidden-views v)
          (hrt:view-set-hidden v t))
        (setf (gethash v (mahogany-group-hidden-view-map group))
              (%make-hidden-view-info output-node f))))))

(defun %group-make-fullscreen (group view output)
  (declare (type (or null hrt:output) output)
           (type hrt:view view)
           (type mahogany-group group))
  (hrt:view-set-fullscreen view t)
  (alexandria:if-let ((frame (hrt::view-container view)))
    ;; The frame is visible, immediately fullscreen it:
    (let ((output-node (if output
			   (gethash (hrt:output-full-name output)
                                    (mahogany-group-output-map group))
			   (%group-current-output-node group))))
      (unless output-node
        (mahogany/log:log-string :warn "Could not find output when making view fullscreen")
        (return-from %group-make-fullscreen nil))
      ;; A floating window comes back tiled from fullscreen:
      (if (typep frame 'tree:floating-frame)
          (%destroy-floating-frame group frame)
          (setf (tree:frame-surface frame) nil))
      (let ((prev-fullscreen (tree:set-fullscreen output-node view)))
        (cond
          (prev-fullscreen
           (%add-hidden (mahogany-group-hidden-views group) prev-fullscreen))
          (t
           ;; Since there wasn't a fullscreen node here previously, mark all the views
           ;; that it hides as hidden:
           (%hide-views-under-fullscreen group output-node))))
      ;; When a frame on the current output is focused, move the focus to the fullscreen
      ;; view:
      (when (eq (%group-current-output-node group)
                output-node)
        (setf (mahogany-group-current-frame group) output-node)))
    ;; Frame isn't visible; allow the view to be fullscreened and we will deal with it
    ;; when it becomes visible:
    (progn
      (log-string :trace "Allowing hidden view to become fullscreen: ~S" view)))
  ;; We always fulfull the request:
  t)

(defun %clear-fullscreen-state (group frame)
  "Unmark the output node frame and make the views that are under it visible.
After this function is ran, the current frame needs to be set and focused."
  (declare (type tree:output-node frame)
           (type mahogany-group group))
  (let ((hidden-map (mahogany-group-hidden-view-map group)))
    (loop :for hidden-view :being :the :hash-key
            :of hidden-map
              :using (hash-value data)
          :when (eql frame (%hidden-view-info-output data))
            :do (remhash hidden-view hidden-map)
                (hrt:view-set-hidden hidden-view nil)
                (ring-list:remove-item (mahogany-group-hidden-views group)
                                       hidden-view
                                       :test #'eql)))
  (tree:unmark-frame-focused frame (server-seat *compositor-state*))
  (tree:clear-fullscreen frame))

(defun %group-unfullscreen (group view)
  (declare (type mahogany-group group)
           (type hrt:view view))
  (hrt:view-set-fullscreen view nil)
  (alexandria:if-let ((frame (hrt::view-container view)))
    ;; The frame is visible, we need to do some cleanup:
    (cond
      ((typep frame 'tree:output-node)
       (%clear-fullscreen-state group frame)
       (let ((to-focus (tree:find-focused-frame frame)))
         (setf (mahogany-group-current-frame group) to-focus)
         (alexandria:when-let ((prev (tree:frame-surface to-focus)))
           (%add-hidden (mahogany-group-hidden-views group) prev))
         (setf (tree:frame-surface to-focus) view)))
      (t
       ;; We aren't doing anything; communicate that to the calling code
       nil))
    (progn
      (log-string :trace "Make hidden view not fullscreen: ~S" view))))

(defun group-set-fullscreen (group view output set-fullscreen)
  (if set-fullscreen
      (%group-make-fullscreen group view output)
      (%group-unfullscreen group view)))

(defun %swap-view-into-frame (group current-frame view)
  (declare (type mahogany-group group)
           (type (or null hrt:view) view))
  (cond
    ((hrt:view-fullscreen-p view)
     (let* ((cur-output (%group-current-output-node group))
            (prev-fullscreen (tree:set-fullscreen cur-output view)))
       (unless prev-fullscreen
         (%hide-views-under-fullscreen group cur-output #'ring-list:add-item))
       (setf (mahogany-group-current-frame group) cur-output)))
    (t
     (let ((hidden-data (gethash view (mahogany-group-hidden-view-map group))))
       (declare (type (or null %hidden-view-info) hidden-data))
       (etypecase current-frame
         (tree:output-node
          (%clear-fullscreen-state group current-frame)
          (cond
            ((and hidden-data
                  (eql (%hidden-view-info-output hidden-data) current-frame))
             (log-string :trace "Hidden view is visible under fullscreen view")
             ;; The view should be visible, focus its frame:
             (let ((to-focus (%hidden-view-info-frame hidden-data)))
               (setf (mahogany-group-current-frame group) to-focus)))
            (t
             (let ((to-focus (tree:find-focused-frame current-frame)))
               (setf (mahogany-group-current-frame group) to-focus)
               (alexandria:when-let ((prev (tree:frame-surface to-focus)))
                 (%add-hidden (mahogany-group-hidden-views group) prev))
               (setf (tree:frame-surface to-focus) view)))))
         (tree:view-frame
          (when hidden-data
            (setf (tree:frame-surface (%hidden-view-info-frame hidden-data))
                  nil)
            (remhash view (mahogany-group-hidden-view-map group)))
          (setf (tree:frame-surface current-frame) view))))))
  (hrt:dirty-view-transaction))

(defun %group-leave-floating (group)
  "Move GROUP's focus from a floating window to the tiled frame focused
last, for the commands that act on tiled frames."
  (when (typep (mahogany-group-current-frame group) 'tree:floating-frame)
    (alexandria:when-let ((tiled (%group-tiled-frame group)))
      (group-focus-frame group tiled (server-seat *compositor-state*)))))

(defun group-next-hidden (group)
  (declare (type mahogany-group group))
  (%group-leave-floating group)
  (let ((current-frame (mahogany-group-current-frame group))
        (hidden-views (mahogany-group-hidden-views group))
        (next-view))
    (when (> (ring-list:ring-list-size hidden-views) 0)
      (alexandria:if-let ((view (tree:frame-surface current-frame)))
        (setf next-view (%swap-next-hidden hidden-views view))
        (setf next-view (%pop-hidden-item hidden-views)))
      (%swap-view-into-frame group current-frame next-view))))

(defun group-previous-hidden (group)
  (declare (type mahogany-group group))
  (%group-leave-floating group)
  (let ((current-frame (mahogany-group-current-frame group))
        (hidden-views (mahogany-group-hidden-views group))
        (next-view))
    (when (> (ring-list:ring-list-size hidden-views) 0)
      (alexandria:if-let ((view (tree:frame-surface current-frame)))
        (setf next-view (%swap-prev-hidden hidden-views view))
        (setf next-view (%pop-hidden-item hidden-views)))
      (%swap-view-into-frame group current-frame next-view))))

(defun group-maximize-view (group view)
  (declare (type mahogany-group group)
           (type hrt:view view))
  ;; attempt to stop abuse by only listening when the
  ;; frame requesting this info is visible:
  (alexandria:if-let ((frame (hrt::view-container view)))
    (progn
      (log-string :trace "maximizing view ~S" view)
      (%maximize-frame group frame))
    (hrt:view-configure view)))

(defun group-minimize-view (group view)
  (declare (type mahogany-group group)
           (type hrt:view view))
  ;; attempt to stop abuse by only doing something
  ;; if the view is focused:
  (let* ((cur-frame (mahogany-group-current-frame group))
         (cur-view (tree:frame-surface cur-frame)))
    (if (equal cur-view view)
        (progn
          (log-string :trace "\"minimizing\" view ~S" view)
          (group-next-hidden group))
        (hrt:view-configure view))))

(defun group-remove-current-frame (group)
  (declare (type mahogany-group group))
  (let ((cur-frame (mahogany-group-current-frame group)))
    (when (or (tree:root-frame-p cur-frame)
              (tree:topmost-frame-p cur-frame))
      (error 'mahogany/util:invalid-operation
             :text "Cannot remove the topmost frame in the frame tree."))
    (let* ((sibling (find-if (lambda (child) (not (eq child cur-frame)))
                             (mahogany/tree:tree-children
                              (tree:frame-parent cur-frame))))
           (to-focus (and sibling (mahogany/tree:find-first-leaf sibling))))
      (when (not to-focus)
        (error 'mahogany/util:invalid-operation
               :text "No frame to focus after removal"))
      (let ((rescued (list)))
        (mahogany/tree:remove-frame
         cur-frame
         (lambda (removed)
           (let ((view (mahogany/tree:frame-surface removed)))
             (when view
               (push view rescued)))))
        (when rescued
          (when (not (tree:frame-surface to-focus))
            (setf (tree:frame-surface to-focus) (pop rescued)))
          (let ((hidden-list (mahogany-group-hidden-views group)))
            (dolist (v rescued)
              (%add-hidden hidden-list v)))))
      (setf (mahogany-group-current-frame group) to-focus)
      (hrt:dirty-view-transaction)
      to-focus)))
