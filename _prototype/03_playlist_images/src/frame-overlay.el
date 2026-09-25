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

(defcustom frame-overlay-playlist nil
  "List of PNG files used by the frame overlay playlist.

Example:

  (setq frame-overlay-playlist
        '(\"C:/images/a.png\"
          \"C:/images/b.png\"
          \"C:/images/c.png\"))"
  :type '(repeat file))

(defcustom frame-overlay-playlist-interval 5.0
  "Seconds between image changes while playlist playback is active."
  :type 'number)

(defcustom frame-overlay-playlist-loop t
  "When non-nil, continue from the first image after the last image.
When nil, playlist playback stops after the last image."
  :type 'boolean)

(defcustom frame-overlay-playlist-directory nil
  "PNGプレイリストを自動生成するディレクトリ。
非nilなら、このディレクトリ内の .png ファイルを使って
`frame-overlay-playlist' を再構築できる。"
  :type '(choice
          (const :tag "未設定" nil)
          directory))

(defcustom frame-overlay-playlist-recursive nil
  "非nilなら、プレイリスト用PNG探索をサブディレクトリまで再帰的に行う。"
  :type 'boolean)

(defvar frame-overlay--timer nil)
(defvar frame-overlay--file nil)
(defvar frame-overlay--frame nil)

(defvar frame-overlay-playlist--timer nil)
(defvar frame-overlay-playlist--index 0)

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

(defun frame-overlay--validate-playlist ()
  "Validate playlist settings."
  (unless frame-overlay-playlist
    (user-error "frame-overlay-playlist is empty"))

  (unless (listp frame-overlay-playlist)
    (user-error "frame-overlay-playlist must be a list"))

  (unless (and (numberp frame-overlay-playlist-interval)
               (> frame-overlay-playlist-interval 0))
    (user-error "frame-overlay-playlist-interval must be greater than zero")))

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

(defun frame-overlay-playlist--stop-timer ()
  "Stop the playlist timer if it is running."
  (when (timerp frame-overlay-playlist--timer)
    (cancel-timer frame-overlay-playlist--timer)
    (setq frame-overlay-playlist--timer nil)))

(defun frame-overlay-playlist--current-file ()
  "Return the current playlist file, or nil when the playlist is empty."
  (when frame-overlay-playlist
    (nth frame-overlay-playlist--index frame-overlay-playlist)))

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
  (frame-overlay-playlist--stop-timer)

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

(defun frame-overlay--show-file (file &optional frame)
  "Internal implementation for showing PNG FILE on FRAME.
Unlike `frame-overlay-show-file', this function does not stop playlist playback."
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

(defun frame-overlay-show-file (file &optional frame)
  "Show PNG FILE once for the whole Emacs FRAME.
The image is scaled and positioned according to the `frame-overlay' options.
When a playlist is currently playing, manual use of this function stops
playlist playback.  The overlay image itself remains visible."
  (interactive "fPNG file: ")
  (frame-overlay-playlist--stop-timer)
  (frame-overlay--show-file file frame))

(defun frame-overlay-refresh ()
    "Reload the current PNG using the latest `frame-overlay' settings.
Use this after changing scale, position, margins, alpha, or sync settings.
If playlist playback is active, playback continues."
  (interactive)
  (unless frame-overlay--file
    (user-error "No PNG overlay has been shown yet"))

  (unless (and frame-overlay--frame
               (frame-live-p frame-overlay--frame))
    (user-error "The frame used by the PNG overlay is no longer live"))

  (frame-overlay--show-file frame-overlay--file frame-overlay--frame))

(defun frame-overlay-sync-now ()
  "Synchronize the overlay position immediately."
  (interactive)
  (unless (frame-overlay-module-sync)
    (error "Failed to synchronize frame overlay")))

(defun frame-overlay-playlist-show-index (index &optional frame)
  "Show INDEX from `frame-overlay-playlist' on FRAME.

INDEX is zero-based.  This function changes the current playlist position
but does not start or stop playlist playback."
  (interactive "nPlaylist index: ")
  (frame-overlay--validate-playlist)

  (let ((count (length frame-overlay-playlist)))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index count))
      (user-error "Playlist index out of range: %s (0..%d)"
                  index (1- count)))

    (setq frame-overlay-playlist--index index)

    (frame-overlay--show-file
     (nth frame-overlay-playlist--index frame-overlay-playlist)
     (or frame
         (and frame-overlay--frame
              (frame-live-p frame-overlay--frame)
              frame-overlay--frame)
         (selected-frame)))

    (message "Frame overlay playlist: %d/%d"
             (1+ frame-overlay-playlist--index)
             count)))

(defun frame-overlay-playlist-next ()
  "Show the next image in `frame-overlay-playlist'.

When the last image is reached:
- if `frame-overlay-playlist-loop' is non-nil, wrap to the first image;
- otherwise stop playlist playback and keep the last image displayed."
  (interactive)
  (frame-overlay--validate-playlist)

  (let* ((count (length frame-overlay-playlist))
         (next (1+ frame-overlay-playlist--index)))
    (cond
     ((< next count)
      (frame-overlay-playlist-show-index next))

     (frame-overlay-playlist-loop
      (frame-overlay-playlist-show-index 0))

     (t
      (frame-overlay-playlist--stop-timer)
      (message "Frame overlay playlist finished")))))

(defun frame-overlay-playlist-previous ()
  "Show the previous image in `frame-overlay-playlist'.

When the first image is selected:
- if `frame-overlay-playlist-loop' is non-nil, wrap to the last image;
- otherwise remain on the first image."
  (interactive)
  (frame-overlay--validate-playlist)

  (let* ((count (length frame-overlay-playlist))
         (previous (1- frame-overlay-playlist--index)))
    (cond
     ((>= previous 0)
      (frame-overlay-playlist-show-index previous))

     (frame-overlay-playlist-loop
      (frame-overlay-playlist-show-index (1- count)))

     (t
      (frame-overlay-playlist-show-index 0)))))

(defun frame-overlay-playlist-start (&optional reset)
  "Start playlist playback.

The current playlist image is displayed immediately, then images are switched
every `frame-overlay-playlist-interval' seconds.

With optional RESET non-nil, start again from index 0.
Interactively, use a prefix argument (\\[universal-argument]) to reset."
  (interactive "P")
  (frame-overlay--validate-playlist)

  (let ((count (length frame-overlay-playlist)))
    (when (or reset
              (< frame-overlay-playlist--index 0)
              (>= frame-overlay-playlist--index count))
      (setq frame-overlay-playlist--index 0)))

  (frame-overlay-playlist--stop-timer)

  ;; Show the current item immediately.
  (frame-overlay-playlist-show-index frame-overlay-playlist--index)

  ;; The first automatic switch occurs after the configured interval.
  (setq frame-overlay-playlist--timer
        (run-with-timer
         frame-overlay-playlist-interval
         frame-overlay-playlist-interval
         #'frame-overlay-playlist-next))

  (message "Frame overlay playlist started: %d images, %.3g sec"
           (length frame-overlay-playlist)
           frame-overlay-playlist-interval))

(defun frame-overlay-playlist-stop ()
  "Stop playlist playback without hiding the current overlay image.

Frame-position synchronization continues according to
`frame-overlay-auto-sync'."
  (interactive)
  (frame-overlay-playlist--stop-timer)
  (message "Frame overlay playlist stopped"))

(defun frame-overlay-playlist-restart ()
  "Restart playlist playback from the first image."
  (interactive)
  (frame-overlay-playlist-start t))

(defun frame-overlay-hide ()
  "Hide the overlay and stop synchronization."
  (interactive)
  (frame-overlay-playlist--stop-timer)
  (frame-overlay--stop-timer)
  (frame-overlay-module-hide))

(defun frame-overlay-destroy ()
  "Destroy the overlay and stop all timers.

The current image and frame are forgotten.
The configured playlist itself is not modified."
  (interactive)
  (frame-overlay-playlist--stop-timer)
  (frame-overlay--stop-timer)
  (frame-overlay-module-destroy)
  (setq frame-overlay--file nil
        frame-overlay--frame nil
        frame-overlay-playlist--index 0))

(defun frame-overlay--directory-png-files (directory &optional recursive)
  "DIRECTORY 内の PNG ファイル一覧を返す。
RECURSIVE が非nilなら、サブディレクトリも探索する。"
  (let ((directory (file-name-as-directory (expand-file-name directory))))
    (unless (file-directory-p directory)
      (user-error "Directory does not exist: %s" directory))

    (sort
     (if recursive
         (directory-files-recursively directory "\\.[Pp][Nn][Gg]\\'")
       (seq-filter
        #'file-regular-p
        (directory-files directory t "\\.[Pp][Nn][Gg]\\'")))
     #'string-lessp)))

(defun frame-overlay-playlist-load-directory (&optional directory)
  "DIRECTORY から PNG ファイル一覧を読み込み、
`frame-overlay-playlist' を再構築する。

DIRECTORY を省略した場合は
`frame-overlay-playlist-directory' を使う。"
  (interactive)
  (let ((directory (or directory frame-overlay-playlist-directory)))
    ;; 先に directory が設定されているか確認する。
    (unless directory
      (user-error "frame-overlay-playlist-directory is not set"))

    ;; directory の存在確認後に PNG 一覧を取得する。
    (let ((files (frame-overlay--directory-png-files
                  directory
                  frame-overlay-playlist-recursive)))
      (unless files
        (user-error "No PNG files found in: %s" directory))

      (setq frame-overlay-playlist files
            frame-overlay-playlist--index 0)

      (message "Frame overlay playlist loaded: %d PNG files from %s"
               (length files)
               directory))))

(defun frame-overlay-playlist-set-directory (directory)
  "プレイリスト用ディレクトリを DIRECTORY に設定し、
PNG一覧を読み込む。"
  (interactive "DPlaylist directory: ")
  (setq frame-overlay-playlist-directory directory)
  (frame-overlay-playlist-load-directory directory))

(defun frame-overlay-playlist-start-directory (directory &optional reset)
  "DIRECTORY 内の PNG をプレイリストにして再生開始する。"
  (interactive "DPlaylist directory: \nP")
  (setq frame-overlay-playlist-directory directory)
  (frame-overlay-playlist-load-directory directory)
  (frame-overlay-playlist-start reset))

(provide 'frame-overlay)
;;; frame-overlay.el ends here
