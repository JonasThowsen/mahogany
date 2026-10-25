(in-package #:hrt)

;;; Idle timeouts of the compositor's own (hrt_idle.h): a function when
;;; there has been no input for a while, another at the next input.

(defstruct (idle-timeout (:constructor %make-idle-timeout (pointer msec idle resume)))
  (pointer (cffi:null-pointer) :type cffi:foreign-pointer)
  (msec 0 :type (unsigned-byte 32) :read-only t)
  (idle nil :type function :read-only t)
  (resume nil :type (or null function) :read-only t))

(declaim (type hash-table *idle-timeouts*))
(mahogany/util::defglobal *idle-timeouts* (make-hash-table)
  "The live idle timeouts, by the address of their hrt_idle_timeout.")

(define-hrt-callback %idle-timeout-idle :void
    ((timeout :pointer)
     (data :pointer))
    ()
  (declare (ignore data))
  (alexandria:when-let ((handle (gethash (cffi:pointer-address timeout) *idle-timeouts*)))
    (funcall (idle-timeout-idle handle) handle)))

(define-hrt-callback %idle-timeout-resume :void
    ((timeout :pointer)
     (data :pointer))
    ()
  (declare (ignore data))
  (alexandria:when-let ((handle (gethash (cffi:pointer-address timeout) *idle-timeouts*)))
    (alexandria:when-let ((resume (idle-timeout-resume handle)))
      (funcall resume handle))))

(defun add-idle-timeout (server msec idle &optional resume)
  "Call IDLE with the timeout when there has been no input for MSEC
milliseconds, and RESUME with it at the first input after that; both
run on the main thread. Input restarts the wait, and while a visible
client inhibits idling the wait does not run out. Returns the timeout,
for destroy-idle-timeout."
  (declare (type (unsigned-byte 32) msec)
           (type function idle)
           (type (or null function) resume))
  (let ((pointer (hrt-idle-timeout-add server msec
                                       (cffi:callback %idle-timeout-idle)
                                       (cffi:callback %idle-timeout-resume)
                                       (cffi:null-pointer))))
    (when (cffi:null-pointer-p pointer)
      (error 'mahogany/util:mahogany-panic :text "Could not add an idle timeout"))
    (let ((handle (%make-idle-timeout pointer msec idle resume)))
      (setf (gethash (cffi:pointer-address pointer) *idle-timeouts*) handle)
      handle)))

(defun destroy-idle-timeout (timeout)
  "Remove TIMEOUT; harmless when it is gone already."
  (declare (type idle-timeout timeout))
  (unless (cffi:null-pointer-p (idle-timeout-pointer timeout))
    (remhash (cffi:pointer-address (idle-timeout-pointer timeout)) *idle-timeouts*)
    (hrt-idle-timeout-destroy (idle-timeout-pointer timeout))
    (setf (idle-timeout-pointer timeout) (cffi:null-pointer))))

(defun idle-milliseconds (server)
  "Milliseconds since the last input."
  (hrt-idle-milliseconds server))

(defun idle-inhibited-p (server)
  "Whether a visible client asks that the user not be considered idle."
  (hrt-idle-inhibited server))

(defun idle-activity (server)
  "Count as input: restart the timeouts, run the resume functions due."
  (hrt-idle-activity server))
