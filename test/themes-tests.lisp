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

(defun call-with-theme-globals-kept (function)
  "Call FUNCTION, then put back what set-theme changes."
  (let* ((symbols '(mahogany::*theme* mahogany::*mode-line-theme* mahogany::*menu-theme*
                    mahogany::*osd-theme* mahogany::*message-theme*
                    mahogany::*message-error-theme* mahogany::*theme-settings-saved*
                    mahogany::*theme-before-preview* mahogany::*theme-hooks*))
         (values (mapcar #'symbol-value symbols)))
    (unwind-protect (funcall function)
      (mapc #'(setf symbol-value) values symbols))))

(fiasco:deftest a-theme-preview-shows-and-goes-back ()
  (call-with-theme-globals-kept
   (lambda ()
     ;; Two themes without settings, so nothing but the globals change;
     ;; a preview neither remembers the theme nor runs the hooks.
     (let* ((before (mahogany::find-theme :tokyo-night))
            (calls 0))
       (setf mahogany::*theme-hooks* (list (lambda (theme) (declare (ignore theme)) (incf calls)))
             mahogany::*theme* before
             mahogany::*theme-before-preview* nil)
       (mahogany::preview-theme :nord)
       (is (eq :nord (mahogany::theme-name mahogany::*theme*)))
       (mahogany::preview-theme :gruvbox)
       (is (eq :gruvbox (mahogany::theme-name mahogany::*theme*)))
       (is (eq before mahogany::*theme-before-preview*))
       (is (= 0 calls))
       ;; Escape:
       (mahogany::end-theme-preview)
       (is (eq before mahogany::*theme*))
       (is (null mahogany::*theme-before-preview*))
       (is (= 0 calls))))))

(defun rgb-255 (color)
  (mapcar (lambda (c) (round (* 255 c)))
          (list (colors:rgb-red color) (colors:rgb-green color) (colors:rgb-blue color))))

(defun close-to (pixel color)
  (every (lambda (a b) (<= (abs (- a b)) 2)) pixel (rgb-255 color)))

(fiasco:deftest a-theme-card-is-drawn-in-its-colors ()
  (mahogany/draw:load-libraries)
  (let ((theme (mahogany::define-theme :test-card
                 :foreground "#ffffff" :background "#102030" :accent "#ff8000"
                 :border-focus "#00ff00" :border-unfocus "#0000ff"
                 :wallpaper-color "#ff00ff"
                 :settings '(mahogany/tree:*window-gap* 10 mahogany/tree:*output-gap* 10
                             mahogany/tree:*frame-border-width* 2 mahogany::*mode-line-height* 28))))
    (unwind-protect
         (mahogany/draw:with-image-surface (surface 320 200)
           (mahogany/draw:with-context (cr surface)
             (mahogany::draw-theme-card cr theme 320 200))
           (flet ((pixel (x y)
                    (subseq (multiple-value-list (mahogany/draw:image-surface-pixel surface x y)) 0 3)))
             ;; The bar is the background; the focused window's left edge
             ;; the focus border, the other window's the unfocused border.
             ;; scale 0.32: bar 11, outer gap 5, border 1, gap 5, so the left
             ;; window is 177 wide and the right one starts at 187.
             (is (close-to (pixel 100 0) (mahogany::theme-background theme)))
             (is (close-to (pixel 5 100) (mahogany::theme-border-focus theme)))
             (is (close-to (pixel 187 20) (mahogany::theme-border-unfocus theme)))
             ;; Below that window, the empty frame shows the wallpaper,
             ;; a gradient of the wallpaper color, not a window:
             (is (not (close-to (pixel 250 185) (mahogany::theme-background theme))))))
      (remhash :test-card mahogany::*themes*))))

(fiasco:deftest a-theme-card-is-rendered-once-and-redone-when-the-theme-changes ()
  (mahogany/draw:load-libraries)
  (let ((theme (mahogany::define-theme :test-card-cache :background "#000000")))
    (unwind-protect
         (let ((first (mahogany::%theme-card-image theme 160 100 2)))
           ;; At the scale's size in pixels:
           (is (equal '(320 200) (multiple-value-list (mahogany/draw:image-size first))))
           (is (eq first (mahogany::%theme-card-image theme 160 100 2)))
           ;; Redefined, the theme is another object, and its card is redone:
           (let* ((again (mahogany::define-theme :test-card-cache :background "#ffffff"))
                  (second (mahogany::%theme-card-image again 160 100 2)))
             (is (not (eq first second)))
             (is (eq second (mahogany::%theme-card-image again 160 100 2)))))
      (let ((entry (gethash (list :test-card-cache 160 100 2) mahogany::*theme-cards*)))
        (when entry
          (mahogany/draw:cairo-surface-destroy (cddr entry))
          (remhash (list :test-card-cache 160 100 2) mahogany::*theme-cards*)))
      (remhash :test-card-cache mahogany::*themes*))))

(fiasco:deftest rendered-wallpapers-are-kept-and-the-oldest-let-go ()
  (mahogany/draw:load-libraries)
  (let ((saved mahogany::*wallpaper-renderings*)
        (kept mahogany::*wallpaper-renderings-kept*))
    (setf mahogany::*wallpaper-renderings* '()
          mahogany::*wallpaper-renderings-kept* 2)
    (unwind-protect
         (flet ((render (color)
                  (mahogany::%wallpaper-rendering nil (colors:rgb color 0 0) 8 4 1)))
           (let ((red (render 1)))
             (is (eq red (render 1)))
             (render 0.5)
             (render 0.25)
             ;; Two kept, the first rendering let go:
             (is (= 2 (length mahogany::*wallpaper-renderings*)))
             (is (not (eq red (render 1))))))
      (loop for (nil . surface) in mahogany::*wallpaper-renderings*
            do (mahogany/draw:cairo-surface-destroy surface))
      (setf mahogany::*wallpaper-renderings* saved
            mahogany::*wallpaper-renderings-kept* kept))))
