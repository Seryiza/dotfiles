(unless (featurep 'sz-state)
  (error "Early-init state setup failed; refusing to initialize packages"))

;; Bootstrap package system

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(require 'use-package)

;; Packages installed in NixOS
(setq package-hidden-regexps
      '("\\`vterm\\'"
        "\\`telega\\'"
        "\\`visual-fill-column\\'"
        "\\`mu4e\\'"))

(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage t))

(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(use-package sz-ewm
  :ensure nil
  :catch nil
  :load-path "lisp/ewm"
  :demand t)

(let* ((dir (locate-user-emacs-file "lisp"))
       (functions-dir (expand-file-name "functions" dir))
       (function-files
        '("sz-howm-create-note.el"
          "sz-org-capture-frame.el"
          "sz-org-capture-timeblocks-loop.el"
          "sz-org-waybar-current-timeblock.el"
          "sz-telega-capture-message-to-inbox.el"
          "sz-telega-save-msg-media.el"))
       (files '("sz-base.el"
                "sz-theme.el"
                "sz-meow.el"
                "sz-eat.el"
                "sz-alerts.el"
                "sz-org.el"
                "sz-telega.el"
                "sz-mode-line.el")))

  ;; Load my emacs modules
  (dolist (file files)
    (load (expand-file-name file dir) nil 'nomessage t))

  ;; Load elisp commands and functions
  (dolist (file function-files)
    (load (expand-file-name file functions-dir) nil 'nomessage t)))
