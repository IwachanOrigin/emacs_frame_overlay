;;; frame-overlay.el --- Frame-level Win32 image overlay -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yuji Iwanaga

;; Author: Yuji Iwanaga
;; Maintainer: Yuji Iwanaga
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, frames, multimedia
;; URL: https://github.com/IwachanOrigin/emacs_frame_overlay
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; frame-overlay displays transparent PNG images over a native Windows
;; Emacs frame by using an Emacs Dynamic Module.
;;
;; Features include:
;;
;; - frame-level transparent PNG overlays
;; - per-pixel PNG alpha
;; - global opacity control
;; - image scaling
;; - configurable image position and margins
;; - automatic frame move/resize tracking
;; - image playlist playback
;; - directory-based playlists
;;
;; The native Dynamic Module is built with CMake when necessary.
;;
;; Basic usage:
;;
;;   (frame-overlay-ensure-module)
;;
;;   (setq frame-overlay-scale 0.35)
;;   (setq frame-overlay-position 'center)
;;   (setq frame-overlay-image-alpha 32)
;;
;;   (frame-overlay-show-file "C:/path/to/image.png")
;;
;; This package currently supports native Windows Emacs only.

;;; Code:

(require 'seq)

(declare-function frame-overlay-module-show
                  "frame-overlay-module"
                  (anchor owner width height alpha))

(declare-function frame-overlay-module-show-file
                  "frame-overlay-module"
                  (hwnd file &optional scale position margin-x margin-y alpha))

(declare-function frame-overlay-module-sync
                  "frame-overlay-module"
                  ())

(declare-function frame-overlay-module-hide
                  "frame-overlay-module"
                  ())

(declare-function frame-overlay-module-destroy
                  "frame-overlay-module"
                  ())

(defgroup frame-overlay nil
  "Frame-level overlay for native Windows Emacs."
  :group 'frames)

(defconst frame-overlay--elisp-directory
  (file-name-directory
   (or load-file-name
       (locate-library "frame-overlay")
       (error "Cannot determine frame-overlay directory")))
  "Directory containing frame-overlay.el.")

(defconst frame-overlay--source-directory
  (file-truename
   (expand-file-name "../.." frame-overlay--elisp-directory))
  "Root of the frame-overlay CMake source tree.")

(defcustom frame-overlay-build-directory
  (expand-file-name "build" frame-overlay--source-directory)
  "Directory used by CMake to build the native module."
  :type 'directory)

(defcustom frame-overlay-emacs-include-directory nil
  "Directory containing emacs-module.h.

When nil, frame-overlay derives the directory from
`invocation-directory'."
  :type '(choice
          (const :tag "Auto detect" nil)
          directory))

(defcustom frame-overlay-cmake-program "cmake"
  "CMake executable used to build the native module."
  :type 'string)

(defcustom frame-overlay-cmake-generator "MinGW Makefiles"
  "CMake generator used to build the native module.

Set this to nil to let CMake select its default generator."
  :type '(choice
          (const :tag "CMake default" nil)
          string))

(defcustom frame-overlay-build-type "Release"
  "CMake build type used for the native module."
  :type 'string)

(defcustom frame-overlay-module-basename "frame-overlay-module"
  "Base filename of the native frame-overlay module."
  :type 'string)

(defcustom frame-overlay-verbose nil
  "When non-nil, display informational frame-overlay messages."
  :type 'boolean)

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

(defun frame-overlay--log (format-string &rest args)
  "Display an informational message when `frame-overlay-verbose' is non-nil."
  (when frame-overlay-verbose
    (apply #'message format-string args)))

(defun frame-overlay--module-file ()
  "Return the expected native module filename."
  (expand-file-name
   (concat frame-overlay-module-basename module-file-suffix)
   (expand-file-name "bin" frame-overlay-build-directory)))

(defun frame-overlay--emacs-include-directory ()
  "Return the directory containing emacs-module.h."
  (let ((directory
         (or frame-overlay-emacs-include-directory
             (expand-file-name "../include" invocation-directory))))
    (setq directory (file-truename directory))

    (unless
        (file-exists-p
         (expand-file-name "emacs-module.h" directory))
      (user-error
       "emacs-module.h was not found in: %s"
       directory))

    directory))

(defun frame-overlay--native-source-files ()
  "Return files which affect the native module build."
  (let ((module-directory
         (expand-file-name
          "main/module"
          frame-overlay--source-directory)))
    (append
     (delq
      nil
      (mapcar
       (lambda (file)
         (when (file-exists-p file)
           file))
       (list
        (expand-file-name
         "CMakeLists.txt"
         frame-overlay--source-directory)

        (expand-file-name
         "main/CMakeLists.txt"
         frame-overlay--source-directory)

        (expand-file-name
         "main/module/CMakeLists.txt"
         frame-overlay--source-directory))))

     (when (file-directory-p module-directory)
       (directory-files-recursively
        module-directory
        "\\.\\(?:cpp\\|hpp\\|h\\)\\'")))))

(defun frame-overlay--module-needs-build-p ()
  "Return non-nil when the native module needs to be built."
  (let ((module-file (frame-overlay--module-file)))
    (or
     (not (file-exists-p module-file))

     (seq-some
      (lambda (source-file)
        (file-newer-than-file-p source-file module-file))
      (frame-overlay--native-source-files)))))

(defun frame-overlay--run-cmake (buffer &rest arguments)
  "Run CMake with ARGUMENTS and append output to BUFFER."
  (let ((cmake
         (or (executable-find frame-overlay-cmake-program)
             (user-error
              "CMake executable was not found: %s"
              frame-overlay-cmake-program))))

    (with-current-buffer buffer
      (goto-char (point-max))
      (insert
       "\n$ "
       cmake
       " "
       (mapconcat #'identity arguments " ")
       "\n\n"))

    (apply
     #'call-process
     cmake
     nil
     buffer
     t
     arguments)))

(defun frame-overlay-build-module ()
  "Configure and build the native frame-overlay module."
  (interactive)

  (unless (eq system-type 'windows-nt)
    (user-error
     "frame-overlay currently supports Windows only"))

  ;; Windows locks loaded DLL files.
  (when (featurep 'frame-overlay-module)
    (user-error
     "frame-overlay-module is already loaded; restart Emacs before rebuilding"))

  (let* ((source-directory
          frame-overlay--source-directory)

         (build-directory
          (expand-file-name
           frame-overlay-build-directory))

         (include-directory
          (frame-overlay--emacs-include-directory))

         (buffer
          (get-buffer-create "*frame-overlay-build*"))

         (configure-arguments
          (append
           (list
            "-S" source-directory
            "-B" build-directory
            (concat
             "-DCMAKE_BUILD_TYPE="
             frame-overlay-build-type)
            (concat
             "-DEMACS_INCLUDE_DIR="
             include-directory))

           (when frame-overlay-cmake-generator
             (list
              "-G"
              frame-overlay-cmake-generator)))))

    (make-directory build-directory t)

    (with-current-buffer buffer
      (erase-buffer)
      (insert "frame-overlay native module build\n"))

    (let ((status
           (apply
            #'frame-overlay--run-cmake
            buffer
            configure-arguments)))

      (unless (and (integerp status)
                   (zerop status))
        (display-buffer buffer)
        (error
         "frame-overlay CMake configuration failed")))

    (let ((status
           (frame-overlay--run-cmake
            buffer
            "--build"
            build-directory
            "--config"
            frame-overlay-build-type)))

      (unless (and (integerp status)
                   (zerop status))
        (display-buffer buffer)
        (error
         "frame-overlay native module build failed")))

    (let ((module-file
           (frame-overlay--module-file)))

      (unless (file-exists-p module-file)
        (display-buffer buffer)
        (error
         "Native module was not generated: %s"
         module-file))

      (frame-overlay--log
       "frame-overlay module built: %s"
       module-file)

      module-file)))

(defun frame-overlay-load-module ()
  "Load the native frame-overlay dynamic module."
  (interactive)

  (unless (fboundp 'module-load)
    (user-error
     "This Emacs does not support dynamic modules"))

  (unless (featurep 'frame-overlay-module)
    (let ((module-file
           (frame-overlay--module-file)))

      (unless (file-exists-p module-file)
        (user-error
         "Native module does not exist: %s"
         module-file))

      (module-load module-file)))

  (unless (featurep 'frame-overlay-module)
    (error
     "frame-overlay native module failed to provide frame-overlay-module"))

  t)

(defun frame-overlay-ensure-module ()
  "Build and load the native frame-overlay module when necessary."
  (interactive)

  (unless (featurep 'frame-overlay-module)

    (when (frame-overlay--module-needs-build-p)
      (frame-overlay-build-module))

    (frame-overlay-load-module))

  t)

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
    (frame-overlay--log "window-id=%S outer-window-id=%S window-system=%S"
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
      (frame-overlay--log "Frame overlay shown: hwnd=%s" anchor)

      t)))

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
      (frame-overlay--log
       "PNG overlay shown: %s (scale %.3g, %s)"
       file frame-overlay-scale frame-overlay-position)

      t)))

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

  (frame-overlay--show-file frame-overlay--file frame-overlay--frame)

  t)

(defun frame-overlay-sync-now ()
  "Synchronize the overlay position immediately."
  (interactive)
  (unless (frame-overlay-module-sync)
    (error "Failed to synchronize frame overlay"))

  t)

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

    (frame-overlay--log
     "Frame overlay playlist: %d/%d"
     (1+ frame-overlay-playlist--index)
     count)

    t))

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
      (frame-overlay--log "Frame overlay playlist finished")))))

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

  (frame-overlay--log "Frame overlay playlist started: %d images, %.3g sec"
           (length frame-overlay-playlist)
           frame-overlay-playlist-interval)

  t)

(defun frame-overlay-playlist-stop ()
  "Stop playlist playback without hiding the current overlay image.

Frame-position synchronization continues according to
`frame-overlay-auto-sync'."
  (interactive)
  (frame-overlay-playlist--stop-timer)
  (frame-overlay--log "Frame overlay playlist stopped")

  t)

(defun frame-overlay-playlist-restart ()
  "Restart playlist playback from the first image."
  (interactive)
  (frame-overlay-playlist-start t))

(defun frame-overlay-hide ()
  "Hide the overlay and stop synchronization."
  (interactive)
  (frame-overlay-playlist--stop-timer)
  (frame-overlay--stop-timer)
  (frame-overlay-module-hide)
  (unless (frame-overlay-module-hide)
    (error "Failed to hide frame overlay"))
  t)

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
        frame-overlay-playlist--index 0)
  (unless (frame-overlay-module-destroy)
    (error "Failed to destroy frame overlay"))
  t)

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

      (frame-overlay--log "Frame overlay playlist loaded: %d PNG files from %s"
               (length files)
               directory)

      t)))

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
