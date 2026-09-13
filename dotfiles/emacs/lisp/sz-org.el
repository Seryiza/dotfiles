;; === Org mode

(require 'sz-alerts)
(require 'subr-x)
(require 'calendar)

(setq org-directory "~/org")
(setq org-archive-location "~/org/archive/%s::")
(setq org-agenda-files '("~/org"
                         "~/org/areas"
                         "~/org/projects"))

(defun workdayp (date)
  "Return non-nil when DATE is a workday (Monday through Friday)."
  (memq (calendar-day-of-week date) '(1 2 3 4 5)))

(defun everydayp (date)
  "Return non-nil when DATE is any day of the week."
  (memq (calendar-day-of-week date) '(0 1 2 3 4 5 6)))

(defun sz/meow-org-promote-subtree ()
  (interactive)
  (when (derived-mode-p 'org-mode) (org-promote-subtree)))

(defun sz/meow-org-demote-subtree ()
  (interactive)
  (when (derived-mode-p 'org-mode) (org-demote-subtree)))

(defun sz/meow-org-move-subtree-down ()
  (interactive)
  (when (derived-mode-p 'org-mode) (org-move-subtree-down)))

(defun sz/meow-org-move-subtree-up ()
  (interactive)
  (when (derived-mode-p 'org-mode) (org-move-subtree-up)))

(defun sz/org-clipboard-has-image-p ()
  "Return non-nil when the GUI clipboard has image data."
  (when (and (display-graphic-p)
             (fboundp 'gui-get-selection))
    (let ((targets (ignore-errors (gui-get-selection 'CLIPBOARD 'TARGETS)))
          found)
      (when (vectorp targets)
        (setq targets (append targets nil)))
      (while (and (consp targets) (not found))
        (let ((target (car targets)))
          (setq found
                (and (symbolp target)
                     (string-match-p "\\`image/" (symbol-name target)))))
        (setq targets (cdr targets)))
      found)))

(defun sz/org-yank-or-yank-media (&optional arg)
  "Paste a clipboard image in Org, otherwise yank text.
ARG is passed through to `yank' when the clipboard does not contain image
data."
  (interactive "*P")
  (if (and (derived-mode-p 'org-mode)
           (fboundp 'yank-media)
           (sz/org-clipboard-has-image-p))
      (let ((beg (point)))
        (call-interactively #'yank-media)
        (org-display-inline-images nil t beg (point)))
    (yank arg)))

(defun sz/org-files-in-directory (directory)
  "Return Org files under DIRECTORY recursively."
  (let ((directory (expand-file-name directory)))
    (when (file-directory-p directory)
      (directory-files-recursively directory "\\.org\\'"))))

(defun sz/org-refile-area-files ()
  "Return Org refile files from areas."
  (sz/org-files-in-directory "~/org/areas"))

(defun sz/org-refile-project-files ()
  "Return Org refile files from projects."
  (sz/org-files-in-directory "~/org/projects"))

(defun sz/org-area-or-project-file-p (file)
  "Return non-nil when FILE is in Org areas or projects."
  (and (stringp file)
       (let ((file (expand-file-name file)))
         (or (file-in-directory-p file (expand-file-name "~/org/areas/"))
             (file-in-directory-p file (expand-file-name "~/org/projects/"))))))

(defun sz/org-filter-refile-targets (targets)
  "Drop bare file targets for Org areas/projects."
  (delq nil
        (mapcar (lambda (target)
                  (unless (and (null (nth 2 target))
                               (null (nth 3 target))
                               (sz/org-area-or-project-file-p (nth 1 target)))
                    target))
                targets)))

(defun sz/org-project-files ()
  "Return direct Org files from projects."
  (let ((directory (expand-file-name "~/org/projects")))
    (when (file-directory-p directory)
      (directory-files directory t "\\.org\\'"))))

(defun sz/org-project-top3-todo-blocks ()
  "Return agenda blocks with up to 3 TODO items per project file."
  (mapcar
   (lambda (file)
     `(alltodo ""
               ((org-agenda-files '(,file))
                (org-agenda-overriding-header ,(file-name-base file))
                (org-agenda-max-entries 3)
                (org-agenda-prefix-format "%i %s "))))
   (sz/org-project-files)))

(defun sz/org-entry-end-position ()
  "Return the end position of the current Org entry."
  (save-excursion
    (cond
     ((ignore-errors (org-back-to-heading t) t)
      (if (outline-next-heading)
          (point)
        (point-max)))
     ((org-before-first-heading-p)
      (if (re-search-forward org-outline-regexp-bol nil t)
          (match-beginning 0)
        (point-max)))
     (t
      (point-max)))))

(defun sz/org-agenda-skip-active-tasks ()
  "Skip current entry when it is an active task state used elsewhere."
  (unless (org-before-first-heading-p)
    (org-agenda-skip-entry-if 'todo '("STRT" "NEXT"))))

(defun sz/org-timestamp-is-today-p (timestamp)
  "Return non-nil when TIMESTAMP falls on the current day."
  (when timestamp
    (let ((today (decode-time (current-time)))
          (date (decode-time (org-timestamp-to-time timestamp))))
      (and (= (nth 3 date) (nth 3 today))
           (= (nth 4 date) (nth 4 today))
           (= (nth 5 date) (nth 5 today))))))

(defun sz/org-entry-scheduled-timestamp ()
  "Return the current entry scheduled timestamp object, if any."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      (when-let ((scheduled (org-entry-get nil "SCHEDULED")))
        (org-timestamp-from-string scheduled)))))

(defun sz/org-entry-has-tag-p (tag)
  "Return non-nil when the current entry has TAG."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      (member tag (org-get-tags nil t)))))

(defun sz/org-entry-has-timed-timestamp-today-p ()
  "Return non-nil when the current entry has a timed timestamp today."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      (let ((end (sz/org-entry-end-position))
            found)
        (while (and (not found)
                    (re-search-forward org-ts-regexp-both end t))
          (when-let ((timestamp (org-timestamp-from-string (match-string 0))))
            (setq found
                  (and (sz/org-timestamp-is-today-p timestamp)
                       (org-timestamp-has-time-p timestamp)))))
        found))))

(defun sz/org-agenda-skip-daily-timeline ()
  "Skip agenda entries that should not appear in the daily timeline."
  (or (sz/org-agenda-skip-active-tasks)
      (when (or (sz/org-entry-has-tag-p "habit")
                (not (sz/org-entry-has-timed-timestamp-today-p)))
        (sz/org-entry-end-position))))

(defun sz/org-agenda-skip-daily-scheduled ()
  "Skip agenda entries that are not untimed scheduled items for today."
  (or (sz/org-agenda-skip-active-tasks)
      (let ((scheduled (sz/org-entry-scheduled-timestamp)))
        (when (or (sz/org-entry-has-tag-p "habit")
                  (not (sz/org-timestamp-is-today-p scheduled))
                  (org-timestamp-has-time-p scheduled))
          (sz/org-entry-end-position)))))

(defun sz/org-agenda-skip-daily-habit ()
  "Skip agenda entries that are not scheduled habits for today."
  (or (sz/org-agenda-skip-active-tasks)
      (let ((scheduled (sz/org-entry-scheduled-timestamp)))
        (when (or (not (sz/org-entry-has-tag-p "habit"))
                  (not (sz/org-timestamp-is-today-p scheduled)))
          (sz/org-entry-end-position)))))

(defun sz/org-daily-agenda-blocks ()
  "Return agenda blocks for the daily dashboard views."
  `((agenda ""
            ((org-agenda-span 1)
             (org-agenda-start-day "0d")
             (org-agenda-use-time-grid t)
             (org-agenda-skip-scheduled-if-done t)
             (org-agenda-skip-deadline-if-done t)
             (org-agenda-skip-timestamp-if-done t)
             (org-agenda-time-grid '((daily today require-timed)
                                     ()
                                     "......" "----------------"))
             (org-agenda-prefix-format
              '((agenda . " %-15:c%-11t [%-4e] %s")))))
    (todo "STRT"
          ((org-agenda-overriding-header "STRT")
           (org-agenda-skip-function nil)))
    (todo "WAIT"
          ((org-agenda-overriding-header "WAIT")
           (org-agenda-skip-function nil)))))

(use-package org
  :ensure t
  :pin gnu
  :catch nil

  :init
  (setq org-id-locations-file (expand-file-name ".org-id-locations" sz/state-directory)
        org-clock-persist-file (expand-file-name "org-clock-save.el" sz/state-directory)
        org-persist-directory (expand-file-name "org-persist/" sz/cache-directory))
  (sz/state-prepare-paths
   (list org-persist-directory)
   (list org-id-locations-file org-clock-persist-file))

  :hook
  ((org-mode . visual-line-mode)
   (org-agenda-mode . hl-line-mode)
   (org-mode . org-indent-mode))

  :bind
  (("C-c j a" . org-agenda)
   ("C-c j c" . org-capture)
   ("C-c j b" . sz/org-capture-timeblocks-loop)

   :map org-mode-map
   ("C-y" . sz/org-yank-or-yank-media)
   ("C-c C-e" . nil)
   ("C-c C-e C-e" . org-babel-execute-src-block))

  :config
  (add-to-list 'org-modules 'org-habit)
  (require 'org-habit)

  ;; Make org-open-at-point follow file links in the same window
  (setf (cdr (assoc 'file org-link-frame-setup)) 'find-file)

  ;; TODO: debug it with my org files (CANX state?)
  ;; (setq org-element-use-cache nil)

  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "STRT(s!)" "WAIT(w!)" "|" "DONE(d!)" "CANX(c!)")))

  (setq org-outline-path-complete-in-steps nil)
  (setq org-refile-use-outline-path 'full-file-path)
  (setopt org-refile-targets
          '((nil . (:level . 1))
            (sz/org-refile-area-files . (:level . 1))
            (sz/org-refile-project-files . (:level . 1))))
  (advice-remove 'org-refile-get-targets #'sz/org-filter-refile-targets)
  (advice-add 'org-refile-get-targets :filter-return #'sz/org-filter-refile-targets)
  (setq org-link-descriptive nil)

  (setq org-log-into-drawer "LOGBOOK")
  (setq org-log-repeat 'time)
  (setq org-log-done 'time)

  (setq org-startup-with-inline-images t)
  (setq org-yank-image-save-method (expand-file-name "images/" org-directory))
  (setq org-tags-column 40)
  (setq org-confirm-babel-evaluate nil)

  (setq org-habit-following-days 1)
  (setq org-habit-preceding-days 3)
  (setq org-habit-graph-column 60)

  (setq org-blank-before-new-entry
        '((heading . nil)
          (plain-list-item . auto)))

  (setq org-startup-folded 'nofold)
  (setq org-indent-indentation-per-level 2)

  (setopt org-capture-templates
          '(("i" "inbox item" entry (file+olp "inbox.org" "Inbox")
             "* %?\n%i")

            ("t" "TODOs")
            ("tt" "Personal" entry (file+olp "areas/personal.org" "Personal")
             "* TODO %?")

            ("tc" "Clocking" entry (file+olp "areas/personal.org" "Personal")
             "* STRT %^{what}"
             :clock-in t
             :clock-keep t
             :immediate-finish t)

            ("to" "Today" entry (file+olp "areas/personal.org" "Personal")
             "* TODO %?\nSCHEDULED: %t")

            ("tn" "NEXT" entry (file+olp "areas/personal.org" "Personal")
             "* NEXT %?")

            ("b" "Timeblock")

            ("bb" "timeblock" entry (file+olp "areas/personal.org" "Personal")
             "* %^{TIMEBLOCK}  :timeblock:\n%^{TIMESTAMP}T"
             :immediate-finish t)

            ("bh" "Work" entry (file+olp "health-samurai.org" "Health Samurai" "Timeblocks")
             "* WORK   :timeblock:\n%^{TIMESTAMP}T"
             :immediate-finish t)

            ("br" "Rest" entry (file+olp "areas/personal.org" "Personal")
             "* relaxing  :timeblock:rest:\n%U"
             :clock-in t
             :clock-keep t
             :immediate-finish t)

            ("h" "Work")
            ("ht" "TODO" entry (file+olp "health-samurai.org" "Health Samurai" "Tasks")
             "* TODO %^{what}"
             :immediate-finish t)))

  (setopt org-agenda-custom-commands
          `(;; Archive tasks
            ("#" "To archive" todo "DONE|CANX")

            ;; Review weekly appointments
            ("$" "Weekly appointments" agenda* "Weekly appointments")

            ;; Review weekly tasks
            ("w" "Week tasks" agenda "Scheduled tasks for this week"
             ((org-agenda-tag-filter-preset '("-habit" "-routine"))
              (org-deadline-warning-days 0)
              (org-agenda-use-time-grid nil)))

            ;; Review daily tasks
            ("j" "Today Journal"
             ,(sz/org-daily-agenda-blocks))

            ("o" "Work"
             ,(sz/org-daily-agenda-blocks)
             ((org-agenda-files '("~/org/health-samurai.org"))))

            ;; Review project tasks
            ("p" "Top 3 TODOs per project file"
             ,(sz/org-project-top3-todo-blocks))

            ;; Review other non-scheduled/deadlined to-do tasks
            ("t" "TODO" tags-todo "TODO={TODO}+DEADLINE=\"\"+SCHEDULED=\"\"")

            ;; Review upcoming deadlines for the next 60 days
            ("!" "Deadlines all" agenda "Past/upcoming deadlines"
             ((org-agenda-span 1)
              (org-deadline-warning-days 60)
              (org-agenda-entry-types '(:deadline)))))))

(defun sz/org-agenda-save-and-redo (&optional arg)
  "Save all Org buffers, then redo the agenda.
ARG is passed to `org-agenda-redo-all'."
  (interactive "P")
  (org-save-all-org-buffers)
  (org-agenda-redo-all arg))

(use-package org-agenda
  :after org
  :hook
  ((after-save . sz/org-appt-refresh-on-save)
   (org-capture-after-finalize . sz/org-appt-refresh)
   (org-after-todo-state-change . sz/org-appt-refresh))

  :bind
  (:map org-agenda-mode-map
        ("g" . sz/org-agenda-save-and-redo))

  :custom
  (appt-display-format 'window)
  (appt-disp-window-function #'sz/org-appt-display-notification)
  (appt-delete-window-function #'ignore)
  (appt-audible nil)
  (appt-display-diary nil)
  ;; Per-entry APPT_WARNTIME overrides this default.
  (appt-message-warning-time 0)
  (appt-display-interval 10)
  (org-agenda-window-setup 'current-window)

  :config
  (require 'appt)
  (appt-activate 1)
  (sz/org-appt-refresh)

  (unless (timerp sz/org-appt--refresh-timer)
    (setq sz/org-appt--refresh-timer
          (run-at-time "00:01" 86400 #'sz/org-appt-refresh))))

(use-package org-repeat-by-cron
  :ensure t
  :config
  (global-org-repeat-by-cron-mode))

(use-package howm
  :ensure t
  :defer nil

  :hook
  (howm-view-contents-mode . howm-org-font-lock-minor-mode)
  (howm-view-summary-mode . howm-org-font-lock-minor-mode)
  (org-mode . howm-mode)

  :init
  (setq howm-view-title-header "*")
  (setq howm-dtime-format "[%Y-%m-%d %a %H:%M]")
  (setq howm-view-title-skip-regexp
        (concat "\\(^\\*?\\s-*$\\)" "\\|" ;; empty title or ...
                ;; date & time
                (concat "\\(^\\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
                        " .+ " ;; day of the week
                        "[0-9]\\{2\\}:[0-9]\\{2\\}\\]\\)")))
  (setq howm-menu-file-extension ".org")
  (setq howm-menu-skel-replace-rules '(("^= " . "* ") ("^== " . "** ")))

  (setq howm-keyword-body-regexp "[^>=\r\n]+")
  (setq howm-ref-body-regexp "[^=\r\n]+")

  ;; Disable wiki link [[...]] for syntax compatibility.
  (setq howm-wiki-regexp nil)

  (setq howm-directory "~/org/")
  (setq howm-file-name-format "howm/%Y-%m-%d-%H%M%S.org")
  (setq howm-prefix (kbd "C-c ,"))
  (setq howm-keyword-file (expand-file-name ".howm-keys" howm-directory))
  (setq howm-history-file (expand-file-name ".howm-history" howm-directory))
  (setq howm-template "* %title%cursor\n:PROPERTIES:\n:CREATED: %date\n:END:")

  :config
  (defun sz/howm-vtab-window ()
    "Return the current frame's vtab window, when vtab is active."
    (when (and (bound-and-true-p vtab-mode)
               (fboundp 'vtab--get-buffer))
      (get-buffer-window (vtab--get-buffer) (selected-frame))))

  (defun sz/howm-with-vtab-temporarily-deletable (fn &rest args)
    "Let howm rebuild summary/contents windows while vtab is active."
    (let ((vtab-window (sz/howm-vtab-window)))
      (unwind-protect
          (progn
            (when (window-live-p vtab-window)
              (set-window-parameter vtab-window 'no-delete-other-windows nil))
            (apply fn args))
        (when (and (bound-and-true-p vtab-mode)
                   (fboundp 'vtab--ensure-visible))
          (vtab--ensure-visible)))))

  (advice-remove 'riffle-setup-window-configuration
                 #'sz/howm-with-vtab-temporarily-deletable)
  (advice-add 'riffle-setup-window-configuration
              :around #'sz/howm-with-vtab-temporarily-deletable))

(use-package org-download
  :ensure t

  :bind
  (("C-c d C-d" . org-download-clipboard))

  :config
  (setq-default org-download-image-dir "~/org/images"))

(use-package org-limit-image-size
  :after org
  :vc (:url "https://github.com/misohena/org-inline-image-fix"
       :rev :newest)

  :custom
  (org-limit-image-size '(0.9 . 0.45))

  :config
  (org-limit-image-size-activate))

(provide 'sz-org)
