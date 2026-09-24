;;; frame-overlay.el --- Prototype frame-level Win32 overlay -*- lexical-binding: t; -*-

(defgroup frame-overlay nil
  "Prototype frame-level overlay for native Windows Emacs."
  :group 'frames)

(defcustom frame-overlay-width 260
  "Prototype overlay width in pixels."
  :type 'integer)

(defcustom frame-overlay-height 180
  "Prototype overlay height in pixels."
  :type 'integer)

(defcustom frame-overlay-alpha 160
  "Prototype overlay opacity, from 0 to 255."
  :type 'integer)

(defcustom frame-overlay-sync-interval 0.05
  "Seconds between frame-position synchronization calls."
  :type 'number)

(defvar frame-overlay--timer nil)

(defun frame-overlay--native-id (frame parameter)
  "Return FRAME's native window PARAMETER as an integer."
  (let ((value (frame-parameter frame parameter)))
    (cond
     ((integerp value) value)
     ((stringp value) (string-to-number value))
     (t (error "Unsupported %S value: %S" parameter value)))))

(defun frame-overlay-frame-ids (&optional frame)
  "Display native window IDs for FRAME."
  (interactive)
  (let* ((frame (or frame (selected-frame)))
         (window-id (frame-parameter frame 'window-id))
         (outer-id (frame-parameter frame 'outer-window-id)))
    (message "window-id=%S outer-window-id=%S window-system=%S"
             window-id outer-id (window-system frame))))

(defun frame-overlay-show (&optional frame)
  "Show one overlay for FRAME."
  (interactive)
  (unless (eq (window-system frame) 'w32)
    (user-error "This prototype currently supports native Windows Emacs only"))

  (let* ((frame (or frame (selected-frame)))
         ;; On native Windows Emacs, `outer-window-id' is normally nil.
         ;; `window-id' is the native frame HWND, so use it as both the
         ;; positioning anchor and popup owner.
         (anchor (frame-overlay--native-id frame 'window-id))
         (owner anchor))
    (unless (frame-overlay-module-show
             anchor owner
             frame-overlay-width
             frame-overlay-height
             frame-overlay-alpha)
      (error "Failed to create the native overlay"))

    (when (timerp frame-overlay--timer)
      (cancel-timer frame-overlay--timer))

    (setq frame-overlay--timer
          (run-with-timer
           0 frame-overlay-sync-interval
           #'frame-overlay-module-sync))

    (message "Frame overlay shown: hwnd=%s" anchor)))

(defun frame-overlay-hide ()
  "Hide the prototype overlay and stop synchronization."
  (interactive)
  (when (timerp frame-overlay--timer)
    (cancel-timer frame-overlay--timer)
    (setq frame-overlay--timer nil))
  (frame-overlay-module-hide))

(defun frame-overlay-destroy ()
  "Destroy the prototype overlay and stop synchronization."
  (interactive)
  (when (timerp frame-overlay--timer)
    (cancel-timer frame-overlay--timer)
    (setq frame-overlay--timer nil))
  (frame-overlay-module-destroy))

(provide 'frame-overlay)
;;; frame-overlay.el ends here
