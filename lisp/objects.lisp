(in-package #:mahogany)

(defstruct (mahogany-group (:constructor %make-mahogany-group
                               (name number hrt-group tiled-container)))
  (name "" :type string)
  ;; Its number on its output; a group away from home gets a free one
  ;; on the output that hosts it.
  (number 1 :type fixnum)
  (active-p nil :type boolean)
  (hrt-group (cffi:null-pointer) :type cffi:foreign-pointer :read-only t)
  (tiled-container nil :type tree:layer-container :read-only t)
  ;; The layer above the tiled one, for floating windows, and their
  ;; frames, the one focused last first:
  (floating-container nil :type (or null tree:layer-container))
  (floating-frames '() :type list)
  ;; The tiled frame focused last: where new windows go, and the focus
  ;; returns, while a floating window has the focus.
  (tiled-frame nil)
  (output-map (make-hash-table :test 'equal) :type hash-table :read-only t)
  (current-frame nil ;; :type (or tree:frame tree:output-node null)
   )
  (hidden-views (ring-list:make-ring-list) :type ring-list:ring-list)
  ;; Map that contains views hidden by fullscreen windows.
  ;; view -> %hidden-view-info
  (hidden-view-map (make-hash-table) :type hash-table)
  (views nil :type list)
  ;; The output the group belongs to (its workspaces are per output):
  ;; the output's full name, NIL for one waiting for an output (none
  ;; connected yet, or its own gone), or :NONE for one never shown, such
  ;; as the scratchpad's.
  (home nil :type (or null string (eql :none)))
  ;; A group whose output went away lives on another output until its
  ;; own comes back: ORIGIN names that output and ORIGIN-NUMBER is its
  ;; number there. NIL for a group at home.
  (origin nil :type (or null string))
  (origin-number 1 :type fixnum))

(defstruct (mahogany-state (:conc-name state-))
  (server nil :type (or null cffi:foreign-pointer))
  (key-state (make-key-state nil):type key-state)
  (%current-group nil :type (or null mahogany-group))
  (%current-frame nil)
  (%keybindings nil :type list)
  (active-kmap-modes nil :type list)
  (%prefix-key (kbd "C-t") :type key)
  (cur-outputs (make-array 0 :element-type 'tree::output-container
                         :adjustable t :fill-pointer t)
   :type (vector tree::output-container *))
  (outputs (make-array 0 :element-type 'hrt:output
                         :adjustable t :fill-pointer t)
   :type (vector hrt:output *))
  (pending-output-timer nil
                        :type (or null hrt:timer-handle))
  (groups (make-array 0 :element-type 'mahogany-group
                        :adjustable t :fill-pointer t)
   :type (vector mahogany-group *))
  ;; output full name -> the group shown on it (its current workspace):
  (output-groups (make-hash-table :test 'equal)
   :type hash-table
   :read-only t)
  (views (make-hash-table)
   :type hash-table
   :read-only t)
  (layer-surfaces (make-hash-table)
   :type hash-table
   :read-only t)
  ;; Whether a client holds the session locked (ext-session-lock):
  (locked-p nil :type boolean))

(declaim (inline state-current-group))
(defun state-current-group (state)
  (declare (type mahogany-state state))
  (state-%current-group state))

(declaim (inline state-current-frame))
(defun state-current-frame (state)
  (declare (type mahogany-state state))
  (state-%current-frame state))

(declaim (inline state-keybindings))
(defun state-keybindings (state)
  (declare (type mahogany-state state))
  (state-%keybindings state))

(declaim (inline state-prefix-key))
(defun state-prefix-key (state)
  (declare (type mahogany-state state))
  (state-%prefix-key state))

(declaim (inline server-seat))
(defun server-seat (state)
  (hrt:hrt-server-seat (state-server state)))
