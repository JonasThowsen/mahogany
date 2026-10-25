(in-package #:mahogany)

;;; X11 programs, through xwayland-satellite: it runs Xwayland rootless
;;; as an ordinary Wayland client of Mahogany, and every X11 window
;;; comes in as an xdg-shell toplevel, tiled like the rest. Mahogany
;;; starts it with the session and sets DISPLAY for the programs it
;;; starts (and for systemd's user services and D-Bus activation, so
;;; programs started elsewhere find it too).

(config:defconfig *xwayland* :auto
  (member t nil :auto)
  "Whether to run xwayland-satellite for X11 programs: T, NIL, or :auto
for when it is installed.")

(config:defconfig *xwayland-display* ":0"
  string
  "The X display xwayland-satellite serves, and DISPLAY for programs.")

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

(defun start-xwayland ()
  "Start xwayland-satellite on *xwayland-display* and set DISPLAY,
when *xwayland* says so. Returns the process, or NIL."
  (let ((wanted (if (eq *xwayland* :auto)
                    (mahogany/system:find-program "xwayland-satellite")
                    *xwayland*)))
    (when wanted
      (handler-case
          (let ((process (uiop:launch-program (list "xwayland-satellite" *xwayland-display*)
                                              :output nil :error-output nil)))
            (%setenv "DISPLAY" *xwayland-display*)
            (%update-activation-environment "DISPLAY" "WAYLAND_DISPLAY")
            (log-string :info "xwayland-satellite started on ~A" *xwayland-display*)
            process)
        (error (c)
          (log-string :error "Could not start xwayland-satellite: ~A" c)
          nil)))))
