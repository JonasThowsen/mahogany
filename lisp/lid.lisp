(in-package #:mahogany)

;;; The laptop lid. heart reports the lid switch (and tablet mode) of
;;; libinput; here the lid closing locks the session, or does what
;;; *lid-close-action* says, and with an external monitor connected
;;; the internal screen is switched off so the external one is the
;;; only one, the windows moving over; opening the lid brings the
;;; internal screen and its windows back. Suspending is left to
;;; systemd-logind (HandleLidSwitch), which also knows to do nothing
;;; while docked.

(config:defconfig *lid-close-action* :lock
  (or (member :lock :nothing) function)
  "What closing the lid does when the built-in screen is the only one:
:lock the session, :nothing, or a function of no arguments. With an
external monitor connected the lid only switches screens, unless
*lid-close-action-docked* says otherwise.")

(config:defconfig *lid-close-action-docked* :nothing
  (or (member :lock :nothing) function)
  "What closing the lid does when an external monitor is connected and
takes over (see *lid-switch-outputs*): :nothing by default, since the
session goes on there; :lock, or a function of no arguments.")

(config:defconfig *lid-switch-outputs* t
  boolean
  "Whether closing the lid with an external monitor connected turns the
internal screen off, moving its windows to the external one, and
opening it turns the screen on again.")

(config:defconfig *internal-output-names* '("eDP" "LVDS" "DSI")
  list
  "Prefixes of the names of built-in screens, those the lid covers.")

(defglobal *lid-closed* nil
  "Whether the lid is closed, as far as heart has told.")

(defglobal *lid-disabled-outputs* '()
  "The names of the outputs the lid closing switched off, to switch on
again when it opens.")

(defglobal *lid-hooks* '()
  "Functions called with :closed or :opened when the lid moves.")

(defun internal-output-p (output)
  "Whether OUTPUT is a built-in screen (*internal-output-names*)."
  (let ((name (hrt:output-name output)))
    (some (lambda (prefix) (alexandria:starts-with-subseq prefix name))
          *internal-output-names*)))

(defun %all-outputs ()
  "Every output known, enabled or not."
  (coerce (state-outputs *compositor-state*) 'list))

(defun %output-named (full-name)
  (find full-name (%all-outputs) :key #'hrt:output-full-name :test #'string=))

(defun %set-output-enabled (output enabled)
  "Turn OUTPUT on or off and let the groups follow: their frame trees
on it go (the windows moving to another output) or come back."
  (let ((state *compositor-state*))
    (hrt:output-configure output (hrt:make-output-config :enabled enabled))
    (hrt:with-view-transaction ()
      (%update-output-enabled state output)
      ;; The windows of a screen that went off wait hidden: show them
      ;; where the groups now are, and let the layouts place them.
      (loop for group across (state-groups state)
            do (%fill-frame-from-hidden group (mahogany-group-current-frame group))
               (group-views-changed group)))
    (hrt:dirty-view-transaction)
    (mode-line-update)
    (wallpaper-update)))

(defun %lid-act (action)
  (etypecase action
    ((eql :lock) (lock-session))
    ((eql :nothing) nil)
    (function (funcall action))))

(defun lid-closed ()
  "What happens when the lid closes: docked (an external monitor there
to take over), the built-in screen goes off and *lid-close-action-docked*
runs; alone, *lid-close-action* runs."
  (setf *lid-closed* t)
  (let* ((outputs (%all-outputs))
         (internal (remove-if-not #'internal-output-p outputs))
         (external (remove-if #'internal-output-p outputs))
         (docked (and internal external)))
    (when (and *lid-switch-outputs* docked)
      (dolist (output internal)
        (log-string :info "Lid closed: switching ~A off" (hrt:output-name output))
        (pushnew (hrt:output-full-name output) *lid-disabled-outputs* :test #'string=)
        (%set-output-enabled output nil)))
    (%lid-act (if docked *lid-close-action-docked* *lid-close-action*))
    (dolist (hook *lid-hooks*)
      (funcall hook :closed))))

(defun lid-opened ()
  "What happens when the lid opens: the screens it switched off come
back."
  (setf *lid-closed* nil)
  (dolist (name *lid-disabled-outputs*)
    (alexandria:when-let ((output (%output-named name)))
      (log-string :info "Lid opened: switching ~A on" (hrt:output-name output))
      (%set-output-enabled output t)))
  (setf *lid-disabled-outputs* '())
  (dolist (hook *lid-hooks*)
    (funcall hook :opened)))

(defconstant +switch-lid+ 1)
(defconstant +switch-tablet-mode+ 2)

(hrt:define-hrt-callback handle-switch-event :void
    ((seat :pointer)
     (switch-type :int)
     (on :bool))
    ()
  (declare (ignore seat))
  (cond ((= switch-type +switch-lid+)
         (handler-case (if on (lid-closed) (lid-opened))
           (error (c)
             (log-string :error "Lid handling failed: ~A" c))))
        (t
         (log-string :debug "Switch ~D is now ~A" switch-type (if on "on" "off")))))

(defcommand lid-close ()
  (:documentation "Do what closing the lid does (to try it)")
  (:method () (lid-closed)))

(defcommand lid-open ()
  (:documentation "Do what opening the lid does")
  (:method () (lid-opened)))
