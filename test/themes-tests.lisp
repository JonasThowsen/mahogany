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
  (dolist (name '(:mahogany :tokyo-night :catppuccin :nord :gruvbox))
    (let ((theme (mahogany::find-theme name)))
      (is (typep (mahogany::theme-foreground theme) 'colors:rgb))
      (is (typep (mahogany::theme-background theme) 'colors:rgb))
      (is (typep (mahogany::theme-accent theme) 'colors:rgb))
      (is (plusp (length (mahogany::theme-description theme)))))))

(fiasco:deftest find-theme-signals-for-unknown-names ()
  (signals error (mahogany::find-theme :no-such-theme-anywhere))
  (is (null (mahogany::find-theme :no-such-theme-anywhere :errorp nil))))
