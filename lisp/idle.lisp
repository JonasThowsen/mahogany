(in-package #:mahogany)

;;; Idle policy: what happens when there has been no input for a while,
;;; like swayidle or hypridle, but configured in Lisp. heart keeps the
;;; timeouts and knows about idle inhibitors (a video playing); this
;;; decides what to do.

(config:defconfig *idle-enabled* t
  boolean
  "Whether the idle timeouts run. The toggle-idle command flips it.")

(config:defconfig *idle-timeouts* '((300 :lock) (600 :screen-off))
  list
  "What to do after how many seconds without input: a list of (SECONDS
ACTION). ACTION is :lock (run *idle-lock-command* unless the session is
locked), :screen-off (turn the outputs off until the next input), a
string (a shell command to run), or a function called with :idle when
the time is up and :resume at the next input. Set it in init.lisp;
restart-idle applies a change.")

(config:defconfig *idle-lock-command* "swaylock -f"
  string
  "The shell command that locks the session, for the :lock action and the
lock-session command. It should lock through ext-session-lock.")

(defglobal *idle-handles* '()
  "The hrt:idle-timeout handles of the running policy.")

(defun lock-session-now ()
  "Run the lock command, unless the session is locked already."
  (if (state-locked-p *compositor-state*)
      (log-string :debug "Not locking: the session is locked")
      (progn
        (log-string :info "Locking the session: ~A" *idle-lock-command*)
        (uiop:launch-program *idle-lock-command*))))

(defun %outputs-set-power (on)
  (loop for container across (state-cur-outputs *compositor-state*)
        for output = (tree:output-container-output container)
        do (log-string :info "Turning output ~A ~:[off~;on~]"
                       (hrt:output-full-name output) on)
           (hrt:output-set-power output on)))

(defun %idle-action (action phase)
  "Carry out ACTION for PHASE, :idle or :resume."
  (handler-case
      (etypecase action
        ((eql :lock) (when (eq phase :idle) (lock-session-now)))
        ((eql :screen-off) (%outputs-set-power (eq phase :resume)))
        (string (when (eq phase :idle) (uiop:launch-program action)))
        ((or function symbol) (funcall action phase)))
    (error (c)
      (log-string :error "Idle action ~S (~A): ~A" action phase c))))

(defun stop-idle ()
  "Remove the idle timeouts."
  (mapc #'hrt:destroy-idle-timeout *idle-handles*)
  (setf *idle-handles* '()))

(defun start-idle ()
  "Put the idle timeouts of *idle-timeouts* in place, replacing those
running."
  (stop-idle)
  (when *idle-enabled*
    (let ((server (state-server *compositor-state*)))
      (dolist (entry *idle-timeouts*)
        (destructuring-bind (seconds action) entry
          (check-type seconds (real (0)))
          (push (hrt:add-idle-timeout
                 server (round (* seconds 1000))
                 (lambda (timeout)
                   (declare (ignore timeout))
                   (log-string :info "Idle for ~A s: ~S" seconds action)
                   (%idle-action action :idle))
                 (lambda (timeout)
                   (declare (ignore timeout))
                   (log-string :info "Input after idling: ~S resumes" action)
                   (%idle-action action :resume)))
                *idle-handles*))))))

(defcommand restart-idle ()
  (:documentation "Apply the idle settings")
  (:method ()
    (start-idle)))

(defcommand toggle-idle ()
  (:documentation "Turn idling (locking, screens off) off, or on again")
  (:method ()
    (setf *idle-enabled* (not *idle-enabled*))
    (start-idle)
    (toast-message *compositor-state*
                   (if *idle-enabled* "Idle timeouts on" "Idle timeouts off"))))

(defcommand lock-session ()
  (:documentation "Lock the session now")
  (:method ()
    (lock-session-now)))
