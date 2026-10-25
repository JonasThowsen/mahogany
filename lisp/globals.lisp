(in-package #:mahogany)

(declaim (type mahogany-state *compositor-state*))
(defglobal *compositor-state* (make-mahogany-state))

(defun state-file (name)
  "The pathname of NAME in Mahogany's state directory,
$XDG_STATE_HOME/mahogany/ (~/.local/state/mahogany/), where what
survives a restart but is not configuration is kept: the launcher
history, the chosen theme."
  ;; This UIOP has no function for XDG_STATE_HOME:
  (let ((state-home (or (uiop:getenv-absolute-directory "XDG_STATE_HOME")
                        (uiop:subpathname (user-homedir-pathname) ".local/state/"))))
    (uiop:subpathname (uiop:subpathname state-home "mahogany/") name)))
