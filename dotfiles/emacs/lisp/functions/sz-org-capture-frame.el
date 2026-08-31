;;; sz-org-capture-frame.el --- Org Capture in a disposable client frame

(require 'org-capture)
(require 'cl-lib)

(defun sz/org-capture--close-frame (&optional frame)
  "Delete FRAME when it belongs to a dedicated Org Capture session."
  (let ((frame (or frame (selected-frame))))
    (when (and (frame-live-p frame)
               (frame-parameter frame 'sz-org-capture-frame))
      (let ((blank-buffer (frame-parameter frame 'sz-org-capture-blank-buffer)))
        (delete-frame frame t)
        (when (buffer-live-p blank-buffer)
          (kill-buffer blank-buffer))))))

(defun sz/org-capture-in-frame ()
  "Start Org Capture in the selected disposable client frame."
  (let* ((frame (selected-frame))
         (blank-buffer (generate-new-buffer " *org-capture*")))
    (set-frame-parameter frame 'sz-org-capture-frame t)
    (set-frame-parameter frame 'sz-org-capture-blank-buffer blank-buffer)
    (switch-to-buffer blank-buffer)
    (delete-other-windows)
    (condition-case err
        (cl-letf (((symbol-function 'switch-to-buffer-other-window)
                   (lambda (buffer &rest _)
                     (prog1 (switch-to-buffer buffer)
                       (make-frame-visible frame))))
                  ((symbol-function 'org-display-buffer-split)
                   (lambda (buffer _)
                     (display-buffer-same-window buffer nil))))
          (org-capture))
      ((quit user-error)
       (sz/org-capture--close-frame frame))
      (error
       (sz/org-capture--close-frame frame)
       (signal (car err) (cdr err))))))

(add-hook 'org-capture-after-finalize-hook #'sz/org-capture--close-frame)

(provide 'sz-org-capture-frame)
;;; sz-org-capture-frame.el ends here
