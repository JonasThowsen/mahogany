(fiasco:define-test-package #:mahogany-tests/wifi
  (:use #:mahogany))

(in-package #:mahogany-tests/wifi)

(defparameter *get-networks*
  (format nil "~{~A~%~}"
          '("                               Available networks"
            "--------------------------------------------------------------------------------"
            "      Network name                      Security            Signal"
            "--------------------------------------------------------------------------------"
            "  >   Hjemme 5G                         psk                 ****"
            "      Nabo                              psk                 **"
            "      Kafe Fri                          open                ***"
            "      eduroam                           8021x               *")))

(fiasco:deftest iwctl-networks-are-parsed ()
  (let ((networks (mahogany::%parse-iwctl-networks *get-networks*)))
    (is (= 4 (length networks)))
    (is (equal '(:ssid "Hjemme 5G" :security "psk" :signal 4 :connected t)
               (first networks)))
    (is (equal '(:ssid "Kafe Fri" :security "open" :signal 3 :connected nil)
               (third networks)))
    (is (equal "eduroam" (getf (fourth networks) :ssid)))))

(fiasco:deftest iwctl-colours-are-stripped ()
  (let ((coloured (format nil "~C[1;90m  >   ~C[0mHjemme 5G    ~C[1mpsk~C[0m   ****"
                          #\Escape #\Escape #\Escape #\Escape)))
    (is (equal "  >   Hjemme 5G    psk   ****" (mahogany::%strip-ansi coloured))))
  (is (equal "plain" (mahogany::%strip-ansi "plain"))))

(fiasco:deftest nothing-is-not-a-network ()
  (is (null (mahogany::%parse-iwctl-networks "")))
  (is (null (mahogany::%parse-iwctl-networks (format nil "No networks~%")))))

(fiasco:deftest the-menu-lists-the-connected-network-first ()
  (let* ((items (mahogany::wifi-menu-items (mahogany::%parse-iwctl-networks *get-networks*)))
         (labels (mapcar #'mahogany::menu-item-label items)))
    (is (equal "✓ Hjemme 5G" (first labels)))
    (is (member "Disconnect" labels :test #'equal))
    (is (member "Rescan" labels :test #'equal))
    ;; The rest by signal:
    (is (equal '("Kafe Fri" "Nabo" "eduroam")
               (remove-if (lambda (l) (member l '("✓ Hjemme 5G" "Disconnect" "Rescan") :test #'equal))
                          labels)))))
