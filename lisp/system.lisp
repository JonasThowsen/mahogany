(defpackage #:mahogany/system
  (:documentation "Package for functions interacting with the system that
Mahogany is running under")
  (:use :cl #:mahogany/util #:mahogany/log)
  (:local-nicknames (#:alex #:alexandria))
  (:nicknames #:mh-sys)
  (:export #:find-program
           #:open-terminal))

(in-package #:mahogany/system)

(defun find-program (name)
  "The path of the program NAME on PATH, as a string, or NIL when it is
not installed. NAME with a slash in it is taken as a path and checked
as it is. No subprocess is run: this is called on the main thread."
  (declare (type string name))
  (flet ((executable-p (path)
           (let ((truename (probe-file path)))
             (and truename
                  (pathname-name truename) ; not a directory
                  #+sbcl (handler-case (plusp (logand (sb-posix:stat-mode (sb-posix:stat truename))
                                                      #o111))
                           (error () nil))
                  #-sbcl t
                  (namestring truename)))))
    (if (find #\/ name)
        (executable-p name)
        (loop for dir in (uiop:split-string (or (uiop:getenv "PATH") "") :separator ":")
              for path = (and (plusp (length dir))
                              (concatenate 'string dir "/" name))
              for found = (and path (executable-p path))
              when found return found))))

(defun open-program (candidates)
  (loop :for name :in candidates
        :do (alex:if-let ((program (find-program name)))
              (progn
                (uiop:launch-program program)
                (return t))
              (log-string :warn "Could not find program ~S in candidates ~S." name candidates)))
  (values nil))

(config-system:defconfig *default-terminals*
    (list "alacritty" "ghostty" "kitty" "xfce4-terminal"
          "konsole" "gnome-terminal" "wezterm" "foot")
  list
  "A list of default terminal programs to use")

(defun open-terminal ()
  (open-program *default-terminals*))
