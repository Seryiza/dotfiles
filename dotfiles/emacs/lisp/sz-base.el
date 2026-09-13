;; === Base options

(use-package emacs
  :ensure nil
  :catch nil
  :init
  (setq sz/backup-directory (expand-file-name "backups/" sz/state-directory)
        sz/auto-save-directory (expand-file-name "auto-save-list/" sz/state-directory))
  (sz/state-prepare-paths
   (list sz/backup-directory sz/auto-save-directory) nil)
  (setq backup-directory-alist `(("." . ,sz/backup-directory))
        auto-save-file-name-transforms `((".*" ,sz/auto-save-directory t))
        auto-save-list-file-prefix (expand-file-name ".saves-" sz/auto-save-directory)
        backup-by-copying t
        delete-old-versions t
        kept-new-versions 6
        kept-old-versions 2
        version-control t))

(use-package recentf
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq recentf-save-file (expand-file-name "recentf" sz/state-directory))
  (sz/state-prepare-paths nil (list recentf-save-file)))

(use-package bookmark
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq bookmark-default-file (expand-file-name "bookmarks" sz/state-directory))
  (sz/state-prepare-paths nil (list bookmark-default-file)))

(use-package tramp
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq tramp-persistency-file-name (expand-file-name "tramp" sz/state-directory))
  (sz/state-prepare-paths nil (list tramp-persistency-file-name)))

(use-package transient
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq transient-levels-file (expand-file-name "transient/levels.el" sz/state-directory)
        transient-values-file (expand-file-name "transient/values.el" sz/state-directory)
        transient-history-file (expand-file-name "transient/history.el" sz/state-directory))
  (sz/state-prepare-paths
   (list (expand-file-name "transient/" sz/state-directory))
   (list transient-levels-file transient-values-file transient-history-file)))

(use-package url
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq url-configuration-directory (expand-file-name "url/" sz/state-directory)
        url-cookie-file (expand-file-name "url/cookies" sz/state-directory)
        url-history-file (expand-file-name "url/history" sz/state-directory)
        url-cache-directory (expand-file-name "url/" sz/cache-directory))
  (sz/state-prepare-paths
   (list url-configuration-directory url-cache-directory)
   (list url-cookie-file url-history-file)))

(use-package svg-lib
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq svg-lib-icons-dir (expand-file-name "svg-lib/" sz/cache-directory))
  (sz/state-prepare-paths (list svg-lib-icons-dir) nil))

