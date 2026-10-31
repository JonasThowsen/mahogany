(in-package #:mahogany)

;;; Moving between outputs (monitors). Each output has groups of its
;;; own and shows one of them, so a window goes to another output by
;;; moving into a frame of the group shown there, and the focus by
;;; focusing one, which makes that group the current one.

(defun current-output ()
  "The output of the focused frame."
  (alexandria:when-let ((group (state-current-group *compositor-state*)))
    (group-current-output group)))

(defun outputs ()
  "The outputs in use, in layout order: left to right, then top to
bottom."
  (sort (map 'list #'tree:output-container-output
             (state-cur-outputs *compositor-state*))
        (lambda (a b)
          (multiple-value-bind (ax ay) (hrt:output-position a)
            (multiple-value-bind (bx by) (hrt:output-position b)
              (or (< ax bx) (and (= ax bx) (< ay by))))))))

(defun next-output (&optional (step 1) (from (current-output)))
  "The output STEP after FROM in layout order, wrapping around; NIL with
only one output."
  (let* ((outputs (outputs))
         (position (position from outputs :test #'hrt:output=)))
    (when (and position (> (length outputs) 1))
      (nth (mod (+ position step) (length outputs)) outputs))))

(defun output-frame (output &optional (group (state-output-group *compositor-state* output)))
  "The frame GROUP (the group shown on OUTPUT by default) focuses: its
focused frame, or its first."
  (alexandria:when-let* ((group group)
                         (node (group-output-node group)))
    (if (tree::output-node-fullscreen node)
        node
        (or (tree:find-focused-frame node)
            (tree:find-first-leaf node)))))

(defun focus-output (output)
  "Focus the frame of the group shown on OUTPUT."
  (let ((state *compositor-state*))
    (alexandria:when-let ((frame (output-frame output)))
      (state-focus-frame state frame (server-seat state))
      frame)))

(defun move-view-to-frame (view target &key (follow t) swap)
  "Move VIEW into the frame TARGET, in its own group or in the group
shown on another output, and focus it there when FOLLOW is true. What
TARGET showed goes behind it, or, with SWAP and both frames in one
group, into the frame VIEW leaves; a frame left empty shows a hidden
window if there is one. Returns VIEW."
  (let* ((state *compositor-state*)
         (seat (server-seat state))
         (source (hrt::view-container view))
         (source-group (%find-view-in-groups view (state-groups state)))
         (target-group (state-frame-group state target)))
    (unless (typep source 'tree:view-frame)
      (error 'mahogany/util:invalid-operation :text "The window is not in a frame"))
    (when (typep source 'tree:floating-frame)
      (error 'mahogany/util:invalid-operation
             :text "The window floats; float-toggle (s-v) tiles it first"))
    (unless (typep target 'tree:view-frame)
      (error 'mahogany/util:invalid-operation :text "There is no frame to move the window into"))
    (unless (and source-group target-group)
      (error 'mahogany/util:invalid-operation :text "The window has no group"))
    (unless (eq source target)
      (hrt:with-view-transaction ()
        (let ((shown (tree:frame-surface target)))
          (setf (tree:frame-surface source) nil)
          (cond
            ((eq source-group target-group)
             (cond ((and shown swap)
                    (setf (tree:frame-surface source) shown))
                   (shown
                    (%add-hidden (mahogany-group-hidden-views target-group) shown)))
             (setf (tree:frame-surface target) view))
            (t
             ;; Another output's group: the view changes group, and
             ;; scene layer with it.
             (setf (mahogany-group-views source-group)
                   (remove view (mahogany-group-views source-group)))
             (tree:layer-container-transfer-view (mahogany-group-tiled-container target-group) view)
             (push view (mahogany-group-views target-group))
             (when shown
               (%add-hidden (mahogany-group-hidden-views target-group) shown))
             (%swap-view-into-frame target-group target view)))
          (%fill-frame-from-hidden source-group source)
          (when follow
            (state-focus-frame state target seat))
          (group-views-changed source-group (tree:find-root-frame source))
          (unless (eq source-group target-group)
            (group-views-changed target-group (tree:find-root-frame target)))))
      (hrt:dirty-view-transaction))
    view))

(defun move-window-to-output (output &key (follow t))
  "Move the focused window to the frame focused in the group shown on
OUTPUT, and focus it there when FOLLOW is true. What that frame showed
goes behind it; the frame left behind shows a hidden window if there
is one."
  (let* ((state *compositor-state*)
         (source (state-current-frame state))
         (view (and (typep source 'tree:frame) (tree:frame-surface source)))
         (target (output-frame output)))
    (unless (typep view 'hrt:view)
      (error 'mahogany/util:invalid-operation :text "No window to move"))
    (unless target
      (error 'mahogany/util:invalid-operation :text "Nothing is shown on that output"))
    (move-view-to-frame view target :follow follow)))

(defcommand focus-next-output ()
  (:documentation "Focus the next output")
  (:method ()
    (alexandria:if-let ((output (next-output 1)))
      (focus-output output)
      (toast-message *compositor-state* "There is only one output"))))

(defcommand focus-previous-output ()
  (:documentation "Focus the previous output")
  (:method ()
    (alexandria:if-let ((output (next-output -1)))
      (focus-output output)
      (toast-message *compositor-state* "There is only one output"))))

(defcommand move-window-to-next-output ()
  (:documentation "Move the focused window to the next output")
  (:method ()
    (alexandria:if-let ((output (next-output 1)))
      (move-window-to-output output)
      (toast-message *compositor-state* "There is only one output"))))

(defcommand move-window-to-previous-output ()
  (:documentation "Move the focused window to the previous output")
  (:method ()
    (alexandria:if-let ((output (next-output -1)))
      (move-window-to-output output)
      (toast-message *compositor-state* "There is only one output"))))

(defun %output-label (output)
  (format nil "~A ~A" (hrt:output-make output) (hrt:output-model output)))

(define-launcher-mode :outputs (:prompt "Output" :description "Outputs (focus one)")
  :items (loop for output in (outputs)
               collect (make-menu-item (hrt:output-name output)
                                       :data output
                                       :detail (if (hrt:output= output (current-output))
                                                   "current"
                                                   (%output-label output))))
  :action #'focus-output)

(define-launcher-mode :move-to-output (:prompt "Move window to" :description "Move the window to an output")
  :items (loop for output in (outputs)
               unless (hrt:output= output (current-output))
                 collect (make-menu-item (hrt:output-name output)
                                         :data output
                                         :detail (%output-label output)))
  :action #'move-window-to-output)

(defcommand output-menu ()
  (:documentation "Choose an output to focus")
  (:method () (launcher :outputs)))

(defcommand move-window-to-output-menu ()
  (:documentation "Choose an output to move the focused window to")
  (:method () (launcher :move-to-output)))
