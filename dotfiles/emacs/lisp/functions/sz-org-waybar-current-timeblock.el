;; === Org Waybar integration

(require 'org)
(require 'org-agenda)
(require 'org-clock)
(require 'org-element)
(require 'json)

(defun sz/org-waybar-current-clock ()
  "Return the currently clocked Org heading, or nil."
  (when (and (fboundp 'org-clocking-p)
             (org-clocking-p)
             (bound-and-true-p org-clock-current-task))
    (substring-no-properties org-clock-current-task)))

(defun sz/org-status--clock-snapshot-file ()
  "Return the Org clock snapshot path in the runtime directory."
  (when-let ((runtime-dir (getenv "XDG_RUNTIME_DIR")))
    (expand-file-name "river-zelbar-status-org-clock" runtime-dir)))

(defun sz/org-status-publish-clock ()
  "Atomically publish the current Org clock heading."
  (unless (and (fboundp 'ewm-running) (ewm-running))
    (if-let ((snapshot (sz/org-status--clock-snapshot-file)))
      (condition-case err
          (let ((temporary (make-temp-file
                            (expand-file-name ".river-zelbar-status-org-clock."
                                              (file-name-directory snapshot)))))
            (unwind-protect
                (progn
                  (set-file-modes temporary #o600)
                  (with-temp-file temporary
                    (insert (or (sz/org-waybar-current-clock) "") "\n"))
                  (rename-file temporary snapshot t))
              (when (file-exists-p temporary)
                (delete-file temporary))))
        (error (message "Org clock snapshot: %s" (error-message-string err))))
      (message "Org clock snapshot: XDG_RUNTIME_DIR is unavailable"))))

(defun sz/org-status-delete-clock-snapshot ()
  "Delete the Org clock snapshot if it exists."
  (when-let ((snapshot (sz/org-status--clock-snapshot-file)))
    (condition-case err
        (when (file-exists-p snapshot)
          (delete-file snapshot))
      (error (message "Org clock snapshot: %s" (error-message-string err))))))

(add-hook 'org-clock-in-hook #'sz/org-status-publish-clock)
(add-hook 'org-clock-out-hook #'sz/org-status-publish-clock)
(add-hook 'org-clock-cancel-hook #'sz/org-status-publish-clock)
(add-hook 'kill-emacs-hook #'sz/org-status-delete-clock-snapshot)
(sz/org-status-publish-clock)

(defun sz/org-waybar-timeblock-state (&optional now)
  "Return the current timeblock text and next transition as (TEXT . TIME)."
  (let* ((now (or now (current-time)))
         (decoded (decode-time now))
         (day (nth 3 decoded))
         (month (nth 4 decoded))
         (year (nth 5 decoded))
         (text nil)
         (next-time (encode-time 0 0 0 (1+ day) month year)))
    (dolist (file (org-agenda-files))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-element-map (org-element-parse-buffer) 'timestamp
           (lambda (timestamp)
             (when (and (eq (org-element-property :type timestamp) 'active-range)
                        (eq (org-element-property :range-type timestamp) 'timerange)
                        (= (org-element-property :year-start timestamp) year)
                        (= (org-element-property :month-start timestamp) month)
                        (= (org-element-property :day-start timestamp) day))
               (let* ((start-hour (org-element-property :hour-start timestamp))
                      (start-minute (org-element-property :minute-start timestamp))
                      (end-hour (org-element-property :hour-end timestamp))
                      (end-minute (org-element-property :minute-end timestamp))
                      (start (encode-time 0 start-minute start-hour day month year))
                      (end (encode-time 0 end-minute end-hour day month year)))
                 (when (time-less-p start end)
                   (when (and (time-less-p now start) (time-less-p start next-time))
                     (setq next-time start))
                   (when (and (time-less-p now end) (time-less-p end next-time))
                     (setq next-time end))
                   (when (and (null text) (not (time-less-p now start)) (time-less-p now end))
                     (goto-char (org-element-property :begin timestamp))
                     (org-back-to-heading t)
                     (setq text
                           (substring-no-properties
                            (format "%s -> %02d:%02d"
                                    (substring-no-properties (org-get-heading t t t t))
                                    end-hour end-minute))))))))))))
    (cons text next-time)))

(defun sz/org-waybar-timeblock-state-payload ()
  "Return the current timeblock state as one base64-encoded JSON line."
  (let ((state (sz/org-waybar-timeblock-state)))
    (base64-encode-string
     (json-serialize
      (list :text (or (car state) "")
            :next_transition (floor (float-time (cdr state)))))
     t)))

(defun sz/org-waybar-current-scheduled-timeblock ()
  "Return scheduled timeblock as \"<heading> -> <end-time>\", or nil."
  (car (sz/org-waybar-timeblock-state)))

(defun sz/org-waybar-current-clocking-todo ()
  "Return the active Org clock TODO heading, or nil."
  (sz/org-waybar-current-clock))
