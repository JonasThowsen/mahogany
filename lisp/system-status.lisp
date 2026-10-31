(in-package #:mahogany)

;;; What the system is up to, for the mode-line and the OSD: battery,
;;; backlight, network, audio. Read from sysfs where that is enough,
;;; and from the usual command line tools otherwise, asynchronously, so
;;; the compositor never waits for them.

;;; Running programs without waiting

(defun run-async (args &optional callback)
  "Run the program ARGS (a list, or one string for a shell command)
without waiting. When it finishes, CALLBACK, if given, is called on the
main thread with its standard output and exit code; with NIL and NIL
if it could not be started."
  (handler-case
      (hrt:subprocess-collect (state-server *compositor-state*)
                              args
                              (lambda (result)
                                (when callback
                                  (funcall callback
                                           (hrt:collect-output-result-stdout result)
                                           (hrt:collect-output-result-exit-code result)))))
    (error (c)
      (log-string :warn "Could not run ~S: ~A" args c)
      (when callback (funcall callback nil nil))))
  (values))

(defun %read-sysfs (path)
  "The first line of the file PATH, trimmed, or NIL."
  (with-open-file (in path :if-does-not-exist nil)
    (when in
      (let ((line (read-line in nil)))
        (and line (string-trim '(#\Space #\Newline #\Return) line))))))

(defun %read-sysfs-integer (path)
  (alexandria:when-let ((text (%read-sysfs path)))
    (parse-integer text :junk-allowed t)))

;;; Battery

(defun battery-status ()
  "A plist (:percent N :state :charging|:discharging|:full|:unknown) for
the first battery, or NIL without one."
  (dolist (dir (directory "/sys/class/power_supply/*/") nil)
    (when (equal (%read-sysfs (merge-pathnames "type" dir)) "Battery")
      (alexandria:when-let ((percent (%read-sysfs-integer (merge-pathnames "capacity" dir))))
        (return (list :percent percent
                      :state (let ((status (%read-sysfs (merge-pathnames "status" dir))))
                               (cond ((equal status "Charging") :charging)
                                     ((equal status "Discharging") :discharging)
                                     ((equal status "Full") :full)
                                     (t :unknown)))))))))

;;; Backlight

(config:defconfig *brightness-step* 5
  (integer 1 100)
  "Percent points the brightness keys change the backlight by.")

(config:defconfig *backlight-device* nil
  (or null string)
  "The backlight the brightness keys drive, a name under
/sys/class/backlight such as \"intel_backlight\"; NIL picks one: the
integrated GPU's (intel_backlight, amdgpu_bl*) before any other, and
NVIDIA's last, since on a laptop with two GPUs the panel usually hangs
off the integrated one and the other backlight changes nothing.")

(defun %backlight-name (dir)
  (car (last (pathname-directory dir))))

(defun %backlight-rank (name)
  (cond ((or (alexandria:starts-with-subseq "intel_backlight" name)
             (alexandria:starts-with-subseq "amdgpu_bl" name)) 0)
        ((alexandria:starts-with-subseq "nvidia" name) 2)
        (t 1)))

(defun %backlight-directory ()
  "The directory of the backlight in use, or NIL without one."
  (let ((dirs (directory "/sys/class/backlight/*/")))
    (if *backlight-device*
        (find *backlight-device* dirs :key #'%backlight-name :test #'string=)
        (first (stable-sort (copy-list dirs) #'< :key (lambda (dir) (%backlight-rank (%backlight-name dir))))))))

(defun backlight-device ()
  "The name of the backlight in use, or NIL without one."
  (alexandria:when-let ((dir (%backlight-directory)))
    (%backlight-name dir)))

(defun brightness-percent ()
  "The backlight's brightness in percent, or NIL without one."
  (alexandria:when-let* ((dir (%backlight-directory))
                         (now (%read-sysfs-integer (merge-pathnames "brightness" dir)))
                         (max (%read-sysfs-integer (merge-pathnames "max_brightness" dir))))
    (when (plusp max)
      (round (* 100 now) max))))

(defun brightness-change (delta &optional callback)
  "Change the backlight by DELTA percent points through brightnessctl,
on the backlight in use; CALLBACK, if given, gets the new percentage."
  (let ((device (backlight-device)))
    (run-async (append (list "brightnessctl")
                       (when device (list "-d" device))
                       (list "set" (format nil "~D%~A" (abs delta) (if (minusp delta) "-" "+"))))
               (lambda (output code)
                 (unless (eql code 0)
                   (log-string :warn "brightnessctl on ~A failed (~A): ~A" device code output))
                 (when callback (funcall callback (brightness-percent)))))))

;;; Network

(defglobal *network-status* nil
  "The last network status read: a plist (:interface NAME :kind :wifi|:wired
:ssid SSID) or NIL for offline.")

(defun %interface-up-p (dir)
  (equal (%read-sysfs (merge-pathnames "operstate" dir)) "up"))

(defun %interface-name (dir)
  (car (last (pathname-directory dir))))

(defun %interface-virtual-p (dir)
  ;; Virtual interfaces (bridges, tunnels, containers) have no device:
  (not (probe-file (merge-pathnames "device/" dir))))

(defun network-refresh (&optional callback)
  "Find out how the machine is connected, and the SSID when by wifi,
asynchronously (iwctl, then iw). CALLBACK, if given, gets the status."
  (let* ((interfaces (remove-if #'%interface-virtual-p (directory "/sys/class/net/*/")))
         (wifi (find-if (lambda (dir)
                          (and (%interface-up-p dir)
                               (probe-file (merge-pathnames "wireless/" dir))))
                        interfaces))
         (wired (find-if (lambda (dir)
                           (and (%interface-up-p dir)
                                (not (probe-file (merge-pathnames "wireless/" dir)))))
                         interfaces)))
    (flet ((done (status)
             (setf *network-status* status)
             (when callback (funcall callback status))))
      (cond
        (wifi
         (let ((name (%interface-name wifi)))
           (run-async (list "iwctl" "station" name "show")
                      (lambda (output code)
                        (let ((ssid (and output (zerop (or code 1)) (%parse-iwctl-ssid output))))
                          (if ssid
                              (done (list :interface name :kind :wifi :ssid ssid))
                              (run-async (list "iw" "dev" name "link")
                                         (lambda (output code)
                                           (declare (ignore code))
                                           (done (list :interface name :kind :wifi
                                                       :ssid (and output (%parse-iw-ssid output))))))))))))
        (wired (done (list :interface (%interface-name wired) :kind :wired)))
        (t (done nil))))))

(defun %parse-iwctl-ssid (output)
  "The SSID in the output of iwctl station IF show, or NIL."
  (loop for line in (uiop:split-string output :separator '(#\Newline))
        for trimmed = (string-trim " " line)
        when (alexandria:starts-with-subseq "Connected network" trimmed)
          return (string-trim " " (subseq trimmed (length "Connected network")))))

(defun %parse-iw-ssid (output)
  (loop for line in (uiop:split-string output :separator '(#\Newline))
        for trimmed = (string-trim " " line)
        when (alexandria:starts-with-subseq "SSID:" trimmed)
          return (string-trim " " (subseq trimmed 5))))

;;; Audio, through WirePlumber's wpctl

(config:defconfig *volume-step* 5
  (integer 1 100)
  "Percent points the volume keys change the volume by.")

(defglobal *volume-status* nil
  "The last volume read: a plist (:percent N :muted BOOL), or NIL.")

(defun %parse-wpctl-volume (output)
  "The plist for wpctl get-volume's \"Volume: 0.55 [MUTED]\", or NIL. The
number ends at the first character that is not a digit or a dot, so the
newline after it (there without [MUTED]) is not part of it."
  (let ((start (search "Volume:" output)))
    (when start
      (let* ((rest (string-trim " " (subseq output (+ start 7))))
             (end (or (position-if-not (lambda (char) (or (digit-char-p char) (char= char #\.)))
                                       rest)
                      (length rest)))
             (number (ignore-errors (parse-number (subseq rest 0 end)))))
        (when (numberp number)
          (list :percent (round (* 100 number))
                :muted (not (null (search "MUTED" rest)))))))))

(defun parse-number (string)
  "The decimal number in STRING, such as 0.55, as a rational."
  (let* ((dot (position #\. string))
         (whole (parse-integer string :end dot))
         (fraction (if dot (subseq string (1+ dot)) "")))
    (+ whole (if (plusp (length fraction))
                 (/ (parse-integer fraction) (expt 10 (length fraction)))
                 0))))

(defun volume-refresh (&optional callback)
  "Read the default sink's volume asynchronously; CALLBACK gets the
plist. A reading that fails is logged and the last one kept, so the
mode-line does not lose the volume over one bad read; it is NIL only
until the first reading succeeds (no wpctl, no audio)."
  (run-async '("wpctl" "get-volume" "@DEFAULT_AUDIO_SINK@")
             (lambda (output code)
               (let ((status (and output (member code '(nil 0)) (%parse-wpctl-volume output))))
                 (if status
                     (setf *volume-status* status)
                     (log-string :warn "wpctl get-volume gave no volume (exit ~S): ~S" code output)))
               (when callback (funcall callback *volume-status*)))))

(defun volume-change (delta &optional callback)
  "Change the default sink's volume by DELTA percent points, within 0
to 100 percent; CALLBACK gets the new status."
  (run-async (list "wpctl" "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@"
                   (format nil "~D%~A" (abs delta) (if (minusp delta) "-" "+")))
             (lambda (output code)
               (declare (ignore output code))
               (volume-refresh callback))))

(defun volume-toggle-mute (&optional callback)
  (run-async '("wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle")
             (lambda (output code)
               (declare (ignore output code))
               (volume-refresh callback))))

(defun microphone-toggle-mute (&optional callback)
  (run-async '("wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle")
             (lambda (output code)
               (declare (ignore output code))
               (when callback (funcall callback)))))
