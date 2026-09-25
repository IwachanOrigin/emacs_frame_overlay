;;; frame-overlay-test.el --- Tests for frame-overlay -*- lexical-binding: t; -*-

(require 'ert)
(require 'frame-overlay)

(ert-deftest frame-overlay-test-position-code-top-left ()
  (let ((frame-overlay-position 'top-left))
    (should (= (frame-overlay--position-code) 0))))

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

(ert-deftest frame-overlay-test-imaeg-options-valid ()
  (let ((frame-overlay-scale 1.0)
        (frame-overlay-image-alpha 255)
        (frame-overlay-margin-x 24)
        (frame-overlay-margin-y 24))
    (frame-overlay--validate-image-options)))


