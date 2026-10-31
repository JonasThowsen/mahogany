(in-package #:mahogany)

;; In osd.lisp, which loads after this file:
(declaim (ftype function %show-volume))

;;; The mode-line: a bar at the top (or bottom) of each output, drawn by
;;; Lisp on a canvas, as StumpWM's. It shows segments: the groups with
;;; the current one marked, the focused window's title, the clock, and
;;; whatever functions the user adds. It is redrawn on a timer and when
;;; groups change; everything about it can be changed in init.lisp or
;;; live from the REPL, and the next redraw shows it.

(config:defconfig *mode-line-enabled* t
  boolean
  "Whether the mode-line is shown. The mode-line command toggles it.")

(config:defconfig *mode-line-position* :top
  (member :top :bottom)
  "The edge of each output the mode-line sits at.")

(config:defconfig *mode-line-height* 28
  fixnum
  "The height of the mode-line in layout pixels.")

(config:defconfig *mode-line-padding* 12
  fixnum
  "Space in layout pixels at the ends of the mode-line and between its
segments.")

(config:defconfig *mode-line-theme*
    (mh/theme:make-theme :font "monospace 12"
                         :font-color (colors:rgb 0.9 0.9 0.9)
                         :background-color (colors:rgb 0.1 0.1 0.12)
                         :border-color (colors:rgb 0.8 0.3 0.2))
  mh/theme:theme
  "Colors and font of the mode-line. The border color marks the current
group.")

(config:defconfig *mode-line-segments*
    '(:groups :title :center :date :clock :fill :network :volume :brightness :battery)
  list
  "What the mode-line shows, left to right: the names of modules
(define-mode-line-module; built in: :groups, :title, :clock, :date,
:network, :volume, :brightness, :battery), :center (what follows is
centred), :fill (the rest goes to the right end), a function of the
output returning a string, or NIL for nothing. Modules with nothing to
show, such as :battery on a desktop, take no room.")

(config:defconfig *mode-line-icons* t
  boolean
  "Whether modules show their icons (Nerd Font glyphs, which need a Nerd
Font such as Symbols Nerd Font installed) before their text.")

(config:defconfig *icons*
    (list :battery-charging (string (code-char #xF0084))
          :battery-full (string (code-char #xF0079))
          :battery-levels (list (string (code-char #xF008E))  ; empty
                                (string (code-char #xF007A))  ; 10
                                (string (code-char #xF007B))
                                (string (code-char #xF007C))
                                (string (code-char #xF007D))
                                (string (code-char #xF007E))  ; 50
                                (string (code-char #xF007F))
                                (string (code-char #xF0080))
                                (string (code-char #xF0081))
                                (string (code-char #xF0082))  ; 90
                                (string (code-char #xF0079)))
          :wifi (string (code-char #xF0928))
          :wired (string (code-char #xF0200))
          :offline (string (code-char #xF092D))
          :volume (string (code-char #xF057E))
          :volume-muted (string (code-char #xF0581))
          :microphone (string (code-char #xF036C))
          :brightness (string (code-char #xF00E0))
          :clock (string (code-char #xF0954))
          :calendar (string (code-char #xF00ED)))
  list
  "The icons, Nerd Font glyphs by default, by name. Replace an entry to
use another glyph or a plain character.")

(defun icon (name)
  "The icon NAME as a string, or NIL when icons are off or NAME is unknown."
  (when *mode-line-icons*
    (let ((icon (getf *icons* name)))
      (if (stringp icon) icon nil))))

(config:defconfig *mode-line-timeout* 1000
  fixnum
  "Milliseconds between redraws of the mode-line, for the clock and
window titles. Group and focus changes redraw it at once.")

(defstruct (mode-line (:constructor %make-mode-line (output canvas)))
  (output nil :type hrt:output :read-only t)
  (canvas nil :type hrt:canvas :read-only t)
  ;; What a click, the wheel or the pointer coming over does where: a
  ;; list of (X0 X1 ON-CLICK ON-SCROLL ON-HOVER), from the last draw.
  (hits '() :type list)
  ;; The ON-HOVER of the item under the pointer, so it runs once as the
  ;; pointer comes over the item, not at every motion:
  (hovered nil))

(defglobal *mode-lines* (make-hash-table :test 'equal)
  "The mode-line of each output, by the output's full name.")

(defglobal *mode-line-timer* nil
  "The timer that redraws the mode-lines, while they are shown.")

;;; Modules

(defstruct (mode-line-module (:constructor %make-mode-line-module))
  (name nil :type keyword)
  ;; (output) -> the text to show, or NIL to show nothing:
  (text nil :type function)
  ;; A string, or the name of an icon in *icons*:
  (icon nil)
  ;; A color for this module's text, or NIL for the theme's:
  (color nil)
  ;; () and (delta): what a click and the wheel over the module do:
  (on-click nil :type (or null function))
  (on-scroll nil :type (or null function))
  ;; (): what the pointer coming over the module does:
  (on-hover nil :type (or null function))
  ;; Seconds between calls of REFRESH, a function starting whatever
  ;; (asynchronous) reading the text needs:
  (interval nil)
  (refresh nil :type (or null function))
  (last-refresh 0))

(defglobal *mode-line-modules* (make-hash-table)
  "The mode-line's modules, by name.")

(defun register-mode-line-module (name &key text icon color on-click on-scroll on-hover
                                             interval refresh)
  (check-type name keyword)
  (setf (gethash name *mode-line-modules*)
        (%make-mode-line-module :name name :text text :icon icon :color color
                                :on-click on-click :on-scroll on-scroll :on-hover on-hover
                                :interval interval :refresh refresh))
  name)

(defmacro define-mode-line-module (name (&key icon color on-click on-scroll on-hover
                                               interval refresh)
                                   &body text-body)
  "Define a module the mode-line can show, named by the keyword NAME.
TEXT-BODY is evaluated at every redraw, with OUTPUT bound to the output,
and gives the text to show, or NIL for nothing. It runs on the main
thread, which stops the compositor while it runs: it must be quick, so
no reading that can wait (a battery, a program). ICON is a string or the
name of an icon in *icons*, shown before the text. COLOR, a cl-colors2
rgb, colors the text. ON-CLICK is a function of no arguments; ON-SCROLL
a function of the wheel's direction, 1 or -1; ON-HOVER a function of no
arguments, called when the pointer comes over the module. REFRESH is a function
called every INTERVAL seconds to start reading something asynchronously
(see run-async), for text that is not cheap to get.

  (define-mode-line-module :uptime (:icon \"⏱\" :interval 60)
    (with-open-file (in \"/proc/uptime\")
      (format nil \"~Dh\" (floor (read in) 3600))))

Then add :uptime to *mode-line-segments*."
  `(register-mode-line-module ,name
                              :text (lambda (output) (declare (ignorable output)) ,@text-body)
                              :icon ,icon :color ,color
                              :on-click ,on-click :on-scroll ,on-scroll :on-hover ,on-hover
                              :interval ,interval :refresh ,refresh))

(defun %module-item (module output)
  "The item of MODULE for OUTPUT, or NIL when it shows nothing."
  (let ((text (handler-case (funcall (mode-line-module-text module) output)
                (error (c)
                  (log-string :error "Mode-line module ~S: ~A" (mode-line-module-name module) c)
                  nil))))
    (when (and text (plusp (length text)))
      (let* ((icon (mode-line-module-icon module))
             (icon (cond ((stringp icon) (and *mode-line-icons* icon))
                         ((keywordp icon) (icon icon))
                         (t nil))))
        (list :text (if icon (format nil "~A ~A" icon text) text)
              :color (mode-line-module-color module)
              :on-click (mode-line-module-on-click module)
              :on-scroll (mode-line-module-on-scroll module)
              :on-hover (mode-line-module-on-hover module))))))

(defun %refresh-modules ()
  "Start the asynchronous refreshes that are due."
  (let ((now (get-universal-time)))
    (dolist (segment *mode-line-segments*)
      (alexandria:when-let ((module (and (keywordp segment)
                                         (gethash segment *mode-line-modules*))))
        (when (and (mode-line-module-refresh module)
                   (>= (- now (mode-line-module-last-refresh module))
                       (or (mode-line-module-interval module) 10)))
          (setf (mode-line-module-last-refresh module) now)
          (handler-case (funcall (mode-line-module-refresh module))
            (error (c)
              (log-string :error "Mode-line module ~S refresh: ~A" segment c))))))))

;;; Segments

(defparameter +day-names+ #("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))
(defparameter +month-names+
  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(defun mode-line-clock ()
  (multiple-value-bind (sec min hour) (get-decoded-time)
    (declare (ignore sec))
    (format nil "~2,'0D:~2,'0D" hour min)))

(defun mode-line-date ()
  (multiple-value-bind (sec min hour day month year weekday) (get-decoded-time)
    (declare (ignore sec min hour year))
    (format nil "~A ~D ~A" (aref +day-names+ weekday) day
            (aref +month-names+ (1- month)))))

(defun mode-line-title ()
  "The title of the focused window, or NIL."
  (let ((frame (state-current-frame *compositor-state*)))
    (when (typep frame 'tree:view-frame)
      (alexandria:when-let ((view (tree:frame-surface frame)))
        (let ((title (hrt:view-title view)))
          (and title (plusp (length title)) title))))))

(defun %mode-line-groups (output)
  "The groups of OUTPUT in order of their numbers, as (name shown-p
group), the one it shows marked."
  (let ((shown (state-output-group *compositor-state* output)))
    (mapcar (lambda (group)
              (list (mahogany-group-name group) (eq group shown) group))
            (remove-if-not #'group-listed-p (output-groups *compositor-state* output)))))

(defun %mode-line-items (output)
  "What to draw for OUTPUT, as a list of items: (:text STRING &key
marked flexible) and :fill."
  (let ((items '()))
    (dolist (segment *mode-line-segments* (nreverse items))
      (flet ((add (text &rest options &key icon &allow-other-keys)
               (when (and text (plusp (length text)))
                 (push (list* :text (if icon (format nil "~A ~A" icon text) text)
                              (alexandria:remove-from-plist options :icon))
                       items))))
        (case segment
          ;; The groups: the shown one marked, the empty ones dimmed.
          (:groups (loop for (name current group) in (%mode-line-groups output)
                         do (add name :marked current
                                 :dim (and (not current) (null (mahogany-group-views group)))
                                 :on-click (let ((group group))
                                             (lambda ()
                                               (setf (state-current-group *compositor-state*)
                                                     group))))))
          (:center (push :center items))
          (:title (add (mode-line-title) :flexible t))
          (:clock (add (mode-line-clock) :icon (icon :clock)))
          (:date (add (mode-line-date) :icon (icon :calendar)))
          (:fill (push :fill items))
          ((nil))
          (t (let ((module (and (keywordp segment) (gethash segment *mode-line-modules*))))
               (cond (module
                      (alexandria:when-let ((item (%module-item module output)))
                        (push item items)))
                     ((keywordp segment)
                      (log-string :warn "No mode-line module ~S" segment))
                     (t (add (handler-case (funcall segment output)
                               (error (c)
                                 (log-string :error "Mode-line segment ~S: ~A" segment c)
                                 nil))))))))))))

;;; Drawing

(defun %draw-mode-line-items (cr items width height theme)
  "Lay ITEMS out on a WIDTH x HEIGHT bar and draw them: the items before
:center or :fill from the left, those between :center and :fill in the
middle, the rest from the right, and a :flexible item taking the room
that is left, shortened to it. Returns the clickable places as a list
of (X0 X1 ON-CLICK ON-SCROLL)."
  (let* ((font (mh/theme:theme-font theme))
         (pad *mode-line-padding*)
         (chip-pad (round pad 2))
         (center-position (position :center items))
         (fill (position :fill items))
         (left (subseq items 0 (or center-position fill (length items))))
         (center (if center-position
                     (subseq items (1+ center-position) (or fill (length items)))
                     '()))
         (right (if fill (subseq items (1+ fill)) '()))
         (hits '()))
    (labels ((text-width (item)
               (multiple-value-bind (w h) (draw:text-size cr (getf item :text) :font font)
                 (declare (ignore h))
                 (+ w (if (getf item :marked) (* 2 chip-pad) 0))))
             (fixed-width (items)
               (loop for item in items
                     unless (getf item :flexible)
                       sum (+ (text-width item) pad)))
             (draw-item (item x available)
               "Draw ITEM at X in at most AVAILABLE pixels; return its width."
               (destructuring-bind (&key text marked dim flexible on-click on-scroll on-hover color)
                   item
                 (let* ((room (if flexible (max 0 (- available pad)) nil))
                        (chip (if marked chip-pad 0))
                        (font-color (mh/theme:theme-font-color theme))
                        (text-color (cond (color color)
                                          ;; On the accent chip, the background color stands out:
                                          (marked (mh/theme:theme-background-color theme))
                                          (dim (list (colors:rgb-red font-color)
                                                     (colors:rgb-green font-color)
                                                     (colors:rgb-blue font-color)
                                                     0.45))
                                          (t font-color))))
                   (draw:with-layout (layout cr :text text :font font
                                                :width (when room (- room (* 2 chip)))
                                                :ellipsize (when room :end))
                     (multiple-value-bind (w h) (draw:layout-pixel-size layout)
                       (let ((y (round (- height h) 2)))
                         (when marked
                           (draw:fill-rounded-rectangle
                            cr x (- y (round chip 2)) (+ w (* 2 chip)) (+ h chip) 5
                            (mh/theme:theme-border-color theme)))
                         (draw:show-layout cr layout (+ x chip) y text-color)
                         (when (or on-click on-scroll on-hover)
                           (push (list x (+ x w (* 2 chip)) on-click on-scroll on-hover) hits))
                         (+ w (* 2 chip)))))))))
      ;; From the right end first, so the left side knows its room:
      (let ((x (- width pad)))
        (dolist (item (reverse right))
          (let ((w (text-width item)))
            (decf x w)
            (draw-item item x w)
            (decf x pad)))
        (let ((right-edge x))
          ;; The centre block, in the middle of the bar unless the
          ;; right side reaches there:
          (when center
            (let* ((block-width (- (fixed-width center) pad))
                   (start (min (round (- width block-width) 2)
                               (- right-edge pad block-width)))
                   (x (max pad start)))
              (dolist (item center)
                (incf x (+ (draw-item item x (text-width item)) pad)))
              (setf right-edge (- (max pad start) pad))))
          (let ((x pad))
            (dolist (item left)
              (let ((available (- right-edge x
                                  (fixed-width (cdr (member item left))))))
                (incf x (+ (draw-item item x available) pad)))))))
      hits)))

(defun mode-line-draw (mode-line)
  "Draw MODE-LINE for its output as it is now."
  (let* ((output (mode-line-output mode-line))
         (canvas (mode-line-canvas mode-line))
         (theme *mode-line-theme*)
         (height *mode-line-height*))
    (multiple-value-bind (width output-height) (hrt:output-logical-size output)
      (hrt:canvas-set-position canvas 0 (if (eq *mode-line-position* :bottom)
                                            (- output-height height)
                                            0))
      (hrt:with-canvas-frame (cr canvas width height)
        (draw:clear cr (mh/theme:theme-background-color theme))
        (setf (mode-line-hits mode-line)
              (%draw-mode-line-items cr (%mode-line-items output) width height theme))))))

(defun %mode-line-click (mode-line x y button pressed)
  "A click on MODE-LINE: run what is under X."
  (declare (ignore y))
  (when (and pressed (= button hrt:+button-left+))
    (loop for (x0 x1 on-click) in (mode-line-hits mode-line)
          when (and on-click (<= x0 x x1))
            do (funcall on-click)
               (mode-line-update)
               (return))))

(defun %mode-line-scroll (mode-line x vertical delta)
  "The wheel over MODE-LINE at X: the module there takes it (the volume,
say), otherwise it goes through the groups."
  (when vertical
    (let ((direction (if (plusp delta) 1 -1)))
      (loop for (x0 x1 nil on-scroll) in (mode-line-hits mode-line)
            when (and on-scroll (<= x0 x x1))
              do (funcall on-scroll direction)
                 (return-from %mode-line-scroll))
      (state-next-group *compositor-state* :step direction
                                           :output (mode-line-output mode-line)))))

(defun %mode-line-motion (mode-line x)
  "The pointer over MODE-LINE at X: when it has come over an item with
an ON-HOVER, run that, once until it leaves the item."
  (let ((on-hover (loop for (x0 x1 nil nil on-hover) in (mode-line-hits mode-line)
                        when (and on-hover (<= x0 x x1))
                          return on-hover)))
    (unless (eq on-hover (mode-line-hovered mode-line))
      (setf (mode-line-hovered mode-line) on-hover)
      (when on-hover
        (handler-case (funcall on-hover)
          (error (c) (log-string :error "Mode-line hover: ~A" c)))))))

;;; Mode-lines of the outputs

(defun %mode-line-reserve (output height)
  (if (eq *mode-line-position* :bottom)
      (hrt:output-set-reserved output :bottom height)
      (hrt:output-set-reserved output :top height)))

(defun %ensure-mode-line (output)
  "The mode-line of OUTPUT, made if it has none."
  (let ((name (hrt:output-full-name output)))
    (or (gethash name *mode-lines*)
        (let* ((canvas (hrt:make-canvas output :layer :layer-top))
               (mode-line (%make-mode-line output canvas)))
          (setf (hrt:canvas-on-button canvas)
                (lambda (canvas x y button pressed)
                  (declare (ignore canvas))
                  (%mode-line-click mode-line x y button pressed))
                (hrt:canvas-on-axis canvas)
                (lambda (canvas x y vertical delta)
                  (declare (ignore canvas y))
                  (%mode-line-scroll mode-line x vertical delta))
                (hrt:canvas-on-motion canvas)
                (lambda (canvas x y)
                  (declare (ignore canvas y))
                  (%mode-line-motion mode-line x))
                (hrt:canvas-on-leave canvas)
                (lambda (canvas)
                  (declare (ignore canvas))
                  (setf (mode-line-hovered mode-line) nil)))
          (%mode-line-reserve output *mode-line-height*)
          (setf (gethash name *mode-lines*) mode-line)))))

(defun %remove-mode-line (mode-line)
  (let ((output (mode-line-output mode-line)))
    (remhash (hrt:output-full-name output) *mode-lines*)
    (unless (hrt:canvas-destroyed-p (mode-line-canvas mode-line))
      (hrt:canvas-destroy (mode-line-canvas mode-line))
      ;; An output switched off has no layers to arrange:
      (when (hrt:output-enabled output)
        (hrt:output-set-reserved output)))))

(defun mode-line-update ()
  "Redraw the mode-lines of the outputs in use, making those that are
missing and dropping those of outputs that have gone."
  (when (and *mode-line-enabled* (state-server *compositor-state*))
    (%refresh-modules)
    ;; Not on an output just turned off, still in use until its removal
    ;; is processed:
    (let ((outputs (remove-if-not #'hrt:output-enabled
                                  (map 'list #'tree:output-container-output
                                       (state-cur-outputs *compositor-state*)))))
      (maphash (lambda (name mode-line)
                 (declare (ignore name))
                 (when (or (hrt:canvas-destroyed-p (mode-line-canvas mode-line))
                           (not (member (mode-line-output mode-line) outputs
                                        :test #'hrt:output=)))
                   (%remove-mode-line mode-line)))
               *mode-lines*)
      (dolist (output outputs)
        (handler-case (mode-line-draw (%ensure-mode-line output))
          (error (c)
            (log-string :error "Could not draw the mode-line of ~S: ~A"
                        (hrt:output-full-name output) c)))))))

(defun %mode-line-timer-fired (timer)
  (declare (type hrt:timer-handle timer))
  (cond (*mode-line-enabled*
         (mode-line-update)
         (hrt:timer-handle-update timer *mode-line-timeout*))
        (t
         (hrt:timer-handle-destroy timer)
         (setf *mode-line-timer* nil))))

(defun mode-line-start ()
  "Show the mode-lines and keep them up to date."
  (setf *mode-line-enabled* t)
  (mode-line-update)
  (unless *mode-line-timer*
    (setf *mode-line-timer*
          (hrt:server-make-timer (state-server *compositor-state*)
                                 #'%mode-line-timer-fired))
    (hrt:timer-handle-update *mode-line-timer* *mode-line-timeout*)))

(defun mode-line-stop ()
  "Take the mode-lines down and give their space back."
  (setf *mode-line-enabled* nil)
  (when *mode-line-timer*
    (hrt:timer-handle-destroy *mode-line-timer*)
    (setf *mode-line-timer* nil))
  (maphash (lambda (name mode-line)
             (declare (ignore name))
             (%remove-mode-line mode-line))
           *mode-lines*)
  (clrhash *mode-lines*))

(defun mode-line-reset ()
  "Take the mode-lines and their timer down for shutdown, leaving
*mode-line-enabled* as the user set it."
  (when *mode-line-timer*
    (hrt:timer-handle-destroy *mode-line-timer*)
    (setf *mode-line-timer* nil))
  (maphash (lambda (name mode-line)
             (declare (ignore name))
             (%remove-mode-line mode-line))
           *mode-lines*)
  (clrhash *mode-lines*))

(defcommand mode-line ()
  (:documentation "Toggle the mode-line")
  (:method ()
    (if *mode-line-enabled*
        (mode-line-stop)
        (mode-line-start))))

;;; The built-in modules

(defun %battery-refresh-and-redraw ()
  (battery-refresh (lambda (status)
                     (declare (ignore status))
                     (mode-line-update))))

;; Every 30 seconds, and at once when the pointer comes over it:
(define-mode-line-module :battery (:icon :battery-full
                                   :interval 30
                                   :refresh #'%battery-refresh-and-redraw
                                   :on-hover #'%battery-refresh-and-redraw)
  ;; The last reading: reading the battery here, at every redraw, would
  ;; stop the compositor while the kernel asks the firmware.
  (alexandria:when-let ((status *battery-status*))
    (let* ((percent (getf status :percent))
           (state (getf status :state))
           (module (gethash :battery *mode-line-modules*)))
      ;; The battery's icon and color follow its level:
      (setf (mode-line-module-icon module)
            (if (member state '(:charging :full))
                :battery-charging
                (nth (min 10 (floor percent 10)) (getf *icons* :battery-levels)))
            (mode-line-module-color module)
            (when (and (eq state :discharging) (<= percent 15))
              (colors:rgb 0.95 0.3 0.3)))
      (format nil "~D%" percent))))

(define-mode-line-module :brightness (:icon :brightness
                                      :on-scroll (lambda (direction)
                                                   (brightness-change (* direction *brightness-step*)
                                                                      (lambda (percent)
                                                                        (declare (ignore percent))
                                                                        (mode-line-update)))))
  (alexandria:when-let ((percent (brightness-percent)))
    (format nil "~D%" percent)))

(define-mode-line-module :volume (:icon :volume
                                  :interval 5
                                  :refresh (lambda () (volume-refresh (lambda (status)
                                                                        (declare (ignore status))
                                                                        (mode-line-update))))
                                  :on-click (lambda () (volume-toggle-mute #'%show-volume))
                                  :on-scroll (lambda (direction)
                                               (volume-change (* direction *volume-step*) #'%show-volume)))
  (alexandria:when-let ((status *volume-status*))
    (let ((module (gethash :volume *mode-line-modules*)))
      (setf (mode-line-module-icon module)
            (if (getf status :muted) :volume-muted :volume)))
    (if (getf status :muted)
        "muted"
        (format nil "~D%" (getf status :percent)))))

(declaim (ftype function wifi-menu))
(define-mode-line-module :network (:icon :offline
                                   :interval 10
                                   :on-click (lambda () (wifi-menu))
                                   :refresh (lambda () (network-refresh (lambda (status)
                                                                          (declare (ignore status))
                                                                          (mode-line-update)))))
  (let ((status *network-status*)
        (module (gethash :network *mode-line-modules*)))
    (setf (mode-line-module-icon module)
          (case (getf status :kind) (:wifi :wifi) (:wired :wired) (t :offline)))
    (cond ((null status) "offline")
          ((eq (getf status :kind) :wifi) (or (getf status :ssid) (getf status :interface)))
          (t (getf status :interface)))))
