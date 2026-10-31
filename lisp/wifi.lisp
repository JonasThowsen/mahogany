(in-package #:mahogany)

;;; Wifi, through iwd's iwctl: a menu of the networks around, one click
;;; on the mode-line's network module (or the wifi-menu command, or the
;;; :wifi launcher mode) away. Choosing a network connects to it; one
;;; that wants a passphrase iwd does not have yet asks for it. Everything
;;; runs iwctl asynchronously, so the compositor never waits.

(config:defconfig *wifi-interface* nil
  (or null string)
  "The wireless interface iwctl drives, such as \"wlan0\"; NIL takes the
first one there is.")

(defglobal *wifi-networks* '()
  "The networks the last scan saw: plists (:ssid S :security \"psk\"|\"open\"|…
:signal 0-5 :connected BOOL), strongest first.")

(defun %wireless-interfaces ()
  "The names of the wireless interfaces, from sysfs."
  (loop for dir in (directory "/sys/class/net/*/")
        when (probe-file (merge-pathnames "wireless/" dir))
          collect (%interface-name dir)))

(defun wifi-interface ()
  "The interface wifi goes through, or NIL without one."
  (or *wifi-interface* (first (%wireless-interfaces))))

(defun %strip-ansi (string)
  "STRING without its ANSI escape sequences (iwctl colours its output)."
  (with-output-to-string (out)
    (let ((i 0) (n (length string)))
      (loop while (< i n)
            do (let ((ch (char string i)))
                 (cond ((and (char= ch #\Escape) (< (1+ i) n) (char= (char string (1+ i)) #\[))
                        ;; Skip to the final byte of the CSI sequence:
                        (setf i (+ i 2))
                        (loop while (and (< i n) (not (alpha-char-p (char string i))))
                              do (incf i))
                        (incf i))
                       (t (write-char ch out) (incf i))))))))

(defun %parse-iwctl-networks (output)
  "The networks in the output of iwctl station IF get-networks: a table
of name, security and signal stars, after two ruled lines, with > on
the connected one."
  (let ((lines (uiop:split-string (%strip-ansi output) :separator '(#\Newline)))
        (rules 0)
        (networks '()))
    (dolist (raw lines (nreverse networks))
      (let ((line (string-right-trim " " raw)))
        (cond ((and (> (length line) 10) (every (lambda (c) (char= c #\-)) line))
               (incf rules))
              ((and (>= rules 2) (plusp (length (string-trim " " line))))
               ;; "  >   Name with spaces     psk     ****"
               (let* ((stars (- (length line) (length (string-right-trim "*" line))))
                      (rest (string-right-trim " " (subseq line 0 (- (length line) stars))))
                      (space (position #\Space rest :from-end t))
                      (security (if space (subseq rest (1+ space)) rest))
                      (name (string-trim " " (if space (subseq rest 0 space) "")))
                      (connected (and (plusp (length name)) (char= (char name 0) #\>))))
                 (when connected
                   (setf name (string-trim " " (subseq name 1))))
                 (when (and (plusp (length name))
                            (member security '("psk" "open" "8021x" "wep" "owe" "sae")
                                    :test #'string-equal))
                   (push (list :ssid name :security (string-downcase security)
                               :signal stars :connected connected)
                         networks)))))))))

(config:defconfig *wifi-scan-wait* 3000
  fixnum
  "Milliseconds between asking iwd to scan and reading the networks it
found: a scan takes a moment, and get-networks lists the last one.")

(defun %wifi-get-networks (interface callback)
  "Read the networks iwd knows on INTERFACE into *wifi-networks*, and
give CALLBACK the list, when there is one."
  (run-async (list "iwctl" "station" interface "get-networks")
             (lambda (output code)
               (setf *wifi-networks*
                     (if (and output (eql code 0))
                         (%parse-iwctl-networks output)
                         '()))
               (when callback (funcall callback *wifi-networks*)))))

(defun wifi-refresh (&optional callback (scan t))
  "Find the networks around, asynchronously, into *wifi-networks*;
CALLBACK, if given, gets the list. With SCAN (the default) iwd scans
first and the list is read *wifi-scan-wait* later, so new networks
show; without, the last scan's list comes at once."
  (let ((interface (wifi-interface)))
    (cond
      ((null interface)
       (when callback (funcall callback nil)))
      ((not scan)
       (%wifi-get-networks interface callback))
      (t
       (run-async (list "iwctl" "station" interface "scan")
                  (lambda (output code)
                    ;; "Operation already in progress" is a scan too:
                    (unless (eql code 0)
                      (log-string :debug "iwctl scan: ~A (~A)" output code))
                    (let ((timer (hrt:server-make-timer
                                  (state-server *compositor-state*)
                                  (lambda (timer)
                                    (hrt:timer-handle-destroy timer)
                                    (%wifi-get-networks interface callback)))))
                      (hrt:timer-handle-update timer *wifi-scan-wait*))))))))

(defun %wifi-report (text)
  "Tell the user TEXT, as a notification when the service runs, else a
message."
  (log-string :info "Wifi: ~A" text)
  (if (fboundp 'notification-received)
      (notification-received :app "Mahogany" :summary text :icon "network-wireless")
      (toast-message *compositor-state* text)))

(defun wifi-connect (ssid &key passphrase)
  "Connect to the network SSID through iwctl, with PASSPHRASE when
given; asks for one when iwd needs it and has none."
  (let ((interface (wifi-interface)))
    (unless interface
      (error 'mahogany/util:recoverable-error :text "No wireless interface"))
    (run-async (append (list "iwctl")
                       (when passphrase (list "--passphrase" passphrase))
                       (list "station" interface "connect" ssid))
               (lambda (output code)
                 (cond
                   ((eql code 0)
                    (%wifi-report (format nil "Connected to ~A" ssid))
                    (network-refresh (lambda (status)
                                       (declare (ignore status))
                                       (mode-line-update))))
                   ((and (not passphrase)
                         output
                         (or (search "Passphrase" output) (search "passphrase" output)
                             (search "Not configured" output) (search "Invalid" output)))
                    (wifi-ask-passphrase ssid))
                   (t
                    (%wifi-report (format nil "Could not connect to ~A~@[: ~A~]"
                                          ssid (and output (string-trim '(#\Space #\Newline)
                                                                        (%strip-ansi output)))))))))))

(defun wifi-ask-passphrase (ssid)
  "Ask for SSID's passphrase in a menu and connect with it."
  (menu-open (format nil "Passphrase for ~A:" ssid) '()
             :allow-text t
             :secret t
             :on-choose (lambda (passphrase)
                          (when (and (stringp passphrase) (plusp (length passphrase)))
                            (wifi-connect ssid :passphrase passphrase)))))

(defun wifi-disconnect ()
  "Disconnect from the current network."
  (alexandria:when-let ((interface (wifi-interface)))
    (run-async (list "iwctl" "station" interface "disconnect")
               (lambda (output code)
                 (declare (ignore output))
                 (%wifi-report (if (eql code 0) "Disconnected" "Could not disconnect"))
                 (network-refresh (lambda (status)
                                    (declare (ignore status))
                                    (mode-line-update)))))))

(defun %wifi-signal-bars (signal)
  (let ((bars (max 0 (min 4 (1- signal)))))
    (concatenate 'string
                 (make-string bars :initial-element #\▮)
                 (make-string (- 4 bars) :initial-element #\▯))))

(defun wifi-menu-items (&optional (networks *wifi-networks*))
  "Menu items for NETWORKS: the connected one first with a way to
disconnect, then the rest by signal."
  (let ((items '()))
    (dolist (network (sort (copy-list networks) #'>
                           :key (lambda (n) (+ (getf n :signal) (if (getf n :connected) 100 0)))))
      (push (make-menu-item (format nil "~:[~;✓ ~]~A" (getf network :connected) (getf network :ssid))
                            :detail (format nil "~A ~:[~;🔒 ~]~A"
                                            (%wifi-signal-bars (getf network :signal))
                                            (string/= (getf network :security) "open")
                                            (getf network :security))
                            :data network)
            items))
    (when (find-if (lambda (n) (getf n :connected)) networks)
      (push (make-menu-item "Disconnect" :detail "" :data :disconnect) items))
    (push (make-menu-item "Rescan" :detail "" :data :rescan) items)
    (nreverse items)))

(defun %wifi-choose (choice)
  (cond ((eq choice :disconnect) (wifi-disconnect))
        ((eq choice :rescan) (wifi-menu))
        ((and (listp choice) (getf choice :connected))
         (%wifi-report (format nil "Already connected to ~A" (getf choice :ssid))))
        ((listp choice) (wifi-connect (getf choice :ssid)))))

(defun wifi-menu ()
  "Scan for networks and open the wifi menu."
  (if (wifi-interface)
      (progn
        (toast-message *compositor-state* "Looking for networks…"
                       :ms-delay (+ *wifi-scan-wait* 5000))
        (wifi-refresh (lambda (networks)
                        (close-message *compositor-state*)
                        (menu-open (menu-prompt-string "Wifi")
                                   (wifi-menu-items networks)
                                   :on-choose (lambda (item)
                                                (%wifi-choose (menu-item-data item)))))))
      (toast-message *compositor-state* "No wireless interface")))

(defcommand wifi ()
  (:documentation "Connect to a wifi network (iwd)")
  (:method () (wifi-menu)))

(define-launcher-mode :wifi (:prompt "Wifi" :description "Connect to a wifi network")
  :items (wifi-menu-items)
  :action #'%wifi-choose)
