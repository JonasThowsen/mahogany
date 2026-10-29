(in-package #:mahogany)

;;; Themes: one set of colors, a font and a wallpaper that everything
;;; Lisp draws takes from. The mode-line, menus, the on-screen display,
;;; messages and the frame borders each have a theme of their own
;;; (*mode-line-theme*, *menu-theme*, ...), and set-theme fills them
;;; all from one theme, live. Themes are defined with define-theme:
;;; the built-in ones below, the user's in init.lisp or in
;;; ~/.config/mahogany/themes/*.lisp. The theme chosen last is
;;; remembered across restarts, unless init.lisp sets one.

(defstruct (theme (:constructor %make-theme))
  (name nil :type keyword)
  (description "" :type string)
  (font "monospace 12" :type string)
  ;; The colors are cl-colors2 rgb:
  (foreground nil)      ; text
  (background nil)      ; panels: the mode-line, menus, messages
  (surface nil)         ; a second background: unfocused frame borders
  (accent nil)          ; the current group, the selection, focused borders
  (muted nil)           ; details, empty frames
  (error nil)           ; error messages
  (border-focus nil)
  (border-unfocus nil)
  (wallpaper nil)       ; a PNG file, or NIL for a plain color
  (wallpaper-color nil))

(defglobal *themes* (make-hash-table :test 'eq)
  "The themes known, by name.")

(defglobal *theme* nil
  "The theme in use, set with set-theme.")

(config:defconfig *default-theme* :tokyo-night
  keyword
  "The theme used at the first start, before one has been chosen with
set-theme or the theme menu. The chosen theme is remembered in the
state directory (state-file \"theme.sexp\") from then on.")

(config:defconfig *theme-directories*
    (list (uiop:xdg-config-home "mahogany/themes/"))
  list
  "Directories whose *.lisp files define the user's themes
(define-theme forms). They are loaded at startup and by reload-themes.")

(config:defconfig *wallpaper* nil
  (or null string pathname)
  "A PNG file shown as the wallpaper in place of the theme's own, on
every output, scaled to cover it. NIL shows the theme's wallpaper, or
its wallpaper color when it has none.")

(defglobal *theme-hooks* '()
  "Functions called with the theme after set-theme has applied it, for
the user's own theming: writing a terminal's color file, restarting a
program, and so on.")

(defun color (designator)
  "A cl-colors2 rgb color from DESIGNATOR: an rgb, or a string such as
\"#1a1b26\" or \"1a1b26\"."
  (etypecase designator
    (colors:rgb designator)
    (string (colors:as-rgb (string-left-trim "#" designator)))))

(defun define-theme (name &key (description "") (font "monospace 12")
                            (foreground "#ffffff") (background "#000000")
                            surface accent muted error
                            border-focus border-unfocus
                            wallpaper wallpaper-color)
  "Define (or redefine) the theme NAME, a keyword. Colors are strings
such as \"#7aa2f7\" or cl-colors2 rgb. FOREGROUND is the text color,
BACKGROUND that of panels, ACCENT marks what is current or selected
and, as BORDER-FOCUS by default, the focused frame; SURFACE (default
BACKGROUND) is the unfocused border by default; MUTED (default
FOREGROUND) draws details and empty frames; ERROR (default ACCENT)
error messages. WALLPAPER is a PNG file shown on every output, and
WALLPAPER-COLOR (default BACKGROUND) is shown without one. Returns the
theme; set-theme puts it to use."
  (let* ((foreground (color foreground))
         (background (color background))
         (surface (if surface (color surface) background))
         (accent (if accent (color accent) foreground))
         (theme (%make-theme :name name
                             :description description
                             :font font
                             :foreground foreground
                             :background background
                             :surface surface
                             :accent accent
                             :muted (if muted (color muted) foreground)
                             :error (if error (color error) accent)
                             :border-focus (if border-focus (color border-focus) accent)
                             :border-unfocus (if border-unfocus (color border-unfocus) surface)
                             :wallpaper (and wallpaper (uiop:native-namestring wallpaper))
                             :wallpaper-color (if wallpaper-color
                                                  (color wallpaper-color)
                                                  background))))
    (setf (gethash name *themes*) theme)
    ;; Redefining the theme in use shows the change:
    (when (and *theme* (eq (theme-name *theme*) name))
      (set-theme theme))
    theme))

(defun find-theme (name &key (errorp t))
  "The theme named NAME, loading the user's theme files when it is not
known yet. Signals an error when there is none, unless ERRORP is NIL."
  (or (gethash name *themes*)
      (progn (load-user-themes)
             (gethash name *themes*))
      (and errorp
           (error "No theme named ~S. Known: ~{~(~A~)~^, ~}"
                  name (theme-names)))))

(defun theme-names ()
  "The names of the themes known, sorted."
  (sort (alexandria:hash-table-keys *themes*) #'string< :key #'symbol-name))

(defun load-user-themes ()
  "Load the *.lisp files in *theme-directories*. A file that fails is
logged and skipped."
  (dolist (directory *theme-directories*)
    (dolist (file (directory (merge-pathnames "*.lisp" directory)))
      (handler-case (let ((*package* (find-package :mahogany)))
                      (load file))
        (error (c)
          (log-string :error "Could not load the theme file ~A: ~A" file c))))))

;;; Applying a theme

(defun %widget-theme (theme &key (font-color (theme-foreground theme))
                                 (border-color (theme-accent theme)))
  (mh/theme:make-theme :font (theme-font theme)
                       :font-color font-color
                       :background-color (theme-background theme)
                       :border-color border-color))

(defun %apply-frame-borders (theme)
  ;; The styles are shared by every frame and updated in place, so the
  ;; frames show the new colors at once. The widths stay as
  ;; init-frame-border-styles made them.
  (let ((width (coerce tree::*frame-border-width* 'double-float)))
    (when tree::*frame-focus-border-style*
      (hrt:border-box-style-update tree::*frame-focus-border-style*
                                   :hrt-border-solid (theme-border-focus theme) width)
      (hrt:border-box-style-update tree::*frame-unfocus-border-style*
                                   :hrt-border-solid (theme-border-unfocus theme) (* width 2))
      (hrt:border-box-style-update tree::*frame-unfocus-empty-border-style*
                                   :hrt-border-dotted (theme-muted theme) width))))

(defun %save-theme-name (name)
  (ignore-errors
   (let ((file (state-file "theme.sexp")))
     (ensure-directories-exist file)
     (with-open-file (out file :direction :output :if-exists :supersede)
       (prin1 name out)
       (terpri out)))))

(defun %saved-theme-name ()
  (ignore-errors
   (with-open-file (in (state-file "theme.sexp") :if-does-not-exist nil)
     (when in
       (let ((*read-eval* nil)
             (*package* (find-package :keyword)))
         (let ((name (read in nil)))
           (and (keywordp name) name)))))))

(defun set-theme (designator)
  "Put the theme DESIGNATOR (a name or a theme) to use everywhere: the
mode-line, menus, the on-screen display, messages, frame borders and
the wallpaper, and remember it for the next start. Returns the theme."
  (let ((theme (if (theme-p designator) designator (find-theme designator))))
    (setf *theme* theme
          *mode-line-theme* (%widget-theme theme)
          *menu-theme* (%widget-theme theme)
          *osd-theme* (%widget-theme theme)
          *message-theme* (%widget-theme theme)
          *message-error-theme* (%widget-theme theme
                                               :font-color (theme-error theme)
                                               :border-color (theme-error theme)))
    (%apply-frame-borders theme)
    (when (state-server *compositor-state*)
      (wallpaper-update)
      (mode-line-update)
      (hrt:dirty-view-transaction))
    (%save-theme-name (theme-name theme))
    (dolist (hook *theme-hooks*)
      (handler-case (funcall hook theme)
        (error (c)
          (log-string :error "Theme hook ~S failed: ~A" hook c))))
    theme))

(defun theme-start ()
  "At startup: load the user's themes and apply the one remembered, or
*default-theme*, unless init.lisp has set one already."
  (load-user-themes)
  (unless *theme*
    (let ((saved (%saved-theme-name)))
      (set-theme (or (and saved (find-theme saved :errorp nil))
                     (find-theme *default-theme* :errorp nil)
                     (find-theme :mahogany))))))

(defun cycle-theme (&optional (step 1))
  "Switch to the next theme by name (the previous one with a negative
STEP). Returns it."
  (let* ((names (theme-names))
         (position (or (and *theme* (position (theme-name *theme*) names)) -1)))
    (set-theme (nth (mod (+ position step) (length names)) names))))

(defcommand next-theme ()
  (:documentation "Switch to the next theme")
  (:method ()
    (toast-message *compositor-state*
                   (format nil "Theme: ~(~A~)" (theme-name (cycle-theme))))))

(defcommand previous-theme ()
  (:documentation "Switch to the previous theme")
  (:method ()
    (toast-message *compositor-state*
                   (format nil "Theme: ~(~A~)" (theme-name (cycle-theme -1))))))

(defcommand reload-themes ()
  (:documentation "Load the theme files again and apply the current theme anew")
  (:method ()
    (load-user-themes)
    (when *theme*
      (set-theme (or (find-theme (theme-name *theme*) :errorp nil) *theme*)))))

(defcommand theme-menu ()
  (:documentation "Choose a theme")
  (:method () (launcher :theme)))

(define-launcher-mode :theme (:prompt "Theme" :description "Themes")
  :items (loop for name in (theme-names)
               for theme = (gethash name *themes*)
               collect (make-menu-item (string-downcase name)
                                       :data name
                                       :detail (if (eq theme *theme*)
                                                   "current"
                                                   (theme-description theme))))
  :action (lambda (name)
            (set-theme name)
            (toast-message *compositor-state* (format nil "Theme: ~(~A~)" name))))

;;; The wallpaper: a canvas on the background layer of each output,
;;; showing the theme's PNG scaled to cover the output (or *wallpaper*),
;;; else a plain color. Redrawn when the theme, the wallpaper or the
;;; outputs change.

(defstruct (wallpaper (:constructor %make-wallpaper (output canvas)))
  output canvas
  (drawn nil))  ; (file color width height) of the last drawing

(defglobal *wallpapers* (make-hash-table :test 'equal)
  "The wallpapers of the outputs, by output name.")

(defglobal *wallpaper-image* nil
  "(file . cairo surface) of the wallpaper loaded last.")

(defun wallpaper-file ()
  "The wallpaper file in use: *wallpaper*, else the theme's, or NIL."
  (let ((file (or *wallpaper* (and *theme* (theme-wallpaper *theme*)))))
    (and file (uiop:native-namestring file))))

(defun wallpaper-color ()
  (if *theme*
      (theme-wallpaper-color *theme*)
      (colors:rgb 0.1 0.1 0.12)))

(defun %wallpaper-image (file)
  "The image surface of FILE, loaded once; NIL when it cannot be read."
  (unless (and *wallpaper-image* (equal (car *wallpaper-image*) file))
    (when *wallpaper-image*
      (draw:cairo-surface-destroy (cdr *wallpaper-image*))
      (setf *wallpaper-image* nil))
    (when file
      (let ((image (draw:load-png file)))
        (if image
            (setf *wallpaper-image* (cons file image))
            (log-string :error "Could not read the wallpaper ~A (a PNG file is needed)"
                        file)))))
  (cdr *wallpaper-image*))

(defun %ensure-wallpaper (output)
  (let ((name (hrt:output-full-name output)))
    (or (gethash name *wallpapers*)
        (let* ((canvas (hrt:make-canvas output :layer :layer-background))
               (wallpaper (%make-wallpaper output canvas)))
          ;; A click on the wallpaper is a click on an empty frame:
          (setf (hrt:canvas-on-button canvas)
                (lambda (canvas x y button pressed)
                  (declare (ignore canvas x y button))
                  (when (and pressed
                             (not (zerop (logand *keyboard-focus-bits* +click-mask+))))
                    (%focus-frame-under-cursor (server-seat *compositor-state*)))))
          (setf (gethash name *wallpapers*) wallpaper)))))

(defun %wallpaper-draw (wallpaper)
  (let ((output (wallpaper-output wallpaper))
        (canvas (wallpaper-canvas wallpaper))
        (file (wallpaper-file))
        (color (wallpaper-color)))
    (multiple-value-bind (width height) (hrt:output-logical-size output)
      (let ((key (list file color width height
                       (multiple-value-list (hrt:output-position output)))))
        (unless (equal key (wallpaper-drawn wallpaper))
          (let ((image (%wallpaper-image file)))
            (hrt:canvas-set-position canvas 0 0)
            (hrt:with-canvas-frame (cr canvas width height)
              (draw:clear cr color)
              (when image
                (draw:draw-image-cover cr image width height))))
          (setf (wallpaper-drawn wallpaper) key))))))

(defun wallpaper-update ()
  "Draw the wallpaper on the outputs in use, where it is not drawn as
it should be, dropping those of outputs that have gone."
  (when (and *theme* (state-server *compositor-state*))
    ;; An output just turned off is still among those in use until its
    ;; removal is processed; drawing on it faults in heart.
    (let ((outputs (remove-if-not #'hrt:output-enabled
                                  (map 'list #'tree:output-container-output
                                       (state-cur-outputs *compositor-state*)))))
      (maphash (lambda (name wallpaper)
                 (when (or (hrt:canvas-destroyed-p (wallpaper-canvas wallpaper))
                           (not (member (wallpaper-output wallpaper) outputs
                                        :test #'hrt:output=)))
                   (remhash name *wallpapers*)
                   (unless (hrt:canvas-destroyed-p (wallpaper-canvas wallpaper))
                     (hrt:canvas-destroy (wallpaper-canvas wallpaper)))))
               *wallpapers*)
      (dolist (output outputs)
        (handler-case (%wallpaper-draw (%ensure-wallpaper output))
          (error (c)
            (log-string :error "Could not draw the wallpaper of ~S: ~A"
                        (hrt:output-full-name output) c)))))))

(defun wallpaper-reset ()
  "Forget the wallpapers; the canvases go with their outputs."
  (clrhash *wallpapers*)
  (when *wallpaper-image*
    (draw:cairo-surface-destroy (cdr *wallpaper-image*))
    (setf *wallpaper-image* nil)))

(defun set-wallpaper (file)
  "Show the PNG FILE as the wallpaper on every output, in place of the
theme's; NIL goes back to the theme's."
  (setf *wallpaper* (and file (uiop:native-namestring file)))
  (wallpaper-update)
  file)

(defcommand wallpaper
    ((file (:function interactively-read-string :data "Wallpaper (PNG)")))
  (:documentation "Show a PNG file as the wallpaper")
  (:method ((file string))
    (set-wallpaper (if (string= file "") nil file))))

;;; The built-in themes

(define-theme :mahogany
  :description "The colors Mahogany had before themes"
  :foreground "#e6e6e6" :background "#1a1a1f" :surface "#000000"
  :accent "#cc4d33" :muted "#cccccc" :error "#ff0000"
  :border-focus "#ace1af")

(define-theme :tokyo-night
  :description "Tokyo Night"
  :foreground "#c0caf5" :background "#1a1b26" :surface "#24283b"
  :accent "#7aa2f7" :muted "#565f89" :error "#f7768e")

(define-theme :catppuccin
  :description "Catppuccin Mocha"
  :foreground "#cdd6f4" :background "#1e1e2e" :surface "#313244"
  :accent "#cba6f7" :muted "#6c7086" :error "#f38ba8")

(define-theme :catppuccin-latte
  :description "Catppuccin Latte, light"
  :foreground "#4c4f69" :background "#eff1f5" :surface "#ccd0da"
  :accent "#8839ef" :muted "#9ca0b0" :error "#d20f39")

(define-theme :nord
  :description "Nord"
  :foreground "#d8dee9" :background "#2e3440" :surface "#3b4252"
  :accent "#88c0d0" :muted "#4c566a" :error "#bf616a")

(define-theme :gruvbox
  :description "Gruvbox dark"
  :foreground "#ebdbb2" :background "#282828" :surface "#3c3836"
  :accent "#d79921" :muted "#928374" :error "#fb4934")

(define-theme :everforest
  :description "Everforest dark"
  :foreground "#d3c6aa" :background "#2d353b" :surface "#3d484d"
  :accent "#a7c080" :muted "#859289" :error "#e67e80")

(define-theme :kanagawa
  :description "Kanagawa"
  :foreground "#dcd7ba" :background "#1f1f28" :surface "#2a2a37"
  :accent "#7e9cd8" :muted "#727169" :error "#c34043")

(define-theme :rose-pine
  :description "Rosé Pine"
  :foreground "#e0def4" :background "#191724" :surface "#26233a"
  :accent "#ebbcba" :muted "#6e6a86" :error "#eb6f92")

(define-theme :matte-black
  :description "Matte black"
  :foreground "#eaeaea" :background "#121212" :surface "#1f1f1f"
  :accent "#8a8a8d" :muted "#5c5c5c" :error "#d35f5f")
