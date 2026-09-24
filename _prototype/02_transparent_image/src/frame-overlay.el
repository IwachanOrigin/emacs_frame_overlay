;;; frame-overlay.el --- Frame-level Win32 image overlay -*- lexical-binding: t; -*-

(defgroup frame-overlay nil
  "Frame-level overlay for native Windows Emacs."
  :group 'frames)

(defcustom frame-overlay-width 260
  "Width in pixels for the solid-color prototype overlay."
  :type 'integer)

(defcustom frame-overlay-height 180
  "Height in pixels for the solid-color prototype overlay."
  :type 'integer)

(defcustom frame-overlay-alpha 160
  "Opacity for the solid-color prototype overlay, from 0 to 255."
  :type 'integer)

(defcustom frame-overlay-image-alpha 255
  "Global opacity for PNG overlays, from 0 to 255.
The PNG's own per-pixel alpha is preserved and multiplied by this value."
  :type '(integer :tag "Alpha"))

(defcustom frame-overlay-scale 1.0
  "Scale factor applied when a PNG is loaded.
For example, 0.5 displays the image at half size and 2.0 at double size."
  :type 'number)

(defcustom frame-overlay-position 'bottom-right
  "Position of the overlay inside the Emacs frame."
  :type '(choice
          (const :tag "Top left" top-left)
          (const :tag "Top right" top-right)
          (const :tag "Bottom left" bottom-left)
          (const :tag "Bottom right" bottom-right)
          (const :tag "Center" center)))

(defcustom frame-overlay-margin-x 24
  "Horizontal margin in pixels from the selected frame edge."
  :type 'integer)

(defcustom frame-overlay-margin-y 24
  "Vertical margin in pixels from the selected frame edge."
  :type 'integer)

(defcustom frame-overlay-auto-sync t
  "When non-nil, periodically synchronize the overlay with its Emacs frame."
  :type 'boolean)

(defcustom frame-overlay-sync-interval 0.05
  "Seconds between frame-position synchronization calls.
This is only used when `frame-overlay-auto-sync' is non-nil."
  :type 'number)

(defvar frame-overlay--timer nil)
(defvar frame-overlay--file nil)
(defvar frame-overlay--frame nil)

(defun frame-overlay--native-id (frame parameter)
  "Return FRAME's native window PARAMETER as an integer."
  (let ((value (frame-parameter frame parameter)))
    (cond
     ((integerp value) value)
     ((stringp value) (string-to-number value))
     (t (error "Unsupported %S value: %S" parameter value)))))

(defun frame-overlay--position-code ()
  "Return the native position code for `frame-overlay-position'."
  (pcase frame-overlay-position
    ('top-left 0)
    ('top-right 1)
    ('bottom-left 2)
    ('bottom-right 3)
    ('center 4)
    (_ (error "Unsupported frame-overlay-position: %S"
              frame-overlay-position))))

(defun frame-overlay--validate-image-options ()
  "Validate image-related customization variables."
  (unless (and (numberp frame-overlay-scale)
               (> frame-overlay-scale 0))
    (user-error "frame-overlay-scale must be greater than zero"))

  (unless (and (integerp frame-overlay-image-alpha)
               (<= 0 frame-overlay-image-alpha 255))
    (user-error "frame-overlay-image-alpha must be between 0 and 255"))

  (unless (integerp frame-overlay-margin-x)
    (user-error "frame-overlay-margin-x must be an integer"))

  (unless (integerp frame-overlay-margin-y)
    (user-error "frame-overlay-margin-y must be an integer")))

(defun frame-overlay--stop-timer ()
  "Stop the synchronization timer if it is running."
  (when (timerp frame-overlay--timer)
    (cancel-timer frame-overlay--timer)
    (setq frame-overlay--timer nil)))

(defun frame-overlay--start-timer ()
  "Restart the synchronization timer according to current settings."
  (frame-overlay--stop-timer)

  (when frame-overlay-auto-sync
    (unless (and (numberp frame-overlay-sync-interval)
                 (> frame-overlay-sync-interval 0))
      (user-error "frame-overlay-sync-interval must be greater than zero"))

    (setq frame-overlay--timer
          (run-with-timer
           0
           frame-overlay-sync-interval
           #'frame-overlay-module-sync))))

(defun frame-overlay-frame-ids (&optional frame)
  "Display native window IDs for FRAME."
  (interactive)
  (let* ((frame (or frame (selected-frame)))
         (window-id (frame-parameter frame 'window-id))
         (outer-id (frame-parameter frame 'outer-window-id)))
    (message "window-id=%S outer-window-id=%S window-system=%S"
             window-id outer-id (window-system frame))))

(defun frame-overlay-show (&optional frame)
  "Show the solid-color prototype overlay for FRAME."
  (interactive)
  (let ((frame (or frame (selected-frame))))
    (unless (eq (window-system frame) 'w32)
      (user-error "This prototype currently supports native Windows Emacs only"))

    (let* ((anchor (frame-overlay--native-id frame 'window-id))
           (owner anchor))
      (unless (frame-overlay-module-show
               anchor owner
               frame-overlay-width
               frame-overlay-height
               frame-overlay-alpha)
        (error "Failed to create the native overlay"))

      (setq frame-overlay--file nil
            frame-overlay--frame frame)
      (frame-overlay--start-timer)
      (message "Frame overlay shown: hwnd=%s" anchor))))

(defun frame-overlay-show-file (file &optional frame)
  "Show PNG FILE once for the whole Emacs FRAME.
The image is scaled and positioned according to the `frame-overlay' options."
  (interactive "fPNG file: ")
  (frame-overlay--validate-image-options)

  (let* ((frame (or frame (selected-frame)))
         (file (expand-file-name file)))
    (unless (eq (window-system frame) 'w32)
      (user-error "This prototype currently supports native Windows Emacs only"))

    (unless (file-readable-p file)
      (user-error "PNG file is not readable: %s" file))

    (let ((hwnd (frame-overlay--native-id frame 'window-id)))
      (unless (frame-overlay-module-show-file
               hwnd
               file
               (float frame-overlay-scale)
               (frame-overlay--position-code)
               frame-overlay-margin-x
               frame-overlay-margin-y
               frame-overlay-image-alpha)
        (error "Failed to show PNG overlay: %s" file))

      (setq frame-overlay--file file
            frame-overlay--frame frame)
      (frame-overlay--start-timer)
      (message "PNG overlay shown: %s (scale %.3g, %s)"
               file frame-overlay-scale frame-overlay-position))))

(defun frame-overlay-refresh ()
  "Reload the current PNG using the latest `frame-overlay' settings.
Use this after changing scale, position, margins, alpha, or sync settings."
  (interactive)
  (unless frame-overlay--file
    (user-error "No PNG overlay has been shown yet"))

  (unless (and frame-overlay--frame
               (frame-live-p frame-overlay--frame))
    (user-error "The frame used by the PNG overlay is no longer live"))

  (frame-overlay-show-file frame-overlay--file frame-overlay--frame))

(defun frame-overlay-sync-now ()
  "Synchronize the overlay position immediately."
  (interactive)
  (unless (frame-overlay-module-sync)
    (error "Failed to synchronize frame overlay")))

(defun frame-overlay-hide ()
  "Hide the overlay and stop synchronization."
  (interactive)
  (frame-overlay--stop-timer)
  (frame-overlay-module-hide))

(defun frame-overlay-destroy ()
  "Destroy the overlay, stop synchronization, and forget the current image."
  (interactive)
  (frame-overlay--stop-timer)
  (frame-overlay-module-destroy)
  (setq frame-overlay--file nil
        frame-overlay--frame nil))

(provide 'frame-overlay)
;;; frame-overlay.el ends here
