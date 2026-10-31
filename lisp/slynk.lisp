(in-package #:mahogany)

;;; Slynk in the session: Emacs with SLY, or anything else that speaks
;;; Slynk's protocol, connects to the running compositor and evaluates,
;;; compiles and redefines in it, the way the lisp command does in a
;;; development image. Off unless asked for: whoever connects has the
;;; user's shell.

(config:defconfig *slynk-port* nil
  (or null (integer 0 65535))
  "The port Slynk listens on, on 127.0.0.1 only, for SLY (M-x
sly-connect) and the lisp command; 0 takes a free port, NIL leaves
Slynk off. Set it in init.lisp (the server starts once the file has
loaded) or with --slynk PORT on the command line. The port in use is
written to $XDG_RUNTIME_DIR/mahogany/slynk-port. A connection has
full access to the session, as a shell has.")

(defvar *slynk-listening* nil
  "The port Slynk listens on while it runs, NIL otherwise.")

(defun %slynk-port-file ()
  "Where the port in use is written: $XDG_RUNTIME_DIR/mahogany/slynk-port,
NIL without a runtime directory."
  (let ((dir (uiop:getenv "XDG_RUNTIME_DIR")))
    (and dir (plusp (length dir))
         (merge-pathnames "mahogany/slynk-port" (uiop:ensure-directory-pathname dir)))))

(defun %slynk-create-server (port)
  "Slynk on PORT, or on a free port when PORT is taken; the port it
listens on, or NIL with the error logged."
  (handler-case (slynk:create-server :port port :dont-close t)
    (error (c)
      (cond ((zerop port)
             (log-string :error "Could not start Slynk: ~A" c)
             nil)
            (t
             (log-string :warn "Could not start Slynk on port ~D (~A): taking a free port"
                         port c)
             (%slynk-create-server 0))))))

(defun start-slynk (&optional (port *slynk-port*))
  "Start Slynk on PORT (0: a free port), on 127.0.0.1, and return the
port it listens on; NIL when it could not start. Already running, it
stays as it is."
  (or *slynk-listening*
      (progn
        ;; Connected, Slynk would otherwise make its debugger every
        ;; thread's, and an error in a wlroots callback would wait for
        ;; Emacs with the session frozen. %recover-from-error keeps the
        ;; main thread; Slynk's debugger serves its own threads, where
        ;; SLY's evaluations run.
        (setf slynk:*global-debugger* nil)
        (let ((listening (%slynk-create-server (or port 0))))
          (when listening
            (setf *slynk-listening* listening)
            (alexandria:when-let ((file (%slynk-port-file)))
              (handler-case
                  (progn
                    (ensure-directories-exist file)
                    (with-open-file (s file :direction :output :if-exists :supersede)
                      (format s "~D~%" listening)))
                (error (c) (log-string :warn "Could not write ~A: ~A" file c))))
            (log-string :info "Slynk listens on 127.0.0.1:~D (M-x sly-connect in Emacs)"
                        listening))
          listening))))

(defun stop-slynk ()
  "Stop listening for new Slynk connections; the ones open stay open."
  (when *slynk-listening*
    (ignore-errors (slynk:stop-server *slynk-listening*))
    (alexandria:when-let ((file (%slynk-port-file)))
      (ignore-errors (when (probe-file file) (delete-file file))))
    (log-string :info "Slynk stopped listening on port ~D" *slynk-listening*)
    (setf *slynk-listening* nil)))

(defcommand slynk-start ()
  (:documentation "Let SLY and the lisp command connect to this session (Slynk on 127.0.0.1)")
  (:method ()
    (let ((port (start-slynk (or *slynk-port* 0))))
      (toast-message *compositor-state*
                     (if port
                         (format nil "Slynk listens on 127.0.0.1:~D~%(M-x sly-connect in Emacs)" port)
                         "Slynk could not start, see the log")
                     :theme (if port *message-theme* *message-error-theme*)))))

(defcommand slynk-stop ()
  (:documentation "Stop accepting Slynk connections")
  (:method ()
    (let ((port *slynk-listening*))
      (stop-slynk)
      (toast-message *compositor-state*
                     (if port (format nil "Slynk stopped (port ~D)" port) "Slynk was not running")))))

;;; From a Slynk thread, or any other, the compositor's state is only
;;; safe to touch on the main thread. hrt:with-main-thread hands a form
;;; there without waiting; this waits and returns its values, so that
;;; at a SLY REPL (in-main-thread (state-current-group *compositor-state*))
;;; answers like a plain form.

(defun call-in-main-thread (function &key (timeout 10))
  "Call FUNCTION on the main thread and return its values; an error
there is signalled here. On the main thread already, call it at once.
After TIMEOUT seconds without an answer (the main thread is paused, or
busy), an error says so."
  (if (sb-thread:main-thread-p)
      (funcall function)
      (let ((semaphore (sb-thread:make-semaphore))
            (values nil)
            (condition nil))
        (hrt:with-main-thread ()
          (handler-case (setf values (multiple-value-list (funcall function)))
            (error (c) (setf condition c)))
          (sb-thread:signal-semaphore semaphore))
        (unless (sb-thread:wait-on-semaphore semaphore :timeout timeout)
          (error "The main thread did not answer within ~D s" timeout))
        (if condition
            (error condition)
            (values-list values)))))

(defmacro in-main-thread (&body body)
  "Evaluate BODY on the main thread and return its values; see
call-in-main-thread."
  `(call-in-main-thread (lambda () ,@body)))
