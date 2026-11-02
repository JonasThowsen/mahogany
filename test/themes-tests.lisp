(fiasco:define-test-package #:mahogany-tests/themes
  (:use #:mahogany)
  (:local-nicknames (#:colors #:cl-colors2)))

(in-package #:mahogany-tests/themes)

;; These only define themes; set-theme is not called, as it draws and
;; remembers the theme in the user's state directory.

(fiasco:deftest color-accepts-strings-and-rgb ()
  (let ((red (colors:rgb 1 0 0)))
    (is (eq red (mahogany::color red)))
    (is (= 1 (colors:rgb-red (mahogany::color "#ff0000"))))
    (is (= 1 (colors:rgb-green (mahogany::color "00ff00"))))))

(fiasco:deftest define-theme-fills-in-defaults ()
  (let ((theme (mahogany::define-theme :test-defaults
                 :foreground "#ffffff" :background "#000000" :accent "#ff0000")))
    (is (eq :test-defaults (mahogany::theme-name theme)))
    ;; The accent is the focused border and the error color:
    (is (equalp (mahogany::theme-accent theme) (mahogany::theme-border-focus theme)))
    (is (equalp (mahogany::theme-accent theme) (mahogany::theme-error theme)))
    ;; The background is the surface, the unfocused border and the wallpaper color:
    (is (equalp (mahogany::theme-background theme) (mahogany::theme-surface theme)))
    (is (equalp (mahogany::theme-background theme) (mahogany::theme-border-unfocus theme)))
    (is (equalp (mahogany::theme-background theme) (mahogany::theme-wallpaper-color theme)))
    (is (null (mahogany::theme-wallpaper theme)))
    (is (eq theme (mahogany::find-theme :test-defaults)))
    (is (member :test-defaults (mahogany::theme-names)))
    (remhash :test-defaults mahogany::*themes*)))

(fiasco:deftest built-in-themes-are-complete ()
  (dolist (name '(:mahogany :tokyo-night :catppuccin :nord :gruvbox
                  :matte-black :gavinok))
    (let ((theme (mahogany::find-theme name)))
      (is (typep (mahogany::theme-foreground theme) 'colors:rgb))
      (is (typep (mahogany::theme-background theme) 'colors:rgb))
      (is (typep (mahogany::theme-accent theme) 'colors:rgb))
      (is (plusp (length (mahogany::theme-description theme)))))))

(fiasco:deftest find-theme-signals-for-unknown-names ()
  (signals error (mahogany::find-theme :no-such-theme-anywhere))
  (is (null (mahogany::find-theme :no-such-theme-anywhere :errorp nil))))

(defvar *setting-under-test* :before)

(fiasco:deftest theme-settings-are-set-and-put-back ()
  (let ((with (mahogany::define-theme :test-settings
                :settings '(mahogany-tests/themes::*setting-under-test* :themed)))
        (without (mahogany::define-theme :test-no-settings))
        (saved mahogany::*theme-settings-saved*))
    (unwind-protect
         (progn
           (setf mahogany::*theme-settings-saved* '())
           (is (not (mahogany::%apply-theme-settings with)))
           (is (eq :themed *setting-under-test*))
           ;; Another theme puts the value back:
           (mahogany::%apply-theme-settings without)
           (is (eq :before *setting-under-test*))
           (is (null mahogany::*theme-settings-saved*))
           ;; A theme that changes a gap says so:
           (let ((gap mahogany/tree:*window-gap*))
             (is (mahogany::%apply-theme-settings
                  (mahogany::define-theme :test-settings
                    :settings (list 'mahogany/tree:*window-gap* (1+ gap)))))
             (is (= (1+ gap) mahogany/tree:*window-gap*))
             (mahogany::%apply-theme-settings without)
             (is (= gap mahogany/tree:*window-gap*))))
      (setf mahogany::*theme-settings-saved* saved
            *setting-under-test* :before)
      (remhash :test-settings mahogany::*themes*)
      (remhash :test-no-settings mahogany::*themes*))))

(fiasco:deftest define-theme-from-takes-another-theme-as-defaults ()
  (let* ((nord (mahogany::find-theme :nord))
         (theme (mahogany::define-theme :test-from :from :nord
                  :accent "#ff0000" :wallpaper "/tmp/test.png")))
    (unwind-protect
         (progn
           (is (equalp (mahogany::theme-background nord) (mahogany::theme-background theme)))
           (is (equalp (mahogany::theme-foreground nord) (mahogany::theme-foreground theme)))
           (is (equalp (mahogany::theme-muted nord) (mahogany::theme-muted theme)))
           (is (equal (mahogany::theme-font nord) (mahogany::theme-font theme)))
           (is (equal (mahogany::theme-description nord) (mahogany::theme-description theme)))
           (is (= 1 (colors:rgb-red (mahogany::theme-accent theme))))
           ;; The inherited border-focus stays nord's, not the new accent:
           (is (equalp (mahogany::theme-border-focus nord) (mahogany::theme-border-focus theme)))
           (is (equal "/tmp/test.png" (mahogany::theme-wallpaper theme)))
           ;; The same theme with a wallpaper added keeps its settings:
           (let ((again (mahogany::define-theme :test-from :from :test-from
                          :settings '(mahogany-tests/themes::*setting-under-test* 1))))
             (is (equal "/tmp/test.png" (mahogany::theme-wallpaper again)))
             (is (equal '(mahogany-tests/themes::*setting-under-test* 1)
                        (mahogany::theme-settings
                         (mahogany::define-theme :test-from :from :test-from))))))
      (remhash :test-from mahogany::*themes*))))

(fiasco:deftest plain-overlays-are-square-with-a-thin-border ()
  (let ((mahogany::*overlay-style* :card))
    (is (= 12 (mahogany::%overlay-radius 12)))
    (is (= 2 (mahogany::%overlay-border))))
  (let ((mahogany::*overlay-style* :plain))
    (is (= 0 (mahogany::%overlay-radius 12)))
    (is (= 1 (mahogany::%overlay-border)))))
