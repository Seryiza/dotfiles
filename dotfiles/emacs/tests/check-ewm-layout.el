;;; check-ewm-layout.el --- Live XKB checks for EWM -*- lexical-binding: t -*-

(require 'cl-lib)
(require 'org-capture)

(defun sz/ewm-test-layout-live (&optional expected-module)
  "Check Ctrl+Space in M-x and Org's real template-selection menu.
Run in an idle EWM session with ydotool available.  Briefly injects keys into
test prompts; restores the layout and windows, and never captures a note.
When EXPECTED-MODULE is non-nil, require that exact native module to be loaded."
  (unless (and (bound-and-true-p ewm-mode) (bound-and-true-p ewm--module-mode))
    (user-error "Run this check inside the EWM server"))
  (when (active-minibuffer-window)
    (user-error "Close the active minibuffer before running this check"))
  (unless (executable-find "ydotool") (user-error "ydotool is required"))
  (let* ((loaded (cl-find-if
                  (lambda (entry)
                    (and (stringp (car entry))
                         (string-match-p "\\(?:ewm-core\\|libewm_core\\)\\.so\\'" (car entry))))
                  load-history))
         (original-layout sz/ewm-status-layout)
         (ewm-input--intercepted-command-active t)
         (last-nonmenu-event nil)
         results)
    (when (and expected-module
               (not (and loaded
                         (equal (file-truename (car loaded))
                                (file-truename expected-module)))))
      (user-error "Restart EWM with the new native module first; loaded: %s" (car loaded)))
    (unwind-protect
        (save-window-excursion
          (dolist (context '(M-x org-capture))
            (let ((org-capture-templates
                   '(("a" "Layout check" entry (file "/dev/null") "* %?")))
                  timers process input failure after)
              (unwind-protect
                  (progn
                    (ewm-switch-layout-module "ru")
                    (sit-for 0.3)
                    (push (run-at-time
                           0.4 nil
                           (lambda ()
                             (setq process
                                   (start-process "ewm-layout-check" nil
                                                  "ydotool" "key" "-d" "70"
                                                  "29:1" "57:1" "57:0" "29:0"
                                                  "30:1" "30:0"))))
                          timers)
                    (push (run-at-time
                           1.6 nil
                           (lambda ()
                             (if (eq context 'M-x)
                                 (progn
                                   (setq input (minibuffer-contents-no-properties))
                                   (abort-recursive-edit))
                               (setq unread-command-events
                                     (cons ?\C-g unread-command-events)))))
                          timers)
                    (condition-case err
                        (if (eq context 'M-x)
                            (call-interactively #'execute-extended-command)
                          (setq input (car (org-capture-select-template))))
                      (quit nil)
                      (error (setq failure (error-message-string err))))
                    (setq after sz/ewm-status-layout)
                    (push (list :context context :input input :layout after
                                :error failure
                                :pass (and (not failure) (equal input "a")
                                           (equal after "us")))
                          results))
                (mapc #'cancel-timer timers)
                ;; The menu can return on key-down, before ydotool sends key-up.
                (when (and process (process-live-p process))
                  (accept-process-output process 1)
                  (when (process-live-p process)
                    (delete-process process)
                    (call-process "ydotool" nil nil nil "key" "-d" "0"
                                  "29:0" "57:0" "30:0")))
                (ewm-input--sync-keyboard-capture)
                (ewm-layout--refresh)))))
      (ewm-switch-layout-module original-layout)
      (ewm-input--sync-keyboard-capture)
      (ewm-layout--refresh))
    (setq results (nreverse results))
    (unless (cl-every (lambda (result) (plist-get result :pass)) results)
      (error "EWM layout check failed: %S" results))
    results))

;;; check-ewm-layout.el ends here
