(in-package #:mahogany)

;;; Desktop notifications: Mahogany is the org.freedesktop.Notifications
;;; service of the session, through sd-bus (libsystemd), whose socket
;;; is read from the compositor's own event loop; nothing runs on
;;; another thread. Notifications are drawn on a canvas at a corner of
;;; the current output, go away after a timeout or a click, and are
;;; kept in a history. notify-send and every program that notifies
;;; through D-Bus works; mako is not needed.

;;; sd-bus

(cffi:define-foreign-library libsystemd
  (:unix (:or "libsystemd.so.0" "libsystemd.so"))
  (t (:default "libsystemd")))

(defun %load-libsystemd ()
  (unless (cffi:foreign-library-loaded-p 'libsystemd)
    (cffi:use-foreign-library libsystemd)))

(cffi:defcfun ("sd_bus_open_user" sd-bus-open-user) :int (ret :pointer))
(cffi:defcfun ("sd_bus_request_name" sd-bus-request-name) :int
  (bus :pointer) (name :string) (flags :uint64))
(cffi:defcfun ("sd_bus_get_fd" sd-bus-get-fd) :int (bus :pointer))
(cffi:defcfun ("sd_bus_process" sd-bus-process) :int (bus :pointer) (ret :pointer))
(cffi:defcfun ("sd_bus_flush" sd-bus-flush) :int (bus :pointer))
(cffi:defcfun ("sd_bus_close" sd-bus-close) :void (bus :pointer))
(cffi:defcfun ("sd_bus_unref" sd-bus-unref) :pointer (bus :pointer))
(cffi:defcfun ("sd_bus_add_filter" sd-bus-add-filter) :int
  (bus :pointer) (slot :pointer) (callback :pointer) (userdata :pointer))
(cffi:defcfun ("sd_bus_message_is_method_call" sd-bus-message-is-method-call) :int
  (m :pointer) (interface :string) (member :string))
(cffi:defcfun ("sd_bus_message_get_path" sd-bus-message-get-path) :string (m :pointer))
(cffi:defcfun ("sd_bus_message_get_member" sd-bus-message-get-member) :string (m :pointer))
(cffi:defcfun ("sd_bus_message_get_sender" sd-bus-message-get-sender) :string (m :pointer))
(cffi:defcfun ("sd_bus_message_read_basic" sd-bus-message-read-basic) :int
  (m :pointer) (type :char) (p :pointer))
(cffi:defcfun ("sd_bus_message_enter_container" sd-bus-message-enter-container) :int
  (m :pointer) (type :char) (contents :string))
(cffi:defcfun ("sd_bus_message_exit_container" sd-bus-message-exit-container) :int (m :pointer))
(cffi:defcfun ("sd_bus_message_skip" sd-bus-message-skip) :int (m :pointer) (types :string))
(cffi:defcfun ("sd_bus_message_peek_type" sd-bus-message-peek-type) :int
  (m :pointer) (type :pointer) (contents :pointer))
(cffi:defcfun ("sd_bus_message_new_method_return" sd-bus-message-new-method-return) :int
  (m :pointer) (ret :pointer))
(cffi:defcfun ("sd_bus_message_new_signal" sd-bus-message-new-signal) :int
  (bus :pointer) (ret :pointer) (path :string) (interface :string) (member :string))
(cffi:defcfun ("sd_bus_message_append_basic" sd-bus-message-append-basic) :int
  (m :pointer) (type :char) (p :pointer))
(cffi:defcfun ("sd_bus_message_open_container" sd-bus-message-open-container) :int
  (m :pointer) (type :char) (contents :string))
(cffi:defcfun ("sd_bus_message_close_container" sd-bus-message-close-container) :int (m :pointer))
(cffi:defcfun ("sd_bus_send" sd-bus-send) :int (bus :pointer) (m :pointer) (cookie :pointer))
(cffi:defcfun ("sd_bus_message_unref" sd-bus-message-unref) :pointer (m :pointer))

(defun %type-char (char) (char-code char))

(defun %read-string (m)
  "The next string argument of M, or NIL."
  (cffi:with-foreign-object (p :pointer)
    (when (plusp (sd-bus-message-read-basic m (%type-char #\s) p))
      (cffi:foreign-string-to-lisp (cffi:mem-ref p :pointer)))))

(defun %read-number (m char type)
  (cffi:with-foreign-object (p type)
    (when (plusp (sd-bus-message-read-basic m (%type-char char) p))
      (cffi:mem-ref p type))))

(defun %read-string-array (m)
  (let ((strings '()))
    (when (plusp (sd-bus-message-enter-container m (%type-char #\a) "s"))
      (loop for string = (%read-string m)
            while string do (push string strings))
      (sd-bus-message-exit-container m))
    (nreverse strings)))

(defun %read-hints (m)
  "The hints of a Notify call as an alist of the ones understood:
urgency (0 low, 1 normal, 2 critical); the rest are skipped."
  (let ((hints '()))
    (when (plusp (sd-bus-message-enter-container m (%type-char #\a) "{sv}"))
      (loop while (plusp (sd-bus-message-enter-container m (%type-char #\e) "sv"))
            do (let ((key (%read-string m)))
                 (cond ((and (equal key "urgency")
                             (plusp (sd-bus-message-enter-container m (%type-char #\v) "y")))
                        (push (cons :urgency (%read-number m #\y :uint8)) hints)
                        (sd-bus-message-exit-container m))
                       (t (sd-bus-message-skip m "v")))
                 (sd-bus-message-exit-container m)))
      (sd-bus-message-exit-container m))
    hints))

(defun %append-string (m string)
  ;; For 's', append_basic takes the char* itself (read_basic gives a char**):
  (cffi:with-foreign-string (s string)
    (sd-bus-message-append-basic m (%type-char #\s) s)))

(defun %append-uint32 (m n)
  (cffi:with-foreign-object (p :uint32)
    (setf (cffi:mem-ref p :uint32) n)
    (sd-bus-message-append-basic m (%type-char #\u) p)))

(defmacro %with-reply ((reply m) &body body)
  "Build a method return for M in BODY and send it."
  `(cffi:with-foreign-object (ret :pointer)
     (when (>= (sd-bus-message-new-method-return ,m ret) 0)
       (let ((,reply (cffi:mem-ref ret :pointer)))
         (unwind-protect (progn ,@body (sd-bus-send (cffi:null-pointer) ,reply (cffi:null-pointer)))
           (sd-bus-message-unref ,reply))))))

;;; The service

(defglobal *notification-bus* nil "The sd_bus connection, or NIL.")
(defglobal *notification-bus-source* nil "Its event source in the loop.")

(alexandria:define-constant +notifications-path+ "/org/freedesktop/Notifications" :test (function string=))
(alexandria:define-constant +notifications-interface+ "org.freedesktop.Notifications" :test (function string=))

(defparameter *notifications-introspection*
  "<node><interface name=\"org.freedesktop.Notifications\">
<method name=\"Notify\"><arg type=\"s\" direction=\"in\"/><arg type=\"u\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/><arg type=\"as\" direction=\"in\"/><arg type=\"a{sv}\" direction=\"in\"/><arg type=\"i\" direction=\"in\"/><arg type=\"u\" direction=\"out\"/></method>
<method name=\"CloseNotification\"><arg type=\"u\" direction=\"in\"/></method>
<method name=\"GetCapabilities\"><arg type=\"as\" direction=\"out\"/></method>
<method name=\"GetServerInformation\"><arg type=\"s\" direction=\"out\"/><arg type=\"s\" direction=\"out\"/><arg type=\"s\" direction=\"out\"/><arg type=\"s\" direction=\"out\"/></method>
<signal name=\"NotificationClosed\"><arg type=\"u\"/><arg type=\"u\"/></signal>
<signal name=\"ActionInvoked\"><arg type=\"u\"/><arg type=\"s\"/></signal>
</interface></node>")

(defun %method-call-p (m interface member)
  (plusp (sd-bus-message-is-method-call m interface member)))

(defun %handle-notifications-message (m)
  "Answer M when it is one of our methods; true when handled."
  (cond ((%method-call-p m +notifications-interface+ "Notify")
         (let* ((app (%read-string m))
                (replaces (%read-number m #\u :uint32))
                (icon (%read-string m))
                (summary (%read-string m))
                (body (%read-string m))
                (actions (%read-string-array m))
                (hints (%read-hints m))
                (timeout (%read-number m #\i :int32))
                (id (notification-received :app (or app "") :replaces (or replaces 0)
                                           :icon icon :summary (or summary "")
                                           :body (or body "") :actions actions
                                           :urgency (or (cdr (assoc :urgency hints)) 1)
                                           :timeout (or timeout -1))))
           (%with-reply (reply m) (%append-uint32 reply id))
           t))
        ((%method-call-p m +notifications-interface+ "CloseNotification")
         (let ((id (%read-number m #\u :uint32)))
           (%with-reply (reply m))
           (when id (notification-close id 3))
           t))
        ((%method-call-p m +notifications-interface+ "GetCapabilities")
         (%with-reply (reply m)
           (sd-bus-message-open-container reply (%type-char #\a) "s")
           (dolist (capability '("body" "body-markup" "persistence"))
             (%append-string reply capability))
           (sd-bus-message-close-container reply))
         t)
        ((%method-call-p m +notifications-interface+ "GetServerInformation")
         (%with-reply (reply m)
           (dolist (s '("mahogany" "mahogany" "0.1" "1.2"))
             (%append-string reply s)))
         t)
        ((and (%method-call-p m "org.freedesktop.DBus.Introspectable" "Introspect")
              (equal (sd-bus-message-get-path m) +notifications-path+))
         (%with-reply (reply m) (%append-string reply *notifications-introspection*))
         t)
        (t nil)))

(hrt:define-hrt-callback %notifications-filter :int
    ((m :pointer) (userdata :pointer) (error :pointer))
    (:error-val 0)
  (declare (ignore userdata error))
  (handler-case (if (%handle-notifications-message m) 1 0)
    (error (c)
      (log-string :error "Notification message failed: ~A" c)
      0)))

(hrt:define-hrt-callback %notifications-bus-readable :int
    ((fd :int) (mask :uint32) (data :pointer))
    (:error-val 0)
  (declare (ignore fd mask data))
  (when *notification-bus*
    (loop repeat 64
          while (plusp (sd-bus-process *notification-bus* (cffi:null-pointer))))
    (sd-bus-flush *notification-bus*))
  0)

(defun notifications-start ()
  "Become the session's notification service. Logs and does nothing
without a session bus or when another service owns the name."
  (when *notification-bus*
    (return-from notifications-start t))
  (handler-case
      (progn
        (%load-libsystemd)
        (cffi:with-foreign-object (ret :pointer)
          (let ((r (sd-bus-open-user ret)))
            (when (minusp r)
              (log-string :warn "Notifications: no session bus (~D)" r)
              (return-from notifications-start nil))
            (let ((bus (cffi:mem-ref ret :pointer)))
              (sd-bus-add-filter bus (cffi:null-pointer)
                                 (cffi:callback %notifications-filter) (cffi:null-pointer))
              (let ((r (sd-bus-request-name bus +notifications-interface+ 0)))
                (when (minusp r)
                  (log-string :warn "Notifications: could not take ~A (~D); is another notification daemon running?"
                              +notifications-interface+ r)
                  (sd-bus-unref bus)
                  (return-from notifications-start nil)))
              (setf *notification-bus* bus
                    *notification-bus-source*
                    (hrt::hrt-event-loop-add-fd (state-server *compositor-state*)
                                                (sd-bus-get-fd bus)
                                                hrt::+hrt-event-readable+
                                                (cffi:callback %notifications-bus-readable)
                                                (cffi:null-pointer)))
              ;; Whatever came in while connecting:
              (loop while (plusp (sd-bus-process bus (cffi:null-pointer))))
              (log-string :info "Notifications: serving ~A" +notifications-interface+)
              t))))
    (error (c)
      (log-string :error "Notifications: could not start: ~A" c)
      nil)))

(defun notifications-stop ()
  "Give the notification service up."
  (when *notification-bus-source*
    (hrt::hrt-event-loop-remove *notification-bus-source*)
    (setf *notification-bus-source* nil))
  (when *notification-bus*
    (sd-bus-flush *notification-bus*)
    (sd-bus-close *notification-bus*)
    (sd-bus-unref *notification-bus*)
    (setf *notification-bus* nil))
  (notification-hide-canvas)
  (setf *notifications* '()))

(defun %emit-closed (id reason)
  (when *notification-bus*
    (cffi:with-foreign-object (ret :pointer)
      (when (>= (sd-bus-message-new-signal *notification-bus* ret +notifications-path+
                                           +notifications-interface+ "NotificationClosed")
                0)
        (let ((m (cffi:mem-ref ret :pointer)))
          (%append-uint32 m id)
          (%append-uint32 m reason)
          (sd-bus-send (cffi:null-pointer) m (cffi:null-pointer))
          (sd-bus-message-unref m))))))

;;; The notifications

(defstruct notification
  (id 0 :type fixnum)
  (app "" :type string)
  (summary "" :type string)
  (body "" :type string)
  (icon nil)
  (urgency 1 :type fixnum)       ; 0 low, 1 normal, 2 critical
  (actions '() :type list)
  (deadline nil)                 ; internal real time, or NIL to stay
  (time (get-universal-time)))

(config:defconfig *notification-timeout* 5000
  fixnum
  "How long a notification stays, in milliseconds, when the sender
gives no time; critical ones stay until dismissed.")

(config:defconfig *notification-width* 380
  fixnum
  "The width of notifications in layout pixels.")

(config:defconfig *notification-position* :top-right
  (member :top-right :top-left :bottom-right :bottom-left)
  "The corner of the output notifications stack in.")

(config:defconfig *notification-max-shown* 5
  fixnum
  "How many notifications are on screen at once; older ones wait in
the history.")

(config:defconfig *notification-history-size* 100
  fixnum
  "How many notifications the history keeps.")

(config:defconfig *notification-hooks* '()
  list
  "Functions called with each notification received, before it is
shown; one returning :hide keeps it off the screen (it stays in the
history).")

(defglobal *notifications* '()
  "The notifications on screen, newest first.")

(defglobal *notification-history* '()
  "Notifications received, newest first, up to *notification-history-size*.")

(defglobal *notifications-paused* nil
  "True while do-not-disturb is on: notifications go to the history only.")

(defglobal *notification-next-id* 1)
(defglobal *notification-canvas* nil)
(defglobal *notification-timer* nil)
(defglobal *notification-hits* '()
  "(y0 y1 id) of the cards drawn, for clicks.")

(defun %strip-markup (text)
  "TEXT without its markup tags, entities resolved: bodies may carry
markup, and bad markup must not break the drawing."
  (let ((out (make-string-output-stream))
        (in-tag nil))
    (loop for char across text
          do (cond (in-tag (when (char= char #\>) (setf in-tag nil)))
                   ((char= char #\<) (setf in-tag t))
                   (t (write-char char out))))
    (let ((s (get-output-stream-string out)))
      (dolist (entity '(("&lt;" . "<") ("&gt;" . ">") ("&quot;" . "\"")
                        ("&apos;" . "'") ("&amp;" . "&")))
        (setf s (%replace-all s (car entity) (cdr entity))))
      s)))

(defun %replace-all (string part replacement)
  (with-output-to-string (out)
    (loop with start = 0
          for pos = (search part string :start2 start)
          do (write-string string out :start start :end (or pos (length string)))
          while pos
          do (write-string replacement out)
             (setf start (+ pos (length part))))))

(defun %escape-markup (text)
  (%replace-all (%replace-all (%replace-all text "&" "&amp;") "<" "&lt;") ">" "&gt;"))

(defun notification-received (&key app replaces icon summary body actions (urgency 1) (timeout -1))
  "A notification came in: show it (or replace the one REPLACES), keep
it in the history, and return its id."
  (let* ((id (if (and replaces (plusp replaces)) replaces
                 (prog1 *notification-next-id* (incf *notification-next-id*))))
         (stay (or (= urgency 2) (= timeout 0)))
         (ms (if (plusp timeout) timeout *notification-timeout*))
         (notification (make-notification
                        :id id :app app :summary (%strip-markup summary)
                        :body (%strip-markup body) :icon icon
                        :urgency urgency :actions actions
                        :deadline (unless stay
                                    (+ (get-internal-real-time)
                                       (* ms (/ internal-time-units-per-second 1000)))))))
    (setf *notifications* (remove id *notifications* :key #'notification-id)
          *notification-history* (cons notification
                                       (remove id *notification-history* :key #'notification-id)))
    (when (> (length *notification-history*) *notification-history-size*)
      (setf *notification-history* (subseq *notification-history* 0 *notification-history-size*)))
    (let ((hidden (or *notifications-paused*
                      (some (lambda (hook) (eq (funcall hook notification) :hide))
                            *notification-hooks*))))
      (unless hidden
        (push notification *notifications*)
        (notifications-redraw)))
    id))

(defun notification-close (id &optional (reason 2))
  "Take notification ID off the screen: REASON 1 expired, 2 dismissed,
3 closed by the sender."
  (when (find id *notifications* :key #'notification-id)
    (setf *notifications* (remove id *notifications* :key #'notification-id))
    (%emit-closed id reason)
    (notifications-redraw)
    t))

(defun notification-hide-canvas ()
  (when *notification-timer*
    (hrt:timer-handle-destroy *notification-timer*)
    (setf *notification-timer* nil))
  (when *notification-canvas*
    (unless (hrt:canvas-destroyed-p *notification-canvas*)
      (hrt:canvas-destroy *notification-canvas*))
    (setf *notification-canvas* nil)))

(defun %notification-expire (timer)
  (declare (ignore timer))
  (setf *notification-timer* nil)
  (let ((now (get-internal-real-time)))
    (dolist (n *notifications*)
      (when (and (notification-deadline n) (<= (notification-deadline n) now))
        (setf *notifications* (remove n *notifications*))
        (%emit-closed (notification-id n) 1))))
  (notifications-redraw))

(defun %schedule-expiry ()
  (when *notification-timer*
    (hrt:timer-handle-destroy *notification-timer*)
    (setf *notification-timer* nil))
  (let ((next (loop for n in *notifications*
                    when (notification-deadline n) minimize (notification-deadline n))))
    (when (and next (plusp next))
      (let ((ms (max 10 (round (* 1000 (- next (get-internal-real-time)))
                               internal-time-units-per-second))))
        (setf *notification-timer*
              (hrt:server-make-timer (state-server *compositor-state*) #'%notification-expire))
        (hrt:timer-handle-update *notification-timer* ms)))))

(defun %notification-click (canvas x y button pressed)
  (declare (ignore canvas x))
  (when (and pressed (= button hrt:+button-left+))
    (loop for (y0 y1 id) in *notification-hits*
          when (<= y0 y y1)
            do (notification-close id 2)
               (return))))

(defun notifications-redraw ()
  "Draw the notifications on screen on the current output, or take the
canvas down when there are none."
  (%schedule-expiry)
  (let ((shown (subseq *notifications* 0 (min (length *notifications*) *notification-max-shown*)))
        (output (and (state-server *compositor-state*)
                     (group-current-output (state-current-group *compositor-state*)))))
    (when (or (null shown) (null output))
      (notification-hide-canvas)
      (return-from notifications-redraw nil))
    (when (and *notification-canvas*
               (or (hrt:canvas-destroyed-p *notification-canvas*)
                   (not (hrt:output= (hrt:canvas-output *notification-canvas*) output))))
      (notification-hide-canvas))
    (let* ((canvas (or *notification-canvas*
                       (let ((c (hrt:make-canvas output :layer :layer-overlay)))
                         (setf (hrt:canvas-on-button c) #'%notification-click)
                         (setf *notification-canvas* c))))
           (theme (or *theme* (find-theme :mahogany)))
           (font (theme-font theme))
           (small-font (format nil "~A ~D" (mh/theme:theme-font-name *menu-theme*)
                               (max 8 (- (mh/theme:theme-font-size *menu-theme*) 2))))
           (width *notification-width*)
           (pad 12) (gap 8) (margin 12)
           (text-width (- width (* 2 pad)))
           (heights '()))
      (multiple-value-bind (output-width output-height) (hrt:output-logical-size output)
        ;; Measure each card:
        (hrt:with-canvas-frame (cr canvas width 1)
          (dolist (n shown)
            (let ((summary-h (nth-value 1 (draw:text-size cr (notification-summary n) :font font)))
                  (body-h (if (string= (notification-body n) "")
                              0
                              (+ 4 (%wrapped-height cr (notification-body n) font text-width)))))
              (push (+ pad summary-h body-h pad) heights))))
        (setf heights (nreverse heights))
        (let* ((total (+ (reduce #'+ heights) (* gap (max 0 (1- (length heights))))))
               (top (member *notification-position* '(:top-right :top-left)))
               (x (if (member *notification-position* '(:top-right :bottom-right))
                      (- output-width width margin)
                      margin))
               (y (if top
                      (+ margin (if (and *mode-line-enabled* (eq *mode-line-position* :top))
                                    *mode-line-height* 0))
                      (- output-height total margin
                         (if (and *mode-line-enabled* (eq *mode-line-position* :bottom))
                             *mode-line-height* 0)))))
          (hrt:canvas-set-position canvas x y)
          (setf *notification-hits* '())
          (hrt:with-canvas-frame (cr canvas width total)
            (draw:clear cr '(0 0 0 0))
            (let ((cy 0))
              (loop for n in shown
                    for h in heights
                    do (let ((border (case (notification-urgency n)
                                       (2 (theme-error theme))
                                       (0 (theme-muted theme))
                                       (t (theme-accent theme)))))
                         (draw:fill-rounded-rectangle cr 0 cy width h 8 (theme-background theme))
                         (draw:fill-rounded-rectangle cr 0 cy 4 h 2 border)
                         (draw:draw-text cr (format nil "<b>~A</b>" (%escape-markup (notification-summary n)))
                                         pad (+ cy pad) :font font :markup t
                                         :color (theme-foreground theme)
                                         :width (- text-width 80) :ellipsize :end)
                         (unless (string= (notification-app n) "")
                           (draw:draw-text cr (notification-app n) pad (+ cy pad)
                                           :font small-font :color (theme-muted theme)
                                           :width text-width :alignment :right))
                         (unless (string= (notification-body n) "")
                           (let ((summary-h (nth-value 1 (draw:text-size cr (notification-summary n) :font font))))
                             (draw:draw-text cr (notification-body n) pad (+ cy pad summary-h 4)
                                             :font font :color (theme-foreground theme)
                                             :width text-width)))
                         (push (list cy (+ cy h) (notification-id n)) *notification-hits*)
                         (incf cy (+ h gap))))))))
      canvas)))

(defun %wrapped-height (cr text font width)
  (draw:with-layout (layout cr :text text :font font :width width)
    (nth-value 1 (draw:layout-pixel-size layout))))

;;; Commands

(defcommand notification-dismiss ()
  (:documentation "Dismiss the newest notification")
  (:method ()
    (alexandria:when-let ((n (first *notifications*)))
      (notification-close (notification-id n) 2))))

(defcommand notification-dismiss-all ()
  (:documentation "Dismiss every notification on screen")
  (:method ()
    (dolist (n *notifications*)
      (%emit-closed (notification-id n) 2))
    (setf *notifications* '())
    (notifications-redraw)))

(defcommand notifications-toggle ()
  (:documentation "Do not disturb on or off")
  (:method ()
    (setf *notifications-paused* (not *notifications-paused*))
    (toast-message *compositor-state*
                   (if *notifications-paused* "Do not disturb: on" "Do not disturb: off"))))

(defcommand notification-history ()
  (:documentation "The notifications received, to read again")
  (:method () (launcher :notifications)))

(define-launcher-mode :notifications (:prompt "Notification" :description "Notification history")
  :items (loop for n in *notification-history*
               collect (make-menu-item (if (string= (notification-body n) "")
                                           (notification-summary n)
                                           (format nil "~A: ~A" (notification-summary n)
                                                   (substitute #\Space #\Newline (notification-body n))))
                                       :data n
                                       :detail (multiple-value-bind (s m h) (decode-universal-time (notification-time n))
                                                 (declare (ignore s))
                                                 (format nil "~A ~2,'0D:~2,'0D" (notification-app n) h m))))
  :action (lambda (n)
            ;; Show it again, staying until dismissed:
            (setf (notification-deadline n) nil)
            (setf *notifications* (cons n (remove n *notifications*)))
            (notifications-redraw)))

(define-keys *top-map*
  "s-n" #'notification-dismiss
  "s-S-n" #'notification-dismiss-all
  "s-C-n" #'notifications-toggle
  "s-M-n" #'notification-history)
