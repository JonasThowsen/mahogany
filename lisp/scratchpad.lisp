(in-package #:mahogany)

;;; The scratchpad: a window kept out of the way in a group of its own
;;; (".scratchpad", which no list shows and gnext skips), brought into
;;; the current frame with one key and sent back with the same key. The
;;; first time, with nothing in the scratchpad, the key starts
;;; *scratchpad-command* and adopts the window it opens.

(config:defconfig *scratchpad-command* '("foot" "--app-id" "scratchpad")
  list
  "The program started when the scratchpad is empty, as a list of
arguments; its window becomes the scratchpad window.")

(config:defconfig *scratchpad-group-name* ".scratchpad"
  string
  "The name of the group that keeps the scratchpad windows. A name
starting with a dot keeps it out of the lists and of gnext/gprev.")

(defglobal *scratchpad-views* '()
  "The scratchpad windows that are out, in an ordinary group, most
recently brought out first.")

(defglobal *scratchpad-adopt-next* nil
  "True while the scratchpad waits for the window of the program it
started.")

(defun scratchpad-group (&optional (create t))
  "The scratchpad group, made when CREATE is true and it is missing."
  (or (find *scratchpad-group-name* (state-groups *compositor-state*)
            :key #'mahogany-group-name :test #'string=)
      (and create
           ;; Number 0, which the numbered groups never take, so s-1..9
           ;; and the group lists stay as they are:
           (mahogany-state-group-add *compositor-state*
                                     :group-name *scratchpad-group-name*
                                     :make-current nil
                                     :number 0
                                     ;; Never shown, on no output:
                                     :home :none))))

(defun %live-view-p (view)
  (%find-view-in-groups view (state-groups *compositor-state*)))

(defun scratchpad-views ()
  "The windows in the scratchpad, most recently put there first."
  (let ((group (scratchpad-group nil)))
    (and group (mahogany-group-views group))))

(defun send-to-scratchpad (&optional view)
  "Send VIEW, or the focused window, to the scratchpad."
  (let* ((state *compositor-state*)
         (group (state-current-group state))
         (frame (state-current-frame state))
         (view (or view (and (typep frame 'tree:frame) (tree:frame-surface frame)))))
    (unless (typep view 'hrt:view)
      (error 'mahogany/util:invalid-operation :text "No window to send to the scratchpad"))
    (let ((source (%find-view-in-groups view (state-groups state)))
          (scratch (scratchpad-group)))
      (when (eq source scratch)
        (return-from send-to-scratchpad view))
      (setf *scratchpad-views* (remove view *scratchpad-views*))
      (hrt:with-view-transaction ()
        (group-move-view source scratch view)
        (when (eq source group)
          (%fill-frame-from-hidden group frame)
          (state-focus-frame state (mahogany-group-current-frame group) (server-seat state))))
      (hrt:dirty-view-transaction)
      (mode-line-update)
      view)))

(defun show-scratchpad (&optional view)
  "Bring VIEW, or the scratchpad window put away last, into the
current frame. Returns it, or NIL with nothing to show."
  (let* ((state *compositor-state*)
         (group (state-current-group state))
         (scratch (scratchpad-group nil))
         (view (or view (first (scratchpad-views)))))
    (when (and view scratch)
      (hrt:with-view-transaction ()
        (group-move-view scratch group view)
        (pushnew view *scratchpad-views*)
        ;; It is now a hidden window of the current group; show-view
        ;; swaps it into the current frame:
        (mahogany-state-show-view state view))
      (hrt:dirty-view-transaction)
      view)))

(defun %scratchpad-adopt (view group)
  (declare (ignore group))
  (when *scratchpad-adopt-next*
    (setf *scratchpad-adopt-next* nil)
    (pushnew view *scratchpad-views*)))

(pushnew '%scratchpad-adopt *new-view-hook*)

(defun toggle-scratchpad ()
  "Send the focused window to the scratchpad when it came from there;
otherwise bring the scratchpad window out into the current frame, or
start *scratchpad-command* when the scratchpad is empty."
  (let* ((state *compositor-state*)
         (frame (state-current-frame state))
         (focused (and (typep frame 'tree:frame) (tree:frame-surface frame))))
    (setf *scratchpad-views* (remove-if-not #'%live-view-p *scratchpad-views*))
    (cond ((and focused (member focused *scratchpad-views*))
           (send-to-scratchpad focused))
          ((scratchpad-views)
           (show-scratchpad))
          (t
           (setf *scratchpad-adopt-next* t)
           (handler-case (uiop:launch-program *scratchpad-command*)
             (error (c)
               (setf *scratchpad-adopt-next* nil)
               (toast-message state (format nil "Could not start ~A: ~A"
                                            (first *scratchpad-command*) c)
                              :theme *message-error-theme*)))))))

(defcommand scratchpad-toggle ()
  (:documentation "Bring the scratchpad window out, or put it back")
  (:method () (toggle-scratchpad)))

(defcommand scratchpad-send ()
  (:documentation "Send the focused window to the scratchpad")
  (:method () (send-to-scratchpad)))

(defcommand scratchpad-menu ()
  (:documentation "Choose a scratchpad window to bring out")
  (:method () (launcher :scratchpad)))

(define-launcher-mode :scratchpad (:prompt "Scratchpad" :description "Scratchpad windows")
  :items (loop for view in (scratchpad-views)
               collect (make-menu-item (or (hrt:view-title view) "(untitled)") :data view))
  :action (lambda (view) (show-scratchpad view)))
