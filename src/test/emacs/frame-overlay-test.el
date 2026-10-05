;;; frame-overlay-test.el --- Tests for frame-overlay -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'frame-overlay)

;;; Position

(ert-deftest frame-overlay-test-position-code-top-left ()
  (let ((frame-overlay-position 'top-left))
    (should (= (frame-overlay--position-code) 0))))

(ert-deftest frame-overlay-test-position-code-top-right ()
  (let ((frame-overlay-position 'top-right))
    (should (= (frame-overlay--position-code) 1))))

(ert-deftest frame-overlay-test-position-code-bottom-left ()
  (let ((frame-overlay-position 'bottom-left))
    (should (= (frame-overlay--position-code) 2))))

(ert-deftest frame-overlay-test-position-code-bottom-right ()
  (let ((frame-overlay-position 'bottom-right))
    (should (= (frame-overlay--position-code) 3))))

(ert-deftest frame-overlay-test-position-code-center ()
  (let ((frame-overlay-position 'center))
    (should (= (frame-overlay--position-code) 4))))

(ert-deftest frame-overlay-test-position-code-invalid ()
  (let ((frame-overlay-position 'invalid-position))
    (should-error
     (frame-overlay--position-code))))


;;; Size mode

(ert-deftest frame-overlay-test-size-mode-code-fixed ()
  (let ((frame-overlay-size-mode 'fixed))
    (should (= (frame-overlay--size-mode-code) 0))))

(ert-deftest frame-overlay-test-size-mode-code-fit ()
  (let ((frame-overlay-size-mode 'fit))
    (should (= (frame-overlay--size-mode-code) 1))))

(ert-deftest frame-overlay-test-size-mode-code-invalid ()
  (let ((frame-overlay-size-mode 'invalid-size-mode))
    (should-error
     (frame-overlay--size-mode-code))))

;;; Image option validation

(ert-deftest frame-overlay-test-image-options-valid ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (frame-overlay--validate-image-options)))

(ert-deftest frame-overlay-test-image-options-invalid-scale-zero ()
  (let ((frame-overlay-scale 0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-invalid-scale-minus ()
  (let ((frame-overlay-scale -1.0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-invalid-alpha-high ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha 256)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-invalid-alpha-minus ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha -1)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-invalid-margin-x ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24.1)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-invalid-margin-y ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24.1))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))


(ert-deftest frame-overlay-test-image-options-invalid-size-mode ()
  (let ((frame-overlay-size-mode 'invalid-size-mode)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 0.35)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-fit-valid ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 0.35)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (frame-overlay--validate-image-options)))

(ert-deftest frame-overlay-test-image-options-fit-invalid-ratio-zero ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-fit-invalid-ratio-minus ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio -0.1)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-fit-invalid-ratio-high ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 1.1)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-fit-invalid-ratio-not-number ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 'invalid)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (should-error
     (frame-overlay--validate-image-options)
     :type 'user-error)))

(ert-deftest frame-overlay-test-image-options-fit-does-not-require-positive-scale ()
  (let ((frame-overlay-size-mode 'fit)
        (frame-overlay-scale 0)
        (frame-overlay-frame-ratio 0.35)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (frame-overlay--validate-image-options)))

;;; Native image argument forwarding

(ert-deftest frame-overlay-test-show-file-fixed-native-arguments ()
  (let ((file (make-temp-file "frame-overlay-test-" nil ".png"))
        (frame-overlay-size-mode 'fixed)
        (frame-overlay-scale 0.5)
        (frame-overlay-frame-ratio 0.35)
        (frame-overlay-position 'bottom-right)
        (frame-overlay-margin-x 12)
        (frame-overlay-margin-y 34)
        (frame-overlay-image-alpha 200)
        (captured-args nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-system)
                   (lambda (&optional _frame) 'w32))
                  ((symbol-function 'frame-overlay--native-id)
                   (lambda (_frame _parameter) 1234))
                  ((symbol-function 'frame-overlay-module-show-file)
                   (lambda (&rest args)
                     (setq captured-args args)
                     t))
                  ((symbol-function 'frame-overlay--start-timer)
                   (lambda () nil)))
          (should (frame-overlay--show-file file))
          (should
           (equal captured-args
                  (list 1234
                        (expand-file-name file)
                        0.5
                        3
                        12
                        34
                        200
                        0
                        0.35))))
      (delete-file file))))

(ert-deftest frame-overlay-test-show-file-fit-native-arguments ()
  (let ((file (make-temp-file "frame-overlay-test-" nil ".png"))
        (frame-overlay-size-mode 'fit)
        (frame-overlay-scale 1.0)
        (frame-overlay-frame-ratio 0.4)
        (frame-overlay-position 'center)
        (frame-overlay-margin-x 20)
        (frame-overlay-margin-y 30)
        (frame-overlay-image-alpha 180)
        (captured-args nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-system)
                   (lambda (&optional _frame) 'w32))
                  ((symbol-function 'frame-overlay--native-id)
                   (lambda (_frame _parameter) 5678))
                  ((symbol-function 'frame-overlay-module-show-file)
                   (lambda (&rest args)
                     (setq captured-args args)
                     t))
                  ((symbol-function 'frame-overlay--start-timer)
                   (lambda () nil)))
          (should (frame-overlay--show-file file))
          (should
           (equal captured-args
                  (list 5678
                        (expand-file-name file)
                        1.0
                        4
                        20
                        30
                        180
                        1
                        0.4))))
      (delete-file file))))

;;; Playlist validation

(ert-deftest frame-overlay-test-playlist-empty ()
  (let ((frame-overlay-playlist nil)
        (frame-overlay-playlist-interval 5.0))
    (should-error
     (frame-overlay--validate-playlist)
     :type 'user-error)))

(ert-deftest frame-overlay-test-playlist-not-list ()
  (let ((frame-overlay-playlist "a.png")
        (frame-overlay-playlist-interval 5.0))
    (should-error
     (frame-overlay--validate-playlist)
     :type 'user-error)))

(ert-deftest frame-overlay-test-playlist-interval-zero ()
  (let ((frame-overlay-playlist '("a.png"))
        (frame-overlay-playlist-interval 0))
    (should-error
     (frame-overlay--validate-playlist)
     :type 'user-error)))

(ert-deftest frame-overlay-test-playlist-interval-minus ()
  (let ((frame-overlay-playlist '("a.png"))
        (frame-overlay-playlist-interval -1))
    (should-error
     (frame-overlay--validate-playlist)
     :type 'user-error)))

(ert-deftest frame-overlay-test-playlist-valid ()
  (let ((frame-overlay-playlist '("a.png"))
        (frame-overlay-playlist-interval 5.0))
    (frame-overlay--validate-playlist)))

;;; Directory PNG scan

(ert-deftest frame-overlay-test-directory-png-files ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "a.png" directory))
          (with-temp-file (expand-file-name "b.PNG" directory))
          (with-temp-file (expand-file-name "c.txt" directory))

          (let ((files
                 (frame-overlay--directory-png-files directory nil)))
            (should (= (length files) 2))
            (should
             (equal
              (mapcar #'file-name-nondirectory files)
              '("a.png" "b.PNG")))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-directory-png-files-empty ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (should-not
         (frame-overlay--directory-png-files directory nil))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-directory-png-files-nonexistent ()
  (let ((directory
         (expand-file-name
          "frame-overlay-directory-that-does-not-exist"
          temporary-file-directory)))
    (when (file-exists-p directory)
      (delete-directory directory t))
    (should-error
     (frame-overlay--directory-png-files directory nil)
     :type 'user-error)))

(ert-deftest frame-overlay-test-directory-png-files-nonrecursive ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (let ((subdirectory (expand-file-name "sub" directory)))
          (make-directory subdirectory)
          (with-temp-file (expand-file-name "root.png" directory))
          (with-temp-file (expand-file-name "child.png" subdirectory))

          (let ((files
                 (frame-overlay--directory-png-files directory nil)))
            (should
             (equal
              (mapcar #'file-name-nondirectory files)
              '("root.png")))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-directory-png-files-recursive ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (let ((subdirectory (expand-file-name "sub" directory)))
          (make-directory subdirectory)
          (with-temp-file (expand-file-name "root.png" directory))
          (with-temp-file (expand-file-name "child.png" subdirectory))

          (let ((files
                 (frame-overlay--directory-png-files directory t)))
            (should (= (length files) 2))
            (should
             (equal
              (sort
               (mapcar #'file-name-nondirectory files)
               #'string-lessp)
              '("child.png" "root.png")))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-directory-png-files-sorted ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "z.png" directory))
          (with-temp-file (expand-file-name "a.png" directory))
          (with-temp-file (expand-file-name "m.png" directory))

          (let ((files
                 (frame-overlay--directory-png-files directory nil)))
            (should
             (equal
              (mapcar #'file-name-nondirectory files)
              '("a.png" "m.png" "z.png")))))
      (delete-directory directory t))))

;;; Playlist movement

(ert-deftest frame-overlay-test-playlist-next ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 0)
        (frame-overlay-playlist-loop t))
    (cl-letf (((symbol-function 'frame-overlay--show-file)
               (lambda (&rest _args) t)))
      (frame-overlay-playlist-next)
      (should (= frame-overlay-playlist--index 1)))))

(ert-deftest frame-overlay-test-playlist-next-loop ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 2)
        (frame-overlay-playlist-loop t))
    (cl-letf (((symbol-function 'frame-overlay--show-file)
               (lambda (&rest _args) t)))
      (frame-overlay-playlist-next)
      (should (= frame-overlay-playlist--index 0)))))

(ert-deftest frame-overlay-test-playlist-next-no-loop ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 2)
        (frame-overlay-playlist-loop nil)
        (timer-stopped nil))
    (cl-letf (((symbol-function 'frame-overlay-playlist--stop-timer)
               (lambda ()
                 (setq timer-stopped t))))
      (frame-overlay-playlist-next)
      (should (= frame-overlay-playlist--index 2))
      (should timer-stopped))))

(ert-deftest frame-overlay-test-playlist-previous ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 2)
        (frame-overlay-playlist-loop t))
    (cl-letf (((symbol-function 'frame-overlay--show-file)
               (lambda (&rest _args) t)))
      (frame-overlay-playlist-previous)
      (should (= frame-overlay-playlist--index 1)))))

(ert-deftest frame-overlay-test-playlist-previous-loop ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 0)
        (frame-overlay-playlist-loop t))
    (cl-letf (((symbol-function 'frame-overlay--show-file)
               (lambda (&rest _args) t)))
      (frame-overlay-playlist-previous)
      (should (= frame-overlay-playlist--index 2)))))

(ert-deftest frame-overlay-test-playlist-previous-no-loop ()
  (let ((frame-overlay-playlist '("a.png" "b.png" "c.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 0)
        (frame-overlay-playlist-loop nil))
    (cl-letf (((symbol-function 'frame-overlay--show-file)
               (lambda (&rest _args) t)))
      (frame-overlay-playlist-previous)
      (should (= frame-overlay-playlist--index 0)))))

(ert-deftest frame-overlay-test-playlist-show-index-out-of-range ()
  (let ((frame-overlay-playlist '("a.png" "b.png"))
        (frame-overlay-playlist-interval 5.0)
        (frame-overlay-playlist--index 0))
    (should-error
     (frame-overlay-playlist-show-index 2)
     :type 'user-error)))

;;; Directory playlist

(ert-deftest frame-overlay-test-playlist-load-directory ()
  (let ((directory (make-temp-file "frame-overlay-test-" t))
        (frame-overlay-playlist nil)
        (frame-overlay-playlist--index 99)
        (frame-overlay-playlist-recursive nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "b.png" directory))
          (with-temp-file (expand-file-name "a.png" directory))
          (with-temp-file (expand-file-name "ignore.txt" directory))

          (should
           (frame-overlay-playlist-load-directory directory))

          (should (= frame-overlay-playlist--index 0))
          (should
           (equal
            (mapcar #'file-name-nondirectory frame-overlay-playlist)
            '("a.png" "b.png"))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-playlist-load-directory-empty ()
  (let ((directory (make-temp-file "frame-overlay-test-" t))
        (frame-overlay-playlist nil)
        (frame-overlay-playlist--index 0)
        (frame-overlay-playlist-recursive nil))
    (unwind-protect
        (should-error
         (frame-overlay-playlist-load-directory directory)
         :type 'user-error)
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-playlist-load-directory-resets-index ()
  (let ((directory (make-temp-file "frame-overlay-test-" t))
        (frame-overlay-playlist '("old.png"))
        (frame-overlay-playlist--index 5)
        (frame-overlay-playlist-recursive nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "new.png" directory))
          (frame-overlay-playlist-load-directory directory)
          (should (= frame-overlay-playlist--index 0)))
      (delete-directory directory t))))

;;; Native module build decision

(ert-deftest frame-overlay-test-module-needs-build-missing-module ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (let ((module-file (expand-file-name "frame-overlay-module.dll"
                                            directory)))
          (cl-letf (((symbol-function 'frame-overlay--module-file)
                     (lambda () module-file))
                    ((symbol-function 'frame-overlay--native-source-files)
                     (lambda () nil)))
            (should
             (frame-overlay--module-needs-build-p))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-module-needs-build-source-newer ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (let ((module-file (expand-file-name "frame-overlay-module.dll"
                                            directory))
              (source-file (expand-file-name "source.cpp"
                                            directory)))
          (with-temp-file module-file)
          (with-temp-file source-file)

          (let ((now (current-time)))
            (set-file-times module-file
                            (time-subtract now (seconds-to-time 60)))
            (set-file-times source-file now))

          (cl-letf (((symbol-function 'frame-overlay--module-file)
                     (lambda () module-file))
                    ((symbol-function 'frame-overlay--native-source-files)
                     (lambda () (list source-file))))
            (should
             (frame-overlay--module-needs-build-p))))
      (delete-directory directory t))))

(ert-deftest frame-overlay-test-module-needs-build-module-newer ()
  (let ((directory (make-temp-file "frame-overlay-test-" t)))
    (unwind-protect
        (let ((module-file (expand-file-name "frame-overlay-module.dll"
                                            directory))
              (source-file (expand-file-name "source.cpp"
                                            directory)))
          (with-temp-file module-file)
          (with-temp-file source-file)

          (let ((now (current-time)))
            (set-file-times source-file
                            (time-subtract now (seconds-to-time 60)))
            (set-file-times module-file now))

          (cl-letf (((symbol-function 'frame-overlay--module-file)
                     (lambda () module-file))
                    ((symbol-function 'frame-overlay--native-source-files)
                     (lambda () (list source-file))))
            (should-not
             (frame-overlay--module-needs-build-p))))
      (delete-directory directory t))))

(provide 'frame-overlay-test)
;;; frame-overlay-test.el ends here

