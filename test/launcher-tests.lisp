(fiasco:define-test-package #:mahogany-tests/launcher
  (:use #:mahogany))

(in-package #:mahogany-tests/launcher)

(fiasco:deftest eval-text-reads-in-mahogany-and-returns-the-last-values ()
  (is (equal '(3 4)
             (multiple-value-list (mahogany::eval-text "(+ 1 1) (values 3 4)"))))
  ;; Read in the mahogany package: its symbols need no prefix.
  (is (eq 'mahogany::launcher (mahogany::eval-text "'launcher")))
  ;; Nothing to evaluate gives no values.
  (is (null (multiple-value-list (mahogany::eval-text "  ")))))

(fiasco:deftest values-text-is-brief ()
  (is (string= "1, \"a\"" (mahogany::%values-text '(1 "a"))))
  (is (string= "; no values" (mahogany::%values-text '())))
  (is (< (length (mahogany::%values-text (list (make-list 1000 :initial-element 1))))
         200))
  (let ((answer (mahogany::%values-text (list (make-string 1000 :initial-element #\a)))))
    (is (= (1+ mahogany::*values-text-length*) (length answer)))
    (is (char= #\… (char answer (1- (length answer)))))))

(fiasco:deftest load-lisp-file-needs-a-file ()
  (signals mahogany/util:recoverable-error
    (mahogany::load-lisp-file "/nonexistent/none.lisp"))
  (uiop:with-temporary-file (:pathname file :stream s :type "lisp" :keep t)
    (format s "(defparameter mahogany-tests/launcher::*loaded* 42)")
    (finish-output s)
    (close s)
    (is (equal (truename file) (mahogany::load-lisp-file (uiop:native-namestring file))))
    (is (eql 42 (symbol-value '*loaded*)))
    (delete-file file)))

(defun call-with-desktop-file (content function)
  (uiop:with-temporary-file (:stream out :pathname file :type "desktop" :keep t)
    (write-string content out)
    (finish-output out)
    :close-stream
    (unwind-protect (funcall function file)
      (uiop:delete-file-if-exists file))))

(fiasco:deftest desktop-actions-are-parsed-and-the-new-window-one-found ()
  (call-with-desktop-file
   "[Desktop Entry]
Type=Application
Name=Helium
Exec=helium %U
StartupWMClass=helium
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=helium --new-window %U

[Desktop Action new-private-window]
Name=New Private Window
Exec=helium --incognito
"
   (lambda (file)
     (let ((entry (mahogany::%parse-desktop-file file)))
       (is (equal "helium " (mahogany::desktop-entry-exec entry)))
       (is (equal "helium" (mahogany::desktop-entry-wm-class entry)))
       (is (equal '(("new-window" "New Window" "helium --new-window ")
                    ("new-private-window" "New Private Window" "helium --incognito"))
                  (mahogany::desktop-entry-actions entry)))
       (is (equal "new-window"
                  (first (mahogany::desktop-entry-new-window-action entry))))))))

(fiasco:deftest a-private-window-is-not-the-new-window-action ()
  (call-with-desktop-file
   "[Desktop Entry]
Type=Application
Name=Browser
Exec=browser

[Desktop Action new-private-window]
Name=New Private Window
Exec=browser --incognito
"
   (lambda (file)
     (let ((entry (mahogany::%parse-desktop-file file)))
       (is (= 1 (length (mahogany::desktop-entry-actions entry))))
       (is (null (mahogany::desktop-entry-new-window-action entry)))))))

(fiasco:deftest an-entry-without-actions-has-none ()
  (call-with-desktop-file
   "[Desktop Entry]
Type=Application
Name=Plain
Exec=plain
"
   (lambda (file)
     (let ((entry (mahogany::%parse-desktop-file file)))
       (is (equal "Plain" (mahogany::desktop-entry-name entry)))
       (is (null (mahogany::desktop-entry-actions entry)))
       (is (null (mahogany::desktop-entry-new-window-action entry)))))))