(use-package treesit
  :ensure nil
  :catch nil
  :defer t
  :init
  (setq sz/tree-sitter-directory (expand-file-name "tree-sitter/" sz/cache-directory))
  (sz/state-prepare-paths (list sz/tree-sitter-directory) nil)
  (add-to-list 'treesit-extra-load-path sz/tree-sitter-directory)

  (defun sz/state--treesit-install-language-grammar (function lang &optional out-dir)
    "Call FUNCTION for LANG with XDG defaults while preserving explicit OUT-DIR."
    (cond
     ((eq out-dir 'interactive)
      (let (updated-history result)
        (let ((treesit--install-language-grammar-out-dir-history
               (cons sz/tree-sitter-directory
                     (delete sz/tree-sitter-directory
                             (copy-sequence
                              treesit--install-language-grammar-out-dir-history)))))
          (setq result (funcall function lang out-dir)
                updated-history treesit--install-language-grammar-out-dir-history))
        (setq treesit--install-language-grammar-out-dir-history updated-history)
        result))
     ((null out-dir)
      (funcall function lang sz/tree-sitter-directory))
     (t
      (funcall function lang out-dir))))

  (with-eval-after-load 'treesit
    (unless (advice-member-p #'sz/state--treesit-install-language-grammar
                             'treesit-install-language-grammar)
      (advice-add 'treesit-install-language-grammar :around
                  #'sz/state--treesit-install-language-grammar))))

(require 'sz-alerts)
(require 'seq)

(setopt initial-major-mode 'fundamental-mode)
(setopt display-time-default-load-average nil)

(setopt user-full-name "Sergey Zaborovsky")
(setopt user-mail-address "hey@seryiza.xyz")

(setopt auto-revert-avoid-polling t)
(setopt auto-revert-use-notify t)
(setopt auto-revert-interval 5)
(setopt auto-revert-check-vc-info nil)
(setopt auto-revert-verbose nil)
(global-auto-revert-mode)

(use-package savehist
  :ensure nil
  :catch nil
  :init
  (setq savehist-file (expand-file-name "history" sz/state-directory))
  (sz/state-prepare-paths nil (list savehist-file))
  :config
  (savehist-mode 1))

;; Move through windows with Ctrl-<arrow keys>
(windmove-default-keybindings 'control)

(winner-mode 1)

(setopt use-short-answers t)
(setopt use-dialog-box nil)

(setopt sentence-end-double-space nil)

;; Make right-click do something sensible
(when (and (display-graphic-p) (fboundp 'context-menu-mode))
  (context-menu-mode))

(setopt make-backup-files t)
(setopt create-lockfiles nil)

(use-package which-key
  :ensure t
  :config (which-key-mode))

(setopt enable-recursive-minibuffers t)
(setopt completion-cycle-threshold 1)
(setopt completions-detailed t)
(setopt tab-always-indent 'complete)
(setopt completion-auto-help 'always)
(setopt completions-max-height 20)
(setopt completions-format 'one-column)
(setopt completions-group t)
(setopt completion-auto-select 'second-tab)
;; (setopt completion-auto-select t) ; See `C-h v completion-auto-select' for more possible values

;; TAB acts more like how it does in the shell
(keymap-set minibuffer-mode-map "TAB" 'minibuffer-complete)

(setopt line-number-mode t)
(setopt column-number-mode t)

(setopt x-underline-at-descent-line nil)
(setopt switch-to-buffer-obey-display-actions t)

(setopt show-trailing-whitespace nil)
(setopt indicate-buffer-boundaries 'left)

(setopt mouse-wheel-tilt-scroll t)
(setopt mouse-wheel-flip-direction t)

(setopt indent-tabs-mode nil)
(setopt tab-width 4)

(blink-cursor-mode t)
(setopt blink-cursor-interval 0.7)

(setq scroll-margin 1
      scroll-conservatively 10000
      scroll-up-aggressively 0.01
      scroll-down-aggressively 0.01)

(unless (display-graphic-p)
  (require 'term/xterm)
  ;; Force modified special keys like S-RET to be reported in TTY Emacs.
  (setq xterm-extra-capabilities
        '(modifyOtherKeys reportBackground getSelection setSelection))
  (when (eq (terminal-parameter nil 'terminal-initted) 'terminal-init-xterm)
    (xterm--init-modify-other-keys))
  (xterm-mouse-mode 1))

(setopt display-line-numbers-width 3)

(setopt display-time-format "%a %F %T")
(setopt display-time-interval 1)
(display-time-mode -1)

;; Default frame configuration
(setq frame-resize-pixelwise t)
(tool-bar-mode -1) ; All these tools are in the menu-bar anyway
(menu-bar-mode -1)

(setq default-frame-alist '((fullscreen . maximized)

                            ;; You can turn off scroll bars by uncommenting these lines:
                            ;; (vertical-scroll-bars . nil)
                            ;; (horizontal-scroll-bars . nil)
                            ))

(defconst sz/default-font-family "Iosevka")
;; (defconst sz/default-font-family "Iosevka Slab")
;; (defconst sz/default-font-family "Go Mono")
(defconst sz/default-font-size 12)

(defun sz/apply-default-font (&optional frame)
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (set-face-attribute 'default nil
                          :family sz/default-font-family
                          :height (* 10 sz/default-font-size)
                          :weight 'normal
                          :width 'condensed))))

(add-to-list 'default-frame-alist
             `(font . ,(format "%s-%d" sz/default-font-family sz/default-font-size)))

(sz/apply-default-font)

(defun sz/reinit-el ()
  "Reload the current `user-init-file`."
  (interactive)
  (load user-init-file nil t t)   ; noerror=nil, nomessage=t, nosuffix=t
  (message "Reloaded %s" user-init-file))

(defun sz/current-tab-index ()
  "Return the zero-based index of the current tab."
  (seq-position (funcall tab-bar-tabs-function)
                'current-tab
                (lambda (tab marker)
                  (eq (car tab) marker))))

(defun sz/tab-next-no-wrap ()
  "Switch to the next tab without wrapping.
Return non-nil when a tab was selected."
  (let* ((tabs (funcall tab-bar-tabs-function))
         (index (sz/current-tab-index)))
    (when (and index (< index (1- (length tabs))))
      (tab-bar-select-tab (+ index 2))
      t)))

(defun sz/tab-previous-no-wrap ()
  "Switch to the previous tab without wrapping.
Return non-nil when a tab was selected."
  (let ((index (sz/current-tab-index)))
    (when (and index (> index 0))
      (tab-bar-select-tab index)
      t)))

(defun sz/move-or-switch-tab (direction)
  "Move to window in DIRECTION, or switch tabs when none exists.
An active minibuffer counts as a window target so the movement keys
can move focus back to minibuffer input.  Tab switching does not wrap
from the last tab to the first, or from the first tab to the last.
Return non-nil when Emacs handled the movement."
  (let ((target (window-in-direction direction)))
    (cond
     (target
      (select-window target)
      t)
     ((memq direction '(right below))
      (sz/tab-next-no-wrap))
     (t
      (sz/tab-previous-no-wrap)))))

(defun sz/sway-nav (direction)
  "Handle Sway-dispatched directional navigation inside Emacs.
Return non-nil when Emacs moved to another window or non-wrapping tab.
Return nil when Sway should fall back to its own directional focus."
  (sz/move-or-switch-tab direction))

(defun sz/below-or-tab-next ()
  (interactive)
  (sz/move-or-switch-tab 'below))

(defun sz/above-or-tab-previous ()
  (interactive)
  (sz/move-or-switch-tab 'above))

(defun sz/left-or-tab-previous ()
  (interactive)
  (sz/move-or-switch-tab 'left))

(defun sz/right-or-tab-next ()
  (interactive)
  (sz/move-or-switch-tab 'right))

(defun sz/sway-new-tab ()
  "Handle Sway-dispatched new-Emacs action inside Emacs.
Open a new tab in the current frame.  Return non-nil when Emacs
handled the request."
  (tab-new)
  t)

(defun sz/sway-close ()
  "Handle Sway-dispatched close action inside Emacs.
Close the current tab when more than one tab exists in the selected
frame.  When this is the frame's only tab, close the selected frame
instead.  Return non-nil when Emacs handled the close request."
  (let ((tabs (funcall tab-bar-tabs-function)))
    (if (> (length tabs) 1)
        (tab-close)
      (delete-frame nil t)))
  t)

;; === Packages

;; Dired is built-in, so use :ensure nil.
(use-package dired
  :ensure nil
  :bind (:map dired-mode-map
              ("," . make-directory))
  :config
  ;; Must include "-l" per the manual.
  (setq dired-listing-switches "-al --group-directories-first")
  (setq dired-kill-when-opening-new-dired-buffer t)
  (setq dired-dwim-target t)
  (setq delete-by-moving-to-trash t)
  (setq dired-free-space nil)
  (setq dired-auto-revert-buffer t))

(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)     ; orig. switch-to-buffer
         ("M-y"   . consult-yank-pop)   ; orig. yank-pop
         ;; Searching
         ("C-c f C-g" . consult-ripgrep)
         ("M-s l" . consult-line)       ; Alternative: rebind C-s to use
         ("M-s s" . consult-line)       ; consult-line instead of isearch, bind
         ("M-s L" . consult-line-multi) ; isearch to M-s s
         ("M-s o" . consult-outline)
         ;; Isearch integration
         :map isearch-mode-map
         ("M-e" . consult-isearch-history)   ; orig. isearch-edit-string
         ("M-s e" . consult-isearch-history) ; orig. isearch-edit-string
         ("M-s l" . consult-line)            ; needed by consult-line to detect isearch
         ("M-s L" . consult-line-multi))     ; needed by consult-line to detect isearch
  :config (setq consult-narrow-key "<"))

(use-package vertico
  :ensure t
  :init (vertico-mode))

(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map ("M-DEL" . vertico-directory-delete-word)))

(use-package corfu
  :ensure t

  :init
  (global-corfu-mode 1)

  :bind
  (:map corfu-map
        ("C-n" . corfu-next)
        ("C-p" . corfu-previous))

  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-auto-delay 0.05)
  (corfu-auto-trigger ".")
  (corfu-preselect 'prompt))

(use-package corfu-popupinfo
  :after corfu
  :ensure nil
  :hook (corfu-mode . corfu-popupinfo-mode)
  :custom
  (corfu-popupinfo-delay '(0.25 . 0.1))
  (corfu-popupinfo-hide nil)
  :config (corfu-popupinfo-mode))

(use-package corfu-terminal
  :if (not (display-graphic-p))
  :ensure t
  :config (corfu-terminal-mode))

(use-package cape
  :ensure t
  :init
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file))

(use-package kind-icon
  :if (display-graphic-p)
  :ensure t
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

(use-package eshell
  :ensure nil
  :catch nil
  :init
  (setq eshell-directory-name (expand-file-name "eshell/" sz/state-directory))
  (sz/state-prepare-paths (list eshell-directory-name) nil)
  (defun bedrock/setup-eshell ()
    ;; Something funny is going on with how Eshell sets up its keymaps; this is
    ;; a work-around to make C-r bound in the keymap
    (keymap-set eshell-mode-map "C-r" 'consult-history))
  :hook (eshell-mode . bedrock/setup-eshell))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-pcm-leading-wildcard t))

(use-package wgrep
  :ensure t
  :config (setq wgrep-auto-save-buffer t))

(use-package emacs
  :hook
  ((before-save . whitespace-cleanup)
   (prog-mode . electric-pair-mode)
   (prog-mode . eldoc-mode)
   (text-mode . hl-line-mode)
   (prog-mode . hl-line-mode)
   (text-mode . display-line-numbers-mode)
   (prog-mode . display-line-numbers-mode)
   (text-mode . visual-line-mode)
   (after-make-frame-functions . sz/apply-default-font))

  :bind
  (:map emacs-lisp-mode-map
    ("C-c C-e" . nil)
    ("C-c C-e C-e" . eval-last-sexp)
    ("C-c C-e C-b" . eval-buffer)
    ("C-c C-e C-f" . eval-defun))

  :config
  (setq show-paren-delay 0)
  (show-paren-mode 1)
  (global-eldoc-mode -1)

  ;; (setq tab-bar-auto-width t)
  ;; (setq tab-bar-auto-width-max '(200 16))
  ;; (setq tab-bar-close-button-show nil)
  ;; (setq tab-bar-tab-hints nil)
  ;; (setq tab-bar-format '(tab-bar-format-tabs tab-bar-separator))

  (setopt treesit-language-source-alist
          '((css "https://github.com/tree-sitter/tree-sitter-css")
            (javascript "https://github.com/tree-sitter/tree-sitter-javascript")
            (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
            (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
            (yaml "https://github.com/tree-sitter-grammars/tree-sitter-yaml")
            (json "https://github.com/tree-sitter/tree-sitter-json")))

  ;; Tell Emacs to prefer the treesitter mode
  ;; You'll want to run the command `M-x treesit-install-language-grammar' before editing.
  (setq major-mode-remap-alist
        '((yaml-mode . yaml-ts-mode)
          (bash-mode . bash-ts-mode)
          (js-mode . js-ts-mode)
          (js2-mode . js-ts-mode)
          (tsx-mode . tsx-ts-mode)
          (json-mode . json-ts-mode)
          (css-mode . css-ts-mode)
          (python-mode . python-ts-mode))))

(use-package project
  :ensure nil
  :catch nil
  :init
  (setq project-list-file (expand-file-name "projects" sz/state-directory))
  (sz/state-prepare-paths nil (list project-list-file))
  :custom (when (>= emacs-major-version 30)
            (project-mode-line t)))

(use-package magit
  :ensure t
  :bind (("C-x g" . magit-status)))

(use-package markdown-mode
  :ensure t
  :hook (markdown-mode . visual-line-mode))

(use-package verb
  :ensure t
  :after org
  :config
  (define-key org-mode-map (kbd "C-c C-r") verb-command-map))

(use-package yaml-mode
  :ensure t)

(use-package json-mode
  :ensure t)

(use-package js
  :ensure nil
  :custom
  (js-indent-level 2))

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.mts\\'" . typescript-ts-mode)
         ("\\.cts\\'" . typescript-ts-mode)))

(use-package tsx-ts-mode
  :ensure nil
  :mode ("\\.tsx\\'" . tsx-ts-mode))

(use-package add-node-modules-path
  :ensure t
  :hook ((js-mode js-ts-mode typescript-ts-mode tsx-ts-mode)
         . add-node-modules-path))

(use-package make-mode
  :ensure nil
  :hook (makefile-mode . (lambda () (setq indent-tabs-mode t))))

(use-package eglot
  :hook (((js-mode js-ts-mode typescript-ts-mode tsx-ts-mode)
          . eglot-ensure)
         (eglot-managed-mode . eglot-inlay-hints-mode))
  :custom
  (eglot-send-changes-idle-time 0.1)
  (eglot-extend-to-xref t)

  :config
  (fset #'jsonrpc--log-event #'ignore)
  (add-to-list 'eglot-server-programs
               `(((js-mode :language-id "javascript")
                  (js-ts-mode :language-id "javascript")
                  (tsx-ts-mode :language-id "typescriptreact")
                  (typescript-ts-mode :language-id "typescript")
                  (typescript-mode :language-id "typescript"))
                 . ,(eglot-alternatives
                     '(("vtsls" "--stdio")
                       ("typescript-language-server" "--stdio"))))))

(use-package rg
  :ensure t)

(use-package tempel
  :ensure t
  :bind (("M-*" . tempel-insert)
         ("M-+" . tempel-complete)
         :map tempel-map
         ("C-c RET" . tempel-done)
         ("C-<down>" . tempel-next)
         ("C-<up>" . tempel-previous)
         ("M-<down>" . tempel-next)
         ("M-<up>" . tempel-previous))
  :hook
  ((prog-mode . tempel-setup-capf)
   (text-mode . tempel-setup-capf))
  :init
  ;; Make a function that adds the tempel expansion function to the
  ;; list of completion-at-point-functions (capf).
  (defun tempel-setup-capf ()
    (add-hook 'completion-at-point-functions #'tempel-expand -1 'local)))

(use-package super-save
  :ensure t
  :config
  (super-save-mode +1)
  (setq super-save-auto-save-when-idle t))

(use-package inheritenv
  :vc (:url "https://github.com/purcell/inheritenv" :rev :newest))

(use-package elfeed
  :ensure t
  :catch nil
  :init
  (setq elfeed-db-directory (expand-file-name "elfeed/" sz/data-directory))
  (sz/state-prepare-paths (list elfeed-db-directory) nil)
  :config
  (defun sz/elfeed-mark-auto-read-tags-read (entry)
    "Mark ENTRY as read when it has the `hide' tag."
    (when (elfeed-tagged-p 'hide entry)
      (elfeed-untag entry 'unread)))

  (add-hook 'elfeed-new-entry-hook #'sz/elfeed-mark-auto-read-tags-read t))

(use-package elfeed-org
  :ensure t
  :config
  (setq rmh-elfeed-org-files (list "~/org/rss.org"))
  (elfeed-org))

(use-package mu4e
  :ensure nil
  :custom
  (mu4e-update-interval (* 5 60))
  (mu4e-get-mail-command "true")

  :config
  (mu4e-modeline-mode -1)
  (setq mu4e-bookmarks
        (cons '(:name "Inbox"
                :query "maildir:/fastmail/INBOX"
                :key ?i
                :favorite t)
              mu4e-bookmarks))

  (add-hook 'mu4e-query-items-updated-hook #'sz/mu4e-notify-new-mail)

  ;; Start background mu4e for emacs server
  (when (daemonp)
    (mu4e t)))

(use-package flycheck
  :ensure t
  :init (global-flycheck-mode))

(use-package nix-mode
  :ensure t
  :mode "\\.nix^\\'"
  ;; :hook (before-save . nix-format-before-save)
  )

(use-package windmove
  :ensure nil
  :bind* (("M-h" . windmove-left)
          ("M-l" . windmove-right)))

(use-package agent-shell
  :ensure t
  :catch nil
  :init
  (setq shell-maker-root-path sz/state-directory)
  (sz/state-prepare-paths
   (list (expand-file-name "agent/" sz/state-directory)) nil))

(use-package agent-shell-sidebar
  :after agent-shell
  :vc (:url "https://github.com/cmacrae/agent-shell-sidebar")

  :custom
  (agent-shell-sidebar-position 'right)
  (agent-shell-sidebar-width "50%")

  :bind
  (("C-c a s" . agent-shell-sidebar-toggle)
   ("C-c a f" . agent-shell-sidebar-toggle-focus)))

(use-package diff-hl
  :ensure t
  :hook
  ((prog-mode . diff-hl-mode)
   (magit-post-refresh . diff-hl-magit-post-refresh)))

(use-package projectile
  :ensure t
  :catch nil
  :init
  (setq projectile-known-projects-file
        (expand-file-name "projectile-bookmarks.eld" sz/state-directory)
        projectile-frecency-file
        (expand-file-name "projectile-frecency.eld" sz/state-directory)
        projectile-session-directory
        (expand-file-name "projectile-sessions/" sz/state-directory))
  (sz/state-prepare-paths
   (list projectile-session-directory)
   (list projectile-known-projects-file projectile-frecency-file))
  (projectile-mode +1)

  :bind
  ("C-c o C-s" . projectile-run-shell)
  ("C-c o C-v" . projectile-run-vterm)
  ("C-c f C-f" . projectile-find-file))

(use-package flycheck-clj-kondo
  :ensure t)

(use-package clojure-mode
  :ensure t

  :init
  (defun format-clojure ()
    (when (or (eq major-mode 'clojure-mode)
              (eq major-mode 'clojurec-mode)
              (eq major-mode 'clojurescript-mode))
      (shell-command-to-string
       (if (file-exists-p (concat (projectile-project-root buffer-file-name) ".cljfmt.edn"))
           (format "cljfmt fix --config %s %s"
                   (concat (projectile-project-root buffer-file-name) ".cljfmt.edn")
                   buffer-file-name)
         (format "cljfmt fix %s" buffer-file-name)))
      (revert-buffer :ignore-auto :noconfirm)))

  :config
  (add-hook 'after-save-hook #'format-clojure))

(use-package cider
  :ensure t

  :bind
  (:map cider-eval-commands-map
    ("C-e" . cider-eval-list-at-point)
    ("C-b" . cider-eval-buffer)
    ("C-f" . cider-eval-defun-at-point))
  (:map cider-test-commands-map
    ("C-c" . cider-test-run-test)
    ("C-n" . cider-test-run-ns-tests)
    ("C-r" . cider-test-show-report))

  :config
  ;; Make C-c C-e / C-c C-t prefixes instead of cider-eval-last-sexp, etc.
  (define-key cider-mode-map (kbd "C-c C-e") cider-eval-commands-map)
  (define-key cider-mode-map (kbd "C-c C-t") cider-test-commands-map)

  (setq cider-save-file-on-load t)
  (setq cider-use-xref nil)
  (setq cider-font-lock-reader-conditionals nil))

(use-package vterm
  :ensure nil
  :commands (vterm vterm-other-window)
  :config
  (add-to-list 'vterm-keymap-exceptions "C-;"))

(use-package emacs
  :ensure nil
  :bind*
  (("M-h" . sz/left-or-tab-previous)
   ("M-j" . windmove-down)
   ("M-k" . windmove-up)
   ("M-l" . sz/right-or-tab-next)
   ("M-n" . tab-new)
   ("M-u" . tab-close))

  :config
  (tab-bar-mode -1)
  (setq tab-bar-close-button-show nil)
  (setq tab-bar-new-tab-choice "*scratch*")
  (setq tab-bar-format '(tab-bar-format-tabs tab-bar-separator)))

(use-package all-the-icons
  :ensure t
  :if (display-graphic-p))

(use-package treesit-auto
  :ensure t

  :custom
  (treesit-auto-install 'prompt)

  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))
