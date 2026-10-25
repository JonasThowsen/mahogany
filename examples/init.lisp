;;; An example ~/.config/mahogany/init.lisp. Everything here is
;;; optional: without a file, Mahogany runs with the defaults these
;;; forms show. Change it live from Emacs (SLY) or with the lisp
;;; command; a restart is never needed.

(in-package :mahogany)

;;; Look

(set-theme :tokyo-night)                ; theme-menu (s-C-SPC) lists them
;; (set-wallpaper "~/Pictures/wallpaper.png")   ; a PNG, scaled to cover
;; (setf *mode-line-position* :bottom)
;; (setf *mode-line-segments*
;;       '(:groups :title :fill :network :volume :battery :clock))

;;; Keys: SUPER chords on *top-map*, C-t prefix map in *root-map*

;; (define-key *top-map* (kbd "s-e") #'launcher-apps)
;; (undefine-key *top-map* (kbd "s-b"))
;; A command of your own, bound to a key:
;; (defcommand open-browser ()
;;   (:documentation "Start the browser")
;;   (:method () (uiop:launch-program '("firefox"))))
;; (define-key *top-map* (kbd "s-S-b") #'open-browser)

;;; Programs

;; (setf *default-terminals* '("foot" "alacritty"))
;; (setf *scratchpad-command* '("foot" "--app-id" "scratchpad"))
;; (setf *autostart* '(("xwayland-satellite") "mako"))

;;; Locking and idle: lock after 5 minutes, screen off after 10

;; (setf *idle-timeouts* '((300 :lock) (600 :screen-off)))
;; (setf *idle-lock-command* "swaylock -f")

;;; The launcher: a mode of your own, listed in the s-M-SPC menu

;; (define-launcher-mode :projects (:prompt "Project" :description "Open a project")
;;   :items (mapcar (lambda (dir) (make-menu-item (car (last (pathname-directory dir)))
;;                                               :data dir))
;;                  (directory "~/coding/*/"))
;;   :action (lambda (dir) (uiop:launch-program (list "foot" "-D" (namestring dir)))))
