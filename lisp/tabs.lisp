(in-package #:mahogany)

;;; Tabs: the :tabs layout shows one window at a time, as :monocle does,
;;; and a strip under the mode-line names every window of the group,
;;; the shown one marked, as dwm's monocle with a tab bar. A click on a
;;; name shows that window, the wheel over the strip goes through them;
;;; s-Tab (next-view) does too. The strip is drawn per output on a
;;; canvas of its own, and the mode-line reserves its height along with
;;; its own while a :tabs group is shown, so the window sits below both.

(config:defconfig *tab-bar-height* 26
  (integer 10 100)
  "The height of the tab strip of the :tabs layout, in layout pixels.")

(config:defconfig *tab-width* 240
  (integer 40 2000)
  "The most a tab takes in width; tabs shrink to fit the strip.")

(define-layout :tabs (n ratio width height)
    "One window at a time, with a tab for each at the top"
  :leaf)

(defstruct (tab-bar (:constructor %make-tab-bar (output canvas)))
  (output nil :type hrt:output :read-only t)
  (canvas nil :type hrt:canvas :read-only t)
  ;; (X0 X1 VIEW) of the tabs, from the last draw, for clicks:
  (hits '() :type list)
  ;; What was drawn last, so an unchanged strip is not drawn again:
  (drawn nil))

(defglobal *tab-bars* (make-hash-table :test 'equal)
  "The tab strip of each output, by the output's full name.")

(defun %tabs-group (output)
  "The group shown on OUTPUT when it has the :tabs layout, else NIL."
  (let ((group (state-output-group *compositor-state* output)))
    (and group (eq (group-layout group) :tabs) group)))

(defun tab-bar-height (output)
  "What the tab strip takes at the top of OUTPUT: its height while a
:tabs group is shown there, else 0."
  (if (%tabs-group output) *tab-bar-height* 0))

(defun %tab-views (group)
  "The windows GROUP's tabs name, oldest first; floating ones are not
in the stack."
  (remove-if (lambda (view) (typep (hrt::view-container view) 'tree:floating-frame))
             (reverse (mahogany-group-views group))))

(defun %tab-shown-view (group)
  "The window GROUP shows in its frame, or NIL."
  (alexandria:when-let ((node (group-output-node group)))
    (let ((leaf (tree:find-first-leaf node)))
      (and (typep leaf 'tree:view-frame) (tree:frame-surface leaf)))))

(defun %tab-title (view)
  (let ((title (hrt:view-title view)))
    (if (and title (plusp (length title)))
        title
        (or (hrt:view-app-id view) "(untitled)"))))

(defun %tab-bar-draw (bar)
  "Draw BAR for its output as it is now, or hide it when the group shown
there has another layout."
  (let* ((output (tab-bar-output bar))
         (canvas (tab-bar-canvas bar))
         (group (%tabs-group output)))
    (cond
      ((null group)
       (hrt:canvas-set-enabled canvas nil)
       (setf (tab-bar-drawn bar) nil
             (tab-bar-hits bar) '()))
      (t
       (let* ((views (%tab-views group))
              (shown (%tab-shown-view group))
              (theme *mode-line-theme*)
              (font (mh/theme:theme-font theme))
              (pad *mode-line-padding*)
              (height *tab-bar-height*))
         (multiple-value-bind (width output-height) (hrt:output-logical-size output)
           (let ((key (list width (mapcar #'%tab-title views) shown
                            (and *theme* (theme-name *theme*)))))
             (unless (equal key (tab-bar-drawn bar))
               (hrt:canvas-set-position canvas 0 (if (eq *mode-line-position* :bottom)
                                                     (- output-height *mode-line-height* height)
                                                     *mode-line-height*))
               (hrt:canvas-set-enabled canvas t)
               (let ((hits '())
                     (tab-width (if views
                                    (min *tab-width* (floor (- width pad) (length views)))
                                    0)))
                 (hrt:with-canvas-frame (cr canvas width height)
                   (draw:clear cr (mh/theme:theme-background-color theme))
                   (loop for view in views
                         for x from pad by tab-width
                         for shown-p = (eq view shown)
                         do (when shown-p
                              (draw:fill-rounded-rectangle cr x 3 (- tab-width (round pad 2)) (- height 6)
                                                           (%overlay-radius 6)
                                                           (mh/theme:theme-border-color theme)))
                            (draw:draw-text cr (%tab-title view)
                                            (+ x (round pad 2)) (round (- height 16) 2)
                                            :font font
                                            :color (if shown-p
                                                       (mh/theme:theme-background-color theme)
                                                       (%dim (mh/theme:theme-font-color theme) 0.7))
                                            :width (- tab-width (* 2 (round pad 2)) (round pad 2))
                                            :ellipsize :end)
                            (push (list x (+ x tab-width) view) hits)))
                 (setf (tab-bar-hits bar) hits
                       (tab-bar-drawn bar) key))))))))))

(defun %tab-bar-click (bar x button pressed)
  (when (and pressed (= button hrt:+button-left+))
    (loop for (x0 x1 view) in (tab-bar-hits bar)
          when (<= x0 x x1)
            do (mahogany-state-show-view *compositor-state* view)
               (mode-line-update)
               (return))))

(defun %tab-bar-scroll (bar vertical delta)
  (declare (ignore bar))
  (when vertical
    (if (plusp delta)
        (state-next-hidden-frame *compositor-state*)
        (state-prev-hidden-frame *compositor-state*))
    (mode-line-update)))

(defun %ensure-tab-bar (output)
  (let ((name (hrt:output-full-name output)))
    (or (gethash name *tab-bars*)
        (let* ((canvas (hrt:make-canvas output :layer :layer-top))
               (bar (%make-tab-bar output canvas)))
          (setf (hrt:canvas-on-button canvas)
                (lambda (canvas x y button pressed)
                  (declare (ignore canvas y))
                  (%tab-bar-click bar x button pressed))
                (hrt:canvas-on-axis canvas)
                (lambda (canvas x y vertical delta)
                  (declare (ignore canvas x y))
                  (%tab-bar-scroll bar vertical delta)))
          (setf (gethash name *tab-bars*) bar)))))

(defun tabs-update (outputs)
  "Draw the tab strips of OUTPUTS (those in use), dropping those of
outputs that have gone. The mode-line calls it whenever it redraws."
  (maphash (lambda (name bar)
             (when (or (hrt:canvas-destroyed-p (tab-bar-canvas bar))
                       (not (member (tab-bar-output bar) outputs :test #'hrt:output=)))
               (remhash name *tab-bars*)
               (unless (hrt:canvas-destroyed-p (tab-bar-canvas bar))
                 (hrt:canvas-destroy (tab-bar-canvas bar)))))
           *tab-bars*)
  (dolist (output outputs)
    (handler-case (%tab-bar-draw (%ensure-tab-bar output))
      (error (c)
        (log-string :error "Could not draw the tabs of ~S: ~A" (hrt:output-full-name output) c)))))
