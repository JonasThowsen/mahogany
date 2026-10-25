(in-package #:mahogany)

;;; Moving between outputs (monitors). A group spans every output, with
;;; a frame tree on each, so a window goes to another output by moving
;;; into a frame of that output's tree, and the focus by focusing one.

(defun current-output ()
  "The output of the focused frame."
  (group-current-output (state-current-group *compositor-state*)))

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

(defun output-frame (output &optional (group (state-current-group *compositor-state*)))
  "The frame GROUP focuses on OUTPUT: its focused frame there, or its
first."
  (alexandria:when-let ((node (gethash (hrt:output-full-name output)
                                       (mahogany-group-output-map group))))
    (or (tree:find-focused-frame node)
        (tree:find-first-leaf node))))

(defun focus-output (output)
  "Focus the current group's frame on OUTPUT."
  (let ((state *compositor-state*))
    (alexandria:when-let ((frame (output-frame output)))
      (state-focus-frame state frame (server-seat state))
      frame)))

(defun move-window-to-output (output &key (follow t))
  "Move the focused window to the frame the current group focuses on
OUTPUT, and focus it there when FOLLOW is true. What that frame showed
goes behind it; the frame left behind shows a hidden window if there
is one."
  (let* ((state *compositor-state*)
         (group (state-current-group state))
         (source (state-current-frame state))
         (view (and (typep source 'tree:frame) (tree:frame-surface source)))
         (target (output-frame output)))
    (unless (typep view 'hrt:view)
      (error 'mahogany/util:invalid-operation :text "No window to move"))
    (unless target
      (error 'mahogany/util:invalid-operation :text "The group has no frame on that output"))
    (unless (eq source target)
      (hrt:with-view-transaction ()
        (setf (tree:frame-surface source) nil)
        (alexandria:when-let ((shown (tree:frame-surface target)))
          (%add-hidden (mahogany-group-hidden-views group) shown))
        (setf (tree:frame-surface target) view)
        (%fill-frame-from-hidden group source)
        (when follow
          (state-focus-frame state target (server-seat state)))
        (group-views-changed group (tree:find-root-frame source))
        (group-views-changed group (tree:find-root-frame target)))
      (hrt:dirty-view-transaction))
    view))

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
