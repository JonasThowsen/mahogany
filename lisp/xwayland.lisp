(in-package #:mahogany)

;;; X11 programs, through xwayland-satellite: it runs Xwayland rootless
;;; as an ordinary Wayland client of Mahogany, and every X11 window
;;; comes in as an xdg-shell toplevel, tiled like the rest. Mahogany
;;; starts it with the session and sets DISPLAY for the programs it
;;; starts (and for systemd's user services and D-Bus activation, so
;;; programs started elsewhere find it too). It watches the process:
;;; what it prints goes to a log of its own, and when it dies it is
;;; started again, a few times, so DISPLAY keeps pointing at something.

(config:defconfig *xwayland* :auto
  (member t nil :auto)
  "Whether to run xwayland-satellite for X11 programs: T, NIL, or :auto
for when it is installed.")

(config:defconfig *xwayland-display* ":0"
  string
  "The X display xwayland-satellite serves, and DISPLAY for programs.")

(config:defconfig *xwayland-restarts* 5
  (integer 0 100)
  "How many times xwayland-satellite is started again after it died;
the count starts over once it has run for a minute.")

(defglobal *xwayland-process* nil
  "The xwayland-satellite process, or NIL.")

(defglobal *xwayland-watch* nil
  "A plist (:timer TIMER :started TIME :restarts N) while the process
is watched.")

(defun xwayland-log-file ()
  "Where xwayland-satellite's output goes: next to the session log, in
$XDG_STATE_HOME/mahogany (~/.local/state/mahogany)."
  (let* ((state (uiop:ensure-directory-pathname
                 (or (uiop:getenvp "XDG_STATE_HOME")
                     (merge-pathnames ".local/state/" (user-homedir-pathname)))))
         (dir (merge-pathnames "mahogany/" state)))
    (ensure-directories-exist dir)
    (merge-pathnames "xwayland-satellite.log" dir)))

(defun %setenv (name value)
  "Set NAME to VALUE in this process's environment, which the programs
it starts inherit."
  #+sbcl (sb-posix:setenv name value 1)
  #-sbcl (setf (uiop:getenv name) value)
  value)

(defun %update-activation-environment (&rest names)
  "Tell systemd --user and the session D-Bus the values of the
environment variables NAMES, so services and activated programs get
them."
  (when (mahogany/system:find-program "dbus-update-activation-environment")
    (handler-case
        (uiop:launch-program (list* "dbus-update-activation-environment" "--systemd" names))
      (error (c)
        (log-string :warn "Could not update the activation environment: ~A" c)))))

(defun %xwayland-wanted-p ()
  (if (eq *xwayland* :auto)
      (mahogany/system:find-program "xwayland-satellite")
      *xwayland*))

(defun %xwayland-launch ()
  "Start the process, its output appended to the log file. Returns it,
or NIL."
  (handler-case
      (let* ((log (uiop:native-namestring (xwayland-log-file)))
             (process (progn
                        ;; Appending wants the file there already:
                        (with-open-file (s log :direction :output
                                               :if-exists :append :if-does-not-exist :create)
                          (format s "~&--- xwayland-satellite ~A started by Mahogany~%" *xwayland-display*))
                        (uiop:launch-program (list "xwayland-satellite" *xwayland-display*)
                                             :output log :if-output-exists :append
                                             :error-output :output))))
        (setf *xwayland-process* process)
        (%setenv "DISPLAY" *xwayland-display*)
        (%update-activation-environment "DISPLAY" "WAYLAND_DISPLAY")
        (log-string :info "xwayland-satellite started on ~A (pid ~D, log ~A)"
                    *xwayland-display* (uiop:process-info-pid process) log)
        process)
    (error (c)
      (log-string :error "Could not start xwayland-satellite: ~A" c)
      nil)))

(defun %xwayland-check (timer)
  "The watch: every few seconds, is the process still there? Dead, it
is started again, unless it died *xwayland-restarts* times within a
minute of starting."
  (let ((process *xwayland-process*)
        (watch *xwayland-watch*))
    (cond
      ((null watch)
       (hrt:timer-handle-destroy timer))
      ((and process (uiop:process-alive-p process))
       ;; Alive for a minute: a crash now is a new story.
       (when (> (- (get-universal-time) (getf watch :started)) 60)
         (setf (getf watch :restarts) 0))
       (hrt:timer-handle-update timer 3000))
      (t
       (let ((code (and process (ignore-errors (uiop:wait-process process))))
             (restarts (getf watch :restarts)))
         (setf *xwayland-process* nil)
         (cond
           ((< restarts *xwayland-restarts*)
            (log-string :warn "xwayland-satellite died (exit ~A): starting it again (~D of ~D), see ~A"
                        code (1+ restarts) *xwayland-restarts* (xwayland-log-file))
            (setf (getf watch :restarts) (1+ restarts)
                  (getf watch :started) (get-universal-time))
            (%xwayland-launch)
            (hrt:timer-handle-update timer 3000))
           (t
            (log-string :error "xwayland-satellite died (exit ~A) ~D times: giving up; xwayland-restart starts it again"
                        code restarts)
            (ignore-errors
             (toast-message *compositor-state* "xwayland-satellite keeps dying; see the log"
                            :theme *message-error-theme*))
            (setf *xwayland-watch* nil)
            (hrt:timer-handle-destroy timer))))))))

(defun start-xwayland ()
  "Start xwayland-satellite on *xwayland-display*, set DISPLAY and watch
it, when *xwayland* says so. Returns the process, or NIL."
  (when (%xwayland-wanted-p)
    (stop-xwayland-watch)
    (prog1 (%xwayland-launch)
      (when *xwayland-process*
        (let ((timer (hrt:server-make-timer (state-server *compositor-state*) #'%xwayland-check)))
          (setf *xwayland-watch* (list :timer timer :started (get-universal-time) :restarts 0))
          (hrt:timer-handle-update timer 3000))))))

(defun stop-xwayland-watch ()
  "Stop watching the process (it goes on running)."
  (alexandria:when-let ((watch *xwayland-watch*))
    (setf *xwayland-watch* nil)
    (hrt:timer-handle-destroy (getf watch :timer))))

(defcommand xwayland-restart ()
  (:documentation "Start xwayland-satellite (again), for X11 programs")
  (:method ()
    (when (and *xwayland-process* (uiop:process-alive-p *xwayland-process*))
      (uiop:terminate-process *xwayland-process*))
    (if (start-xwayland)
        (toast-message *compositor-state* (format nil "xwayland-satellite started on ~A" *xwayland-display*))
        (toast-message *compositor-state* "xwayland-satellite is not installed, or would not start"
                       :theme *message-error-theme*))))
