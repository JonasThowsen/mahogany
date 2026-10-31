(in-package #:mahogany)

;; In mode-line.lisp, which loads after this file:
(declaim (ftype function mode-line-update mode-line-reset stop-idle menu-cancel
                        wallpaper-update wallpaper-reset notifications-stop))

(defvar *default-group-name* "1"
  "The name of the first group of an output. Groups are named by their
number unless given a name (grename), as workspaces are.")

;;; Groups are per output, as the workspaces of dwm or Hyprland: each
;;; output has its own groups 1, 2, 3 …, one of them shown
;;; (state-output-group), and the group of the focused frame is the
;;; current one (state-current-group). Selecting a group by number
;;; changes only the output that has the focus, and a window goes to
;;; another output by moving into the group shown there. A group has one
;;; output node in its frame tree; its home names the output.

;; If there turns out to be more choices than
;; minimize and maximize, make this a bitmask or separate them out:
(config-system:defconfig *follow-config-events* :all
  (member :none :all :minimize :maximize)
  "The client window management events that the compositor listends to.")

(config-system:defconfig *focus-on-activation* t
  boolean
  "Whether a window that asks to be focused through xdg-activation (a
browser when a link is opened in it, for instance) gets the focus: its
group becomes the current one and its frame is focused. A hidden window
is shown in the current frame.")

(config-system:defconfig *shutdown-timeout-msec* 1000
  (signed-byte 32) ;; This goes to a a C int; unless this is running
  ;; on a weird machine, it's going to big enough on all platforms.
  "How long to wait for connected clients to disconnect after compositor
sends a close event prior to exiting. Units are in milliseconds.")

(declaim (type (or null hrt:timer-handle) *shutdown-timer*))
(defglobal *shutdown-timer* nil)

(declaim (inline %find-output-container))
(defun %find-output-container (hrt-output state)
  "Return the output-container tracking HRT-OUTPUT, or NIL when STATE has none
or HRT-OUTPUT is NIL or a null pointer."
  (declare (type mahogany-state state)
           (type (or null cffi:foreign-pointer) hrt-output))
  (when (and hrt-output (not (cffi:null-pointer-p hrt-output)))
    (find hrt-output (state-cur-outputs state)
          :key #'tree::output-container-output-ptr
          :test #'cffi:pointer-eq)))

(defun %output-designator-name (output)
  "The full name of OUTPUT, given as an output, a name or NIL."
  (etypecase output
    (null nil)
    (string output)
    (hrt:output (hrt:output-full-name output))
    (tree:output-container (hrt:output-full-name (tree:output-container-output output)))))

(defun %home-groups (state home)
  "The groups whose home is HOME (an output's full name, NIL or :none)."
  (remove-if-not (lambda (group) (equal (mahogany-group-home group) home))
                 (coerce (state-groups state) 'list)))

(defun output-groups (state output)
  "The groups of OUTPUT (its workspaces), in order of their numbers."
  (declare (type mahogany-state state))
  (sort (remove-if-not #'group-attached-p
                       (%home-groups state (%output-designator-name output)))
        #'< :key #'mahogany-group-number))

(defun state-output-group (state output)
  "The group shown on OUTPUT, or NIL for an output not in use."
  (declare (type mahogany-state state))
  (gethash (%output-designator-name output) (state-output-groups state)))

(defun state-current-home (state)
  "The full name of the output that has the focus, or NIL without one."
  (alexandria:when-let ((group (state-current-group state)))
    (let ((home (mahogany-group-home group)))
      (and (stringp home) home))))

(defun %next-group-index (state home)
  (declare (type mahogany-state state))
  (mahogany/util::find-free-number
   (mapcar #'mahogany-group-number (%home-groups state home)) 1))

(defun %add-group (state name index home)
  (declare (type mahogany-state state)
           (type string name)
           (type fixnum index))
  (let ((group (make-mahogany-group name index (state-server state))))
    (setf (mahogany-group-home group) home)
    (vector-push-extend group (state-groups state))
    group))

(defun state-frame-group (state frame)
  "The group whose frame tree holds FRAME, or NIL for a layer shell
frame or a frame of no group."
  (declare (type mahogany-state state))
  (when (group-frame-p frame)
    (let ((root (tree:find-root-frame frame)))
      (find-if (lambda (group)
                 (eq (group-output-node group) root))
               (state-groups state)))))

(defun server-state-init (state server output-callbacks seat-callbacks view-callbacks
			  layer-shell-callbacks
                          &key (debug-level 3))
  (setf (state-server state) server)
  (unless (hrt:server-init server
                           output-callbacks seat-callbacks view-callbacks
                           layer-shell-callbacks
                           debug-level)
    (error 'mahogany/util:mahogany-panic
           :text "Could not initialize the compositor."))
  ;; The first group waits for the first output, which adopts it:
  (let ((default-group (%add-group state *default-group-name* 1 nil)))
    (setf (state-%current-group state) default-group)))

(defun server-state-reset (state)
  (declare (type mahogany-state state))
  (with-accessors ((groups state-groups)
                   (server state-server)
                   (output-groups state-output-groups)
                   (views state-views)
                   (layer-surfaces state-layer-surfaces))
      state
    ;; Clear the current frame so that subsequent cleanup code
    ;; doesn't try to switch focus to an invalid frame:
    (setf (state-%current-frame state) nil)
    (mode-line-reset)
    (wallpaper-reset)
    (notifications-stop)
    (stop-idle)
    ;; A menu open at shutdown: its thread must not wait forever.
    (menu-cancel)
    ;; This kicks off the destruction sequence, which
    ;; calls the various output and seat removal callbacks. At the end, we
    ;; are left in a state where all hrt and wlroots based objects
    ;; are invalid.
    (hrt:server-finish server)
    ;; The actual scene object is freed during hrt-server-finish:
    (setf server nil)
    ;; Since we don't listen to the callbacks that destroy the
    ;; infrastructure needed for groups to work, we just clear them
    ;; out here. Do a bit of checking and logging to make sure
    ;; everything that needed to be cleaned up was.
    (flet ((clear-toplevel-tbl (table type)
             (declare (type hash-table table)
                      (type string type))
             (let ((lst (list)))
               (maphash (lambda (k v)
                          (declare (ignore k))
                          (push v lst))
                        table)
               (when lst
                 (log-string :error "~A were orphaned: ~A~%" type lst)))
             (clrhash table)))
      (clear-toplevel-tbl views "views")
      (clear-toplevel-tbl layer-surfaces "layer surfaces"))
    (clrhash output-groups)
    (setf (state-%current-group state) nil)
    (setf groups (adjust-array groups 0 :fill-pointer 0))))

(defun server-stop (state)
  (declare (type mahogany-state state))
  (hrt:hrt-server-stop (state-server state)))

(defun %handle-shutdown-timer (timer)
  (declare (type hrt:timer-handle timer))
  (let* ((state (hrt:timer-handle-data timer))
        (num-views (hash-table-count (state-views state))))
    (declare (type mahogany-state state))
    (cond
      ((> num-views 0)
       (toast-message state
                      (format nil "Waiting for ~A client~P to close."
                              num-views num-views))
       (hrt:timer-handle-update timer *shutdown-timeout-msec*))
      (t
       (hrt:timer-handle-destroy timer)
       (server-stop state)))))

(defun server-shutdown-cancel (state)
  (declare (type mahogany-state state))
  (log-string :info "Shutdown: shutdown canceled.")
  (hrt:timer-handle-destroy *shutdown-timer*)
  (setf *shutdown-timer* nil)
  (toast-message state "Quitting Canceled."))

(defun server-shutdown-gracefully (state)
  (declare (type mahogany-state state))
  (let ((num-views (hash-table-count (state-views state))))
    (cond
      ((> num-views 0)
       (log-string :info "Shutdown: Waiting for clients to disconnect.")
       (toast-message state
                      (format nil "Quiting after ~A client~P close..."
                              num-views num-views))
       (maphash (lambda (_ view)
                  (declare (ignore _))
                  (hrt:view-request-close view))
                (state-views state))
       (unless *shutdown-timer*
         (let ((timer (hrt:server-make-timer
                       (state-server state)
                       #'%handle-shutdown-timer state)))
           (hrt:timer-handle-update timer *shutdown-timeout-msec*)
           (setf *shutdown-timer* timer))))
      (t
       (log-string :info "Shutdown: No clients, exiting now.")
       (server-stop state)))))

(config-system:defconfig *show-group-name* nil
  boolean
  "Whether to name the group in a toast message when switching to it.
Off by default: the mode-line marks it.")

(config-system:defconfig *remove-empty-groups* t
  boolean
  "Whether a group named by its number goes away when it is left with
no windows, as niri's workspaces do, so only the groups in use remain.
A group named with grename stays.")

(config-system:defconfig *group-name-delay* 500
  fixnum
  "How long the group name is shown for, in milliseconds.")

(defun group-listed-p (group)
  "Whether GROUP is one the user cycles through and sees in lists: those
whose names start with a dot, such as the scratchpad's, are not."
  (let ((name (mahogany-group-name group)))
    (not (and (plusp (length name)) (char= (char name 0) #\.)))))

(defun %group-disposable-p (state group)
  "Whether GROUP goes away now that it is left: *remove-empty-groups*,
and it is attached to an output but not shown there, has no windows and
is named by its number."
  (declare (type mahogany-state state))
  (and *remove-empty-groups*
       (group-attached-p group)
       (null (mahogany-group-views group))
       (string= (mahogany-group-name group)
                (%next-group-name (mahogany-group-number group)))
       (let ((home (mahogany-group-home group)))
         (and (stringp home)
              (not (eq group (state-output-group state home)))))))

(defun %show-output-group (state group)
  "Show GROUP on its output in place of the group shown there, without
moving the focus."
  (declare (type mahogany-state state)
           (type mahogany-group group))
  (let* ((home (mahogany-group-home group))
         (shown (and (stringp home) (gethash home (state-output-groups state)))))
    (when (and shown (not (eq shown group)))
      (group-suspend shown (server-seat state)))
    (when (group-attached-p group)
      (setf (gethash home (state-output-groups state)) group))
    (group-show group)))

(defun (setf state-current-group) (group state)
  "Make GROUP the current one: shown on its output in place of the group
shown there, and focused."
  (declare (type mahogany-state state)
           (type mahogany-group group))
  (when (not (find group (state-groups state) :test #'eq))
    (error (format nil "Group ~S is not part of this state" group)))
  (let ((previous (state-%current-group state))
        (seat (server-seat state)))
    (%show-output-group state group)
    ;; The previous group on another output stays shown, but loses the
    ;; focus:
    (when (and previous (not (eq previous group)) (mahogany-group-active-p previous))
      (group-unfocus previous seat))
    (setf (state-%current-group state) group)
    (group-wakeup group seat)
    (alexandria:when-let ((group-frame (mahogany-group-current-frame group)))
      (state-focus-frame state group-frame seat)
      (when *show-group-name*
        (toast-message state (mahogany-group-name group)
                       :ms-delay *group-name-delay*)))
    ;; The group left behind goes when nothing is in it:
    (when (and previous (not (eq previous group))
               (%group-disposable-p state previous))
      (%delete-group state previous)))
  (mode-line-update)
  (hrt:dirty-view-transaction))

(defun %state-select-group (state designator &optional (output (state-current-home state)))
  "The group of OUTPUT (the focused one by default) that DESIGNATOR
names: its number, or NIL."
  (declare (type mahogany-state state))
  (etypecase designator
    (null nil)
    (integer
     (find designator (output-groups state output)
           :key #'mahogany-group-number :test #'=))))

(defun state-select-group (state designator)
  "Switch the focused output to its group DESIGNATOR (a number)."
  (declare (type mahogany-state state))
  (let ((group (%state-select-group state designator)))
    (when group
      (setf (state-current-group state) group))))

(defun state-next-group (state &key (step 1) (output (state-current-home state)))
  "Switch OUTPUT (the focused one by default) to the group STEP after
the one it shows, by number and around the end; with one group, nothing."
  (declare (type mahogany-state state))
  (let* ((groups (remove-if-not #'group-listed-p (output-groups state output)))
         (shown (state-output-group state output))
         (position (position shown groups)))
    (when (and position (> (length groups) 1))
      (setf (state-current-group state)
            (nth (mod (+ position step) (length groups)) groups)))))

(defun state-previous-group (state &key (output (state-current-home state)))
  (state-next-group state :step -1 :output output))

(defun group-frame-p (frame)
  ;; TODO: It might be better to start storing the
  ;; group that a frame is in, so we can use that
  ;; instead of just relying on the type. It would
  ;; also make it possible to pass arbitrary frames
  ;; to state-focus-frame
  (not (typep frame 'tree::layer-shell-frame)))

(defun state-focus-frame (state new-frame seat)
  "Focus the given frame: one of a group shown on an output, whose group
becomes the current one, or a layer shell frame."
  (with-accessors ((cur-frame state-%current-frame)
                   (cur-group state-%current-group))
      state
    (unless (eql cur-frame new-frame)
      ;; Determine if the frame is in a group:
      (let ((cur-in-group (group-frame-p cur-frame))
            (next-group (state-frame-group state new-frame)))
        (cond
          (next-group
           (unless (eq next-group cur-group)
             (when (and cur-in-group cur-group)
               (group-unfocus cur-group seat))
             (setf cur-group next-group)
             (mode-line-update))
           (group-focus-frame next-group new-frame seat))
          (t
           (when (and cur-in-group cur-group)
             (group-unfocus cur-group seat))
           (tree:mark-frame-focused new-frame seat))))
      (setf cur-frame new-frame))))

(defun %ensure-focus (state)
  "After outputs came or went: when the current group has no output,
make the group shown on the first output current, and focus a frame when
none is."
  (declare (type mahogany-state state))
  (let ((current (state-current-group state)))
    (unless (and current (group-attached-p current))
      (alexandria:when-let ((group (loop for container across (state-cur-outputs state)
                                         thereis (state-output-group state container))))
        (when (and current (not (eq current group)) (mahogany-group-active-p current))
          (group-unfocus current (server-seat state)))
        (setf (state-%current-group state) group
              current group)))
    (when (and current (null (state-%current-frame state)))
      (alexandria:when-let ((frame (mahogany-group-current-frame current)))
        (state-focus-frame state frame (server-seat state))))))

(defun server-keystate-reset (state)
  (setf (state-key-state state)
        (make-key-state (state-keybindings state))))

(defun (setf state-keybindings) (kmaps state)
  (declare (type list kmaps)
           (type mahogany-state state))
  (setf (state-%keybindings state) kmaps)
  (unless (key-state-active-p (state-key-state state))
    (server-keystate-reset state)))

(defglobal *output-debounce-msec* 1)

(defstruct pending-output-changes
  (added nil :type list))

(defun %get-output-list (pending-changes outputs)
  (declare (type vector outputs)
           (type pending-output-changes pending-changes))
  (let* ((added (pending-output-changes-added pending-changes))
         (all-outputs (concatenate 'list outputs added)))
    (values all-outputs added)))

(defun %renumber-group (state group home &optional (preferred (mahogany-group-number group)))
  "Give GROUP the number PREFERRED among the groups of HOME, or the
lowest free one above it, renaming it when it is named by its number."
  (declare (type mahogany-state state))
  (let* ((taken (mapcar #'mahogany-group-number
                        (remove group (%home-groups state home))))
         (number (if (member preferred taken)
                     (mahogany/util::find-free-number taken preferred)
                     preferred)))
    (when (string= (mahogany-group-name group)
                   (%next-group-name (mahogany-group-number group)))
      (setf (mahogany-group-name group) (%next-group-name number)))
    (setf (mahogany-group-number group) number)))

(defun %attach-group (state group output-container)
  "Put GROUP, detached from any output, on OUTPUT-CONTAINER: back on its
own output, or away from home on another, remembering where it belongs
(its origin and its number there) so it can go back; away it gets a
free number. Its frame tree is rebuilt there, its windows hidden until
the layout places them."
  (declare (type mahogany-state state)
           (type mahogany-group group))
  (let ((name (%output-designator-name output-container))
        (home (mahogany-group-home group)))
    (cond ((equal home name))
          ((equal (mahogany-group-origin group) name)
           (%renumber-group state group name (mahogany-group-origin-number group))
           (setf (mahogany-group-origin group) nil))
          (t
           (unless (mahogany-group-origin group)
             (setf (mahogany-group-origin group) home
                   (mahogany-group-origin-number group) (mahogany-group-number group)))
           (%renumber-group state group name)))
    (setf (mahogany-group-home group) name)
    (group-add-output group output-container)
    (group-views-changed group)
    group))

(defun %first-group-of-output (state output-container)
  "The first group of OUTPUT-CONTAINER by number, made as its group 1
when it has none."
  (declare (type mahogany-state state))
  (let ((name (%output-designator-name output-container)))
    (or (first (output-groups state name))
        (let* ((index (%next-group-index state name))
               (group (%add-group state (%next-group-name index) index name)))
          (group-add-output group output-container)
          group))))

(defun %send-group-home (state group output-container)
  "Move GROUP, away on another output, home to OUTPUT-CONTAINER, which
has just come back. The output it leaves shows another of its groups
in its place."
  (declare (type mahogany-state state))
  (let* ((cur-outputs (state-cur-outputs state))
         (host (mahogany-group-home group))
         (host-container (find host cur-outputs :key #'%output-designator-name :test #'equal))
         (shown-p (eq group (state-output-group state host))))
    (when (eq group (state-current-group state))
      (setf (state-%current-frame state) nil))
    (when host-container
      (group-remove-output group host-container (server-seat state)))
    (when shown-p
      (remhash host (state-output-groups state))
      (when host-container
        (%show-output-group state (%first-group-of-output state host-container))))
    (%attach-group state group output-container)))

(defun view-forget-origin (view &optional (state *compositor-state*))
  "VIEW stays where it is when the output it came from returns: for a
window the user moved on purpose."
  (remhash view (state-view-origins state)))

(defun %merge-group-away (state group host output-name)
  "Move the windows of GROUP, whose output OUTPUT-NAME is going, into
the group with the same number on the output HOST (made when missing),
remembering where each came from, and delete GROUP. Returns the group
they went to."
  (declare (type mahogany-state state)
           (type mahogany-group group))
  (let* ((host-name (%output-designator-name host))
         (number (mahogany-group-number group))
         (origin (list output-name number (mahogany-group-name group)))
         (destination (or (%state-select-group state number host-name)
                          (mahogany-state-group-add state :number number :home host-name
                                                          :make-current nil))))
    (dolist (view (mahogany-group-views group))
      (setf (gethash view (state-view-origins state)) origin)
      (group-move-view group destination view))
    (%delete-group state group)
    destination))

(defun %bring-views-home (state output-container)
  "The windows that left OUTPUT-CONTAINER's output when it went go back
to it, each into the group it had there, made again when needed with
its name. A group they leave empty goes, as when a group is left.
Returns the groups they went to, lowest number first."
  (declare (type mahogany-state state))
  (let ((name (%output-designator-name output-container))
        (origins (state-view-origins state))
        (sources '())
        (destinations '()))
    (maphash (lambda (view origin)
               (destructuring-bind (home number group-name) origin
                 (when (equal home name)
                   (remhash view origins)
                   (alexandria:when-let ((source (%find-view-in-groups view (state-groups state))))
                     (let ((destination
                             (or (%state-select-group state number name)
                                 (mahogany-state-group-add state :number number :home name
                                                                 :group-name group-name
                                                                 :make-current nil))))
                       (group-move-view source destination view)
                       (pushnew source sources)
                       (pushnew destination destinations))))))
             origins)
    (dolist (source sources)
      (when (and (find source (state-groups state))
                 (%group-disposable-p state source))
        (%delete-group state source)))
    (sort destinations #'< :key #'mahogany-group-number)))

(defun %add-output-container (state mh-output)
  "Start using MH-OUTPUT: the groups waiting for it (those it had before
it went, or every waiting group when it is the first output) get their
frame trees on it, the windows that moved to other outputs when it
went come back into their groups there, or it gets a group 1. It shows
the current group when that came back to it, else the first group
windows came back to, else its first group by number."
  (declare (type mahogany-state state))
  (let* ((cur-outputs (state-cur-outputs state))
         (name (hrt:output-full-name mh-output))
         (first-p (zerop (length cur-outputs)))
         (output-container (tree::make-output-container mh-output))
         (current (state-current-group state))
         (waiting (remove-if-not
                   (lambda (group)
                     (let ((home (mahogany-group-home group)))
                       (and (not (eq home :none))
                            (not (group-attached-p group))
                            (or first-p (equal home name)))))
                   (state-groups state)))
         (away (remove-if-not
                (lambda (group)
                  (and (group-attached-p group)
                       (equal (mahogany-group-origin group) name)))
                (state-groups state))))
    (vector-push-extend output-container cur-outputs)
    (loop for group across waiting
          do (%attach-group state group output-container))
    (loop for group across away
          do (%send-group-home state group output-container))
    (let ((returned (%bring-views-home state output-container)))
      (%show-output-group state (cond ((and current (equal (mahogany-group-home current) name)
                                            (group-attached-p current))
                                       current)
                                      (returned (first returned))
                                      (t (%first-group-of-output state output-container)))))
    (%ensure-focus state)
    (mode-line-update)))

(defun %add-output (state mh-output)
  (declare (type mahogany-state state))
  (vector-push-extend mh-output (state-outputs state))
  (when (hrt:output-enabled mh-output)
    (%add-output-container state mh-output)))

(defun %update-output-enabled (state mh-output)
  (declare (type mahogany-state state)
           (type hrt:output mh-output))
  (if (hrt:output-enabled mh-output)
      (unless (%find-output-container (hrt:output-hrt-output mh-output)
                                      state)
        (%add-output-container state mh-output))
      (%remove-output-container state mh-output)))

(defun %try-backup-configs (full-list)
  (let ((config-map (make-hash-table :test 'equalp)))
	(map nil (lambda (output)
			   (setf (gethash output config-map) nil))
		 (state-outputs *compositor-state*))
    (tagbody
       (when (hrt::output-configure-atomic config-map)
         (go :end))
       (log-string :error "Backup default configuration modeset failed")
       ;; Since that didn't work, try configuring the
       ;; outputs individually to see if one of them works.
       ;; This strategy is just a guess; I'm not sure
       ;; why the above code would fail.
       (dolist (output full-list)
         (when (hrt:output-configure output nil)
           (clrhash config-map)
           (setf (gethash output config-map) nil)
           (go :end)))
       (error 'mahogany/util:mahogany-panic
              :text "Failed to set any configurations")
     :end
       (log-string :info "Backup output configuration applied."))
    config-map))

(defun state-use-output-layout (state output-layout)
  (declare (type mahogany-state state)
           (type mh/output-config:output-layout-config output-layout))
  (let ((config-map
          (mh/output-config:get-configuration-map
           output-layout
           (map 'list #'tree:output-container-output (state-cur-outputs state)))))
    (if config-map
        (prog1 (hrt::output-configure-atomic config-map)
          (%update-output-containers state))
        (let ((config-name (mh/output-config:output-layout-config-name output-layout)))
          (error 'mahogany/util:invalid-operation
                 :text (format nil
                               "Output layout ~S is not applicable to the current set of connected outputs"
                               config-name))))))

(defun %update-output-containers (state)
  "After a configuration was applied: take the outputs it disabled out
of use, and put the ones it enabled to use."
  (declare (type mahogany-state state))
  (map nil (lambda (output) (%update-output-enabled state output))
       (copy-seq (state-outputs state))))

(defun state-output-layouts-rescan (state)
  "Apply the output configuration that fits the outputs connected,
disabled ones included (so a configuration can turn them on again), and
put the outputs to use, or out of it, as it says."
  (declare (type mahogany-state state))
  (let ((outputs (coerce (state-outputs state) 'list)))
    (multiple-value-bind (config-map layout)
        (find-output-configurations outputs)
      ;; Because we presumably already have a valid mode,
      ;; this is not a fatal error:
      (let ((success (hrt::output-configure-atomic config-map)))
        (unless success
          (log-string :error "Failed to apply output configuration ~A"
                      layout))
        (%update-output-containers state)
        success))))

(defun process-output-changes (timer)
  (declare (type hrt:timer-handle timer))
  (hrt:timer-handle-destroy timer)
  (setf (state-pending-output-timer *compositor-state*) nil)
  (multiple-value-bind (full-list added)
      (%get-output-list (hrt:timer-handle-data timer)
                        (state-outputs *compositor-state*))
    (log-string
     :trace
     "After configuration:~%~2TAdded: ~S~%~2T~%~2TAll: ~S"
     added full-list)
    ;; If there aren't any outputs,
    ;; configuration will always fail.
    (when (> (length full-list) 0)
      (multiple-value-bind (config-map layout)
          (find-output-configurations full-list)
        (log-string :info "Applying output configuration ~S:~%  ~S"
                    (when layout
                      (mahogany/output-config:output-layout-config-name layout))
                    (with-output-to-string (s)
                      (maphash (lambda (x y) (format s "  (~S ~S)~%" x y)) config-map)))
        (unless (hrt::output-configure-atomic config-map)
          (log-string :error "Failed to apply output configuration ~A"
                      layout)
          (setf config-map (%try-backup-configs full-list)))
        (dolist (new-output added)
          (remhash new-output config-map)
          (%add-output *compositor-state* new-output))
        (maphash (lambda (output config)
                   (declare (ignore config))
                   (%update-output-enabled *compositor-state* output))
                 config-map)))
    (%ensure-focus *compositor-state*))
  (wallpaper-update))

(defun %make-output-process-timer (state change-data)
  (declare (type mahogany-state state))
  (let ((timer (hrt:server-make-timer (state-server state)
                                      #'process-output-changes
                                      change-data)))
    (hrt:timer-handle-update timer *output-debounce-msec*)
    timer))

(defun mahogany-state-output-add (state hrt-output)
  (declare (type mahogany-state state)
           (type cffi:foreign-pointer hrt-output))
  (let* ((mh-output (hrt:make-output hrt-output)))
    (log-string :debug "New output added ~S" (hrt:output-full-name mh-output))
    (alexandria:if-let ((timer (state-pending-output-timer state)))
      (let ((data (hrt:timer-handle-data timer)))
        (hrt:timer-handle-update timer *output-debounce-msec*)
        (push mh-output (pending-output-changes-added data)))
      (setf (state-pending-output-timer state)
            (%make-output-process-timer
             state
             (make-pending-output-changes
              :added (list mh-output)))))))



(declaim (inline %find-output))
(defun %find-output (hrt-output state)
  "Return the output tracking HRT-OUTPUT, or NIL if STATE has none."
  (declare (type mahogany-state state))
  (alexandria:when-let ((container (%find-output-container hrt-output state)))
    (tree:output-container-output container)))

(defun %delete-group (state group)
  (declare (type mahogany-state state))
  (let ((server (state-server state)))
    (setf (state-groups state) (delete group (state-groups state) :test #'eq))
    (destroy-mahogany-group group (hrt:hrt-server-scene-tree server)
                            (hrt:hrt-server-seat server))))

(defun %remove-output-container (state hrt-output)
  "Stop using HRT-OUTPUT. The windows of each of its groups join the
group with the same number on the first output left, remembering where
they came from (%add-output-container brings them back); without
another output the groups wait for one, their windows hidden. The
output left shows the group the current group's windows went to."
  (declare (type mahogany-state state)
           (type hrt:output hrt-output))
  (with-accessors ((cur-outputs state-cur-outputs)
                   (cur-frame state-%current-frame))
      state
    (alexandria:if-let ((output-container (%find-output-container
                          (hrt:output-hrt-output hrt-output)
                          state)))
      (let* ((mh-output (tree::output-container-output output-container))
             (name (hrt:output-full-name mh-output))
             (seat (server-seat state))
             (dead-groups (output-groups state name))
             (current (state-current-group state)))
        (log-string :debug "Output removed ~S" name)
        (setf cur-outputs (delete output-container cur-outputs :test #'equalp))
        (remhash name (state-output-groups state))
        ;; The frame focused is going, and the groups' own current frames
        ;; with it:
        (when (or (null cur-frame)
                  (not (group-frame-p cur-frame))
                  (member (state-frame-group state cur-frame) dead-groups))
          (setf cur-frame nil))
        (let ((target (and (plusp (length cur-outputs)) (aref cur-outputs 0)))
              (show nil))
          (dolist (group dead-groups)
            (group-remove-output group output-container seat)
            (when target
              (let ((destination (%merge-group-away state group target name)))
                (when (eq group current)
                  (setf show destination)))))
          (when show
            (%show-output-group state show)))
        (%ensure-focus state)
        (mode-line-update))
      ;; An output that was disabled (the lid, a configuration) left
      ;; its container when it was; at shutdown it is just torn down.
      (log-string (if (hrt:output-enabled hrt-output) :error :debug)
                  "Removed an output that was never added to a container"))))

(defun mahogany-state-output-remove (state hrt-output)
  (declare (type mahogany-state state)
           (type cffi:foreign-pointer hrt-output))
  (with-accessors ((outputs state-outputs))
      state
    ;; The output is now invalid, so remove it from the state.
    (alexandria:if-let ((mh-output (find hrt-output (state-outputs state)
                                         :test #'cffi:pointer-eq
                                         :key #'hrt:output-hrt-output)))
      (progn
        ;; Again, we just found the location of this thing. Do
        ;; we really need to search it again?
        (setf outputs (delete mh-output outputs :test #'equalp))
        (%remove-output-container state mh-output)
        (hrt:destroy-output mh-output))
      (log-string :error "Removed an output that was never added"))
    ;; Start the timer:
    (alexandria:if-let ((timer (state-pending-output-timer state)))
      (let ((data (hrt:timer-handle-data timer)))
        (hrt:timer-handle-update timer *output-debounce-msec*)
        ;; We really shouldn't be using pointer-eq here,
        ;;  but it appears to be the best choice right now
        (alexandria:deletef (pending-output-changes-added data)
                            hrt-output
                            :test #'cffi:pointer-eq
                            :key #'hrt:output-hrt-output))
      (setf (state-pending-output-timer state)
            (%make-output-process-timer
             state
             (make-pending-output-changes
              :added (list)))))))

(defun %next-group-name (index)
  "The name of a group made with INDEX and no name: the number itself."
  (princ-to-string index))

(defun state-next-group-name (state &optional (home (state-current-home state)))
  (%next-group-name (%next-group-index state home)))

(defun %output-designator-name-or-none (home)
  (if (eq home :none) :none (%output-designator-name home)))

(defun mahogany-state-group-add (state &key group-name (make-current t) number
                                         (home (or (state-current-home state)
                                                   (and (state-current-group state)
                                                        (mahogany-group-home (state-current-group state))))))
  "Add a group to the output HOME (the focused one by default; :none for
a group never shown, the scratchpad's), named GROUP-NAME (its number by
default), with NUMBER or the lowest number free on that output from 1,
and make it current unless MAKE-CURRENT is NIL."
  (declare (type mahogany-state state))
  (let* ((home (%output-designator-name-or-none home))
         (index (or number (%next-group-index state home))))
    (unless group-name
      (setf group-name (%next-group-name index)))
    (let ((new-group (%add-group state group-name index home)))
      (when (stringp home)
        (alexandria:when-let ((container (find home (state-cur-outputs state)
                                               :key #'%output-designator-name
                                               :test #'string=)))
          (group-add-output new-group container)))
      (if (and make-current (group-attached-p new-group))
          (setf (state-current-group state) new-group)
          (mode-line-update))
      new-group)))

(defun mahogany-state-group-remove (state group)
  "Remove GROUP, its windows going to the group before it on its output,
which is shown in its place. The only group of an output stays."
  (with-accessors ((groups state-groups)) state
    (unless (find group groups :test #'eq)
      (log-string :error "could not find group to delete")
      (return-from mahogany-state-group-remove))
    (let* ((home (mahogany-group-home group))
           (siblings (and (stringp home)
                          (remove group (output-groups state home))))
           (heir (cond ((not (group-attached-p group))
                        (state-current-group state))
                       (siblings
                        (or (car (last (remove-if (lambda (g) (> (mahogany-group-number g)
                                                                  (mahogany-group-number group)))
                                                  siblings)))
                            (first siblings))))))
      (when (or (null heir) (eq heir group))
        (log-string :warn "Cannot remove the only group of ~A" home)
        (return-from mahogany-state-group-remove))
      (cond ((eq group (state-current-group state))
             ;; Deleted below, once its windows have moved:
             (let ((*remove-empty-groups* nil))
               (setf (state-current-group state) heir)))
            ((eq group (state-output-group state home))
             (%show-output-group state heir)))
      (group-transfer-views heir group)
      (%delete-group state group)
      (mode-line-update))))

(defun mahogany-state-output-reconfigure (state)
  (hrt:with-view-transaction ()
    (with-accessors ((groups state-groups)) state
      (loop for g across groups
            do (group-reconfigure-outputs g (state-cur-outputs state)))))
  (wallpaper-update))

(defun mahogany-state-layers-arrange (state output)
  (declare (type mahogany-state state)
           (type tree:output-container output))
  (let ((hrt-output (tree:output-container-output output)))
    (log-string :debug "layer shell layers re-arranged on output ~S"
              (hrt:output-full-name hrt-output))
    (hrt:with-view-transaction ()
      (with-accessors ((groups state-groups)) state
        (loop for g across groups
              do (group-rearrange-output g hrt-output))))))

(defglobal *new-view-hook* '()
  "Functions called with each new view (window) and its group, right
after it is created and before it is shown; the scratchpad adopts the
window it started here, and window rules can be built on it.")

(defun mahogany-state-view-add (state view-ptr)
  (declare (type mahogany-state state)
           (type cffi:foreign-pointer view-ptr))
  (with-accessors ((view-tbl state-views)
                   (current-group state-current-group)
                   (server state-server))
      state
    (let ((new-view (group-add-initialize-view current-group view-ptr)))
      (setf (gethash (cffi:pointer-address view-ptr) view-tbl) new-view)
      (dolist (hook *new-view-hook*)
        (handler-case (funcall hook new-view current-group)
          (error (c)
            (log-string :error "New view hook ~S failed: ~A" hook c))))
      new-view)))

(defun %find-view-in-groups (view groups)
  (find-if (lambda (g) (member view (mahogany-group-views g))) groups))

(defmacro %with-found-group (state (group-var view) &body body)
  `(alexandria:if-let ((,group-var (%find-view-in-groups ,view (state-groups ,state))))
     (progn
       ,@body)
     (log-string :error "Could not find mahogany view in any groups!")))

(defun mahogany-state-view-remove (state view-ptr)
  (declare (type mahogany-state state)
           (type cffi:foreign-pointer view-ptr))
  (with-slots (views groups) state
    (alexandria:if-let ((view (gethash (cffi:pointer-address view-ptr) views)))
      (progn
        (%with-found-group state (group view)
          (group-remove-view group view))
        (view-forget-origin view state)
        (remhash (cffi:pointer-address view-ptr) views))
      (log-string :error "Could not find mahogany view associated with pointer ~S" view-ptr))))

(defun %cur-frame-set-from-group (state group)
  (declare (type mahogany-state state)
           (type mahogany-group group))
  (let ((cur-frame (mahogany-group-current-frame group)))
    (setf (state-%current-frame state) cur-frame)
    (tree:mark-frame-focused cur-frame (server-seat state))))

(defun mahogany-state-view-fullscreen (state view output set-fullscreen)
  (declare (type mahogany-state state)
         (type hrt:view view)
         (type (or null hrt:output) output))
  (%with-found-group state (group view)
    (log-string :debug
                "~@<Fullscreen requested (~:[no~;yes~]):~I ~:_view ~S ~:_on output ~S~:>"
                set-fullscreen view output)
	(group-set-fullscreen group view output set-fullscreen)
    (%cur-frame-set-from-group state group)))

(defun mahogany-state-view-map (state view)
  (declare (type mahogany-state state)
           (type hrt:view view))
  (%with-found-group state (group view)
    (group-map-view group view)
    ;; Mapping the view can cause focus to change:
    (%cur-frame-set-from-group state group)))

(defun mahogany-state-view-unmap (state view)
  (declare (type mahogany-state state)
           (type hrt:view view))
  (%with-found-group state (group view)
    (group-unmap-view group view)
    ;; Unmapping the view can cause focus to change:
    (%cur-frame-set-from-group state group)))

(defun mahogany-state-view-size-changed (state view)
  (declare (type mahogany-state state)
	       (type hrt:view view)
           (ignore state view))
  ;; For now, just check to see if the view is now under the cursor:
  (hrt:dirty-view-transaction)
  ;; TODO: Center the view in its frame if the dimensions do not match. May
  ;;  also need to do something if it's now bigger than the frame:
  )

(defun mahogany-state-view-activate (state view)
  "A client asked for VIEW to be focused (xdg-activation, with a valid
token): give it the focus when *focus-on-activation* says so."
  (declare (type mahogany-state state)
           (type hrt:view view))
  (when *focus-on-activation*
    (mahogany-state-show-view state view)))

(defun mahogany-state-show-view (state view)
  "Make VIEW the focused window: its group becomes current, its frame
focused; hidden behind another window, it is shown in the current frame."
  (declare (type mahogany-state state)
           (type hrt:view view))
  (progn
    (%with-found-group state (group view)
      (unless (or (eq group (state-current-group state))
                  (not (group-attached-p group)))
        (setf (state-current-group state) group))
      (alexandria:if-let ((frame (if (typep (hrt::view-container view) 'tree:floating-frame)
                                     (hrt::view-container view)
                                     (tree:find-view-frame
                                      (mahogany-group-tiled-container group) view))))
        (state-focus-frame state frame (server-seat state))
        ;; Hidden behind another view: show it in the current frame, the
        ;; way next-view does, hiding what that frame showed.
        (let ((hidden (mahogany-group-hidden-views group))
              (cur-frame (mahogany-group-current-frame group)))
          (when (and (typep cur-frame 'tree:view-frame)
                     (ring-list:contains-item hidden view))
            (ring-list:remove-item hidden view)
            (hrt:view-set-hidden view nil)
            (alexandria:when-let ((prev (tree:frame-surface cur-frame)))
              (%add-hidden hidden prev))
            (%swap-view-into-frame group cur-frame view)
            (%cur-frame-set-from-group state group)))))))

(defun mahogany-state-view-maximize (state view)
  (declare (type mahogany-state state)
           (type hrt:view view))
  (%with-found-group state (group view)
    (if (member *follow-config-events* '(:all :maximize))
        (group-maximize-view group view)
        (hrt:view-configure view))))

(defun mahogany-state-view-minimize (state view)
  (declare (type mahogany-state state)
           (type hrt:view view))
  (%with-found-group state (group view)
    (if (member *follow-config-events* '(:all :minimize))
        (group-minimize-view group view)
        (hrt:view-configure view))))

(defun state-next-hidden-frame (state)
  (declare (type mahogany-state state))
  (when (group-frame-p (state-current-frame state))
    (let ((group (state-current-group state)))
      (group-next-hidden group)
      (%cur-frame-set-from-group state group))))

(defun state-prev-hidden-frame (state)
  (declare (type mahogany-state state))
  (when (group-frame-p (state-current-frame state))
    (let ((group (state-current-group state)))
      (group-previous-hidden group)
      (%cur-frame-set-from-group state group))))

(config-system:defconfig grab-pointer-cursor "help"
  string
  "The cursor image to use for the grab pointer.")

(defun state-remove-cur-group-frame (state)
  (declare (type mahogany-state state))
  (when (group-frame-p (state-current-frame state))
    (let ((cur-group (state-current-group state)))
      (group-remove-current-frame cur-group)
      (%cur-frame-set-from-group state cur-group))))

(defun state-grab-seat (state)
  (declare (type mahogany-state state))
  (let ((seat (server-seat state)))
    (unless (hrt:seat-grabbed-p seat)
      (tree:unmark-frame-focused (state-%current-frame state)
                                 seat)
      (hrt:seat-grab seat grab-pointer-cursor))))

(defun state-ungrab-seat (state)
  (declare (type mahogany-state state))
  (let ((seat (server-seat state)))
    (hrt:hrt-seat-ungrab seat)
    (tree:mark-frame-focused (state-%current-frame state)
                             seat)))

(defun state-set-cursor-theme (state theme-name &optional (cursor-size 24))
  (declare (type mahogany-state state))
  (hrt:seat-cursor-set-theme (server-seat state)
									   theme-name
                                       cursor-size))

(defun mahogany-set-keymap (state &key (rules (cffi:null-pointer)) (keymap-flags :no-flags))
  "Set the xkb keymap using the provided rules and flags. Signals a
KEYMAP-CREATION-ERROR if the rules are invalid or malformed."
  (let* ((seat (hrt:hrt-server-seat (state-server state)))
	 (success (hrt:hrt-seat-set-keymap seat rules keymap-flags)))
    (unless success
      ;; TODO: register with xkb's logging handling to get
      ;; some sort of usable error message?
      ;; Either that, or just turn this into a warning or return a boolean?
      (error 'xkb:keymap-creation-error))))

(declaim (ftype (function (mahogany-state cffi:foreign-pointer) (or null hrt:output))
                %get-or-autoassign-output))
(defun %get-or-autoassign-output (state hrt-layer-shell)
  (declare (type mahogany-state state))
  (alexandria:if-let ((hrt-output (hrt:hrt-layer-surface-output hrt-layer-shell)))
    (%find-output hrt-output state)
    (let ((current-output (group-current-output (state-current-group state))))
      ;; TODO: try to use the fallback output:
      (unless current-output
	    (log-string :error "Could not auto-assign output to layer surface")
	    (return-from %get-or-autoassign-output nil))
      (hrt:hrt-layer-shell-surface-set-output hrt-layer-shell
                                              (hrt:output-hrt-output current-output))
      current-output)))

(defun mahogany-state-layer-shell-handle (state hrt-layer-shell)
  (declare (type mahogany-state state))
  (alexandria:if-let ((output (%get-or-autoassign-output state hrt-layer-shell)))
    (progn
      (hrt:layer-shell-surface-place hrt-layer-shell
                                     output)
      (hrt:hrt-layer-shell-finish-init hrt-layer-shell))
    (hrt:hrt-layer-shell-surface-abort hrt-layer-shell)))

(defun state-layer-surface-add (state hrt-layer-surface)
  (declare (type mahogany-state state))
  (let* ((surfaces (state-layer-surfaces state))
         (new-surface (hrt:make-layer-surface hrt-layer-surface))
         (interactivity (hrt:layer-surface-keyboard-interactivity new-surface)))
    (setf (gethash (cffi:pointer-address hrt-layer-surface) surfaces) new-surface)
    (alexandria:if-let ((output-container (%find-output-container
                                           (hrt:layer-surface-output new-surface)
                                           state)))
      (progn
        (log-string
         :info
         "New Layer surface on output ~S~%, layer ~S with keyboard ~S keyboard"
         (tree::output-container-output output-container)
         (hrt::layer-surface-layer new-surface)
         interactivity)
        ;; If the surface can't be focused, don't do anything to place it.
        ;; Otherwise, add it to the tree data structure so we can navigate
        ;; to it by keyboard. The only difference between exclusive and
        ;; "on demand" surfaces is that we focus exclusive surfaces when
        ;; they appear.
        ;; We need to do something different
        ;; in the future for bottom or background surfaces.
        (unless (eq :layer-shell-keyboard-none interactivity)
          (let ((add-node (tree::output-container-add-layer-shell output-container new-surface)))
            (when (eq :layer-shell-keyboard-exclusive interactivity)
              (state-focus-frame state add-node (server-seat state))))))
      (log-string :debug "Layer surface mapped on an output we don't track"))))

(defun state-layer-surface-remove (state hrt-layer-surface)
  (declare (type mahogany-state state))
  (let ((surfaces (state-layer-surfaces state))
        (surface-ptr (cffi:pointer-address hrt-layer-surface)))
    (alexandria:if-let ((surface (gethash surface-ptr surfaces)))
      (let* ((output-container (%find-output-container
                                (hrt:layer-surface-output surface)
                                state))
             (removed-frame (when output-container
                              (tree::output-container-remove-layer-shell
                               output-container surface))))
        (when (and removed-frame (eq (state-current-frame state) removed-frame))
          (state-focus-frame state (mahogany-group-current-frame
                                    (state-current-group state))
                             (server-seat state)))
        (remhash surface-ptr surfaces))
      (log-string :error "Unmapping layer surface that was never mapped"))))
