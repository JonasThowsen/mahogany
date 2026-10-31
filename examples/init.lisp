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

;;; Tiling: a layout per group (:master-stack by default; s-r cycles,
;;; s-C-r chooses) or by hand (:manual, as StumpWM)

;; (setf *default-layout* :manual)
;; (setf *group-layout-defaults* '(("1" . :master-stack) ("2" . :manual)))

;;; Input: the touchpad, the mouse, Num Lock, the cursor

;; (config:set-config touchpad-tap-to-click t          ; the default
;;                    touchpad-natural-scroll t
;;                    mouse-accel-speed -0.4
;;                    numlock t
;;                    cursor-theme "Adwaita"
;;                    cursor-size 24)

;;; Outputs: the scale is picked from the screen's DPI (2 on a HiDPI
;;; laptop screen); set it by hand with an output configuration

;; (define-output-config "laptop" "eDP-1" (:scale 2))
;; (define-output-config "monitor" "DP-1" (:scale 1.5) (:position 0 0))

;;; Keys: SUPER chords on *top-map* (laid out as niri), C-t prefix map
;;; in *root-map*; s-S-SPC lists what is bound

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
;; Windows that float over the tiles (see Floating Windows in the manual):
;; (push '("org.gnome.Calculator" :width 400 :height 600) *floating-rules*)
;; Screenshots: open satty right away, instead of on a click on the message
;; (setf *screenshot-edit* t)
;; (setf *autostart* '(("xwayland-satellite") "mako"))

;;; The lid: lock when it closes; with an external monitor, the
;;; built-in screen goes off and its windows move over

;; (setf *lid-close-action* :nothing)
;; (setf *lid-close-action-docked* :lock)
;; (setf *lid-switch-outputs* nil)

;;; X11 programs run through xwayland-satellite when it is installed

;; (setf *xwayland* nil)

;;; Notifications: Mahogany is the notification service (no mako needed)

;; (setf *notification-position* :bottom-right)
;; (setf *notification-timeout* 8000)

;;; Locking and idle: lock after 5 minutes, screen off after 10

;; (setf *idle-timeouts* '((300 :lock) (600 :screen-off)))
;; (setf *idle-lock-command* "swaylock -f")

;;; The launcher: a mode of your own, listed in the s-M-SPC menu

;; (define-launcher-mode :projects (:prompt "Project" :description "Open a project")
;;   :items (mapcar (lambda (dir) (make-menu-item (car (last (pathname-directory dir)))
;;                                               :data dir))
;;                  (directory "~/coding/*/"))
;;   :action (lambda (dir) (uiop:launch-program (list "foot" "-D" (namestring dir)))))
