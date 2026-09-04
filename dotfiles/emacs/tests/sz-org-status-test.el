(require 'ert)

(load (expand-file-name "../lisp/functions/sz-org-waybar-current-timeblock.el"
                        (file-name-directory load-file-name)))

(defmacro sz/org-status-test-with-runtime (&rest body)
  `(let* ((runtime (make-temp-file "org-status-runtime" t))
          (process-environment (copy-sequence process-environment)))
     (setenv "XDG_RUNTIME_DIR" runtime)
     (unwind-protect
         (progn ,@body)
       (delete-directory runtime t))))

(defun sz/org-status-test-snapshot ()
  (with-temp-buffer
    (insert-file-contents (sz/org-status--clock-snapshot-file))
    (buffer-string)))

(defmacro sz/org-status-test-with-agenda (contents &rest body)
  `(let* ((file (make-temp-file "org-status" nil ".org"))
          (org-agenda-files (list file)))
     (unwind-protect
         (progn
           (with-temp-file file (insert ,contents))
           ,@body)
       (when-let ((buffer (get-file-buffer file)))
         (kill-buffer buffer))
       (delete-file file))))

(ert-deftest sz/org-status-clock-hooks-publish-unsaved-state ()
  (sz/org-status-test-with-runtime
   (with-temp-buffer
     (org-mode)
     (insert "* TODO Clocked task\n")
     (goto-char (point-min))
     (unwind-protect
         (progn
           (org-clock-in)
           (should (equal (sz/org-status-test-snapshot) "Clocked task\n"))
           (org-clock-out)
           (should (equal (sz/org-status-test-snapshot) "\n"))
           (org-clock-in)
           (org-clock-cancel)
           (should (equal (sz/org-status-test-snapshot) "\n")))
       (when (org-clocking-p) (org-clock-out))))))

(ert-deftest sz/org-status-clock-startup-and-delete ()
  (sz/org-status-test-with-runtime
   (sz/org-status-publish-clock)
   (should (equal (sz/org-status-test-snapshot) "\n"))
   (sz/org-status-delete-clock-snapshot)
   (should-not (file-exists-p (sz/org-status--clock-snapshot-file)))))

(ert-deftest sz/org-status-clock-switch-publishes-new-heading ()
  (sz/org-status-test-with-runtime
   (with-temp-buffer
     (org-mode)
     (insert "* TODO A\n* TODO B\n")
     (unwind-protect
         (progn
           (goto-char (point-min))
           (org-clock-in)
           (goto-char (point-max))
           (org-back-to-heading t)
           (org-clock-in)
           (should (equal (sz/org-status-test-snapshot) "B\n")))
       (when (org-clocking-p) (org-clock-out))))))

(ert-deftest sz/org-status-timeblocks-select-first-overlap-and-boundaries ()
  (sz/org-status-test-with-agenda
   "* A\n<2026-09-04 Fri 10:30-11:00>\n* B\n<2026-09-04 Fri 10:00-11:00>\n"
   (should (equal (car (sz/org-waybar-timeblock-state (encode-time 0 0 10 4 9 2026)))
                  "B -> 11:00"))
   (should (equal (car (sz/org-waybar-timeblock-state (encode-time 0 30 10 4 9 2026)))
                  "A -> 11:00"))
   (should (equal (car (sz/org-waybar-timeblock-state (encode-time 0 0 11 4 9 2026)))
                  nil))))

(ert-deftest sz/org-status-timeblocks-track-earliest-transition-and-midnight ()
  (sz/org-status-test-with-agenda
   "* A\n<2026-09-04 Fri 09:00-11:00>\n* B\n<2026-09-04 Fri 10:30-12:00>\n"
   (let ((state (sz/org-waybar-timeblock-state (encode-time 0 0 10 4 9 2026))))
     (should (equal (car state) "A -> 11:00"))
     (should (equal (format-time-string "%H:%M" (cdr state)) "10:30"))))
  (sz/org-status-test-with-agenda
   "* Tomorrow\n<2026-09-05 Sat 09:00-10:00>\n"
   (let ((state (sz/org-waybar-timeblock-state (encode-time 0 0 23 4 9 2026))))
     (should (equal (format-time-string "%Y-%m-%d %H:%M" (cdr state))
                    "2026-09-05 00:00")))))
