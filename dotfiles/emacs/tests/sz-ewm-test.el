;;; sz-ewm-test.el --- ERT checks for the local EWM profile -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'tab-bar)
(require 'consult)

(defconst sz/ewm-test-emacs-directory
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name))))
(defconst sz/ewm-test-upstream-directory
  (or (getenv "EWM_TEST_SOURCE")
      (error "Set EWM_TEST_SOURCE to the pinned EWM lisp directory")))

(add-to-list 'load-path sz/ewm-test-upstream-directory)
(add-to-list 'load-path (expand-file-name "lisp/ewm" sz/ewm-test-emacs-directory))

;; Mocks only the native module boundary; all tested policy and event code is
;; loaded from the pinned upstream Lisp source selected by EWM_TEST_SOURCE.
(dolist (stub '((ewm-intercept-keys-module (&rest _))
                (ewm-configure-input-module (&rest _))
                (ewm-configure-output-module (&rest _))
                (ewm-keyboard-capture-begin-module (&rest _) 1)
                (ewm-keyboard-capture-end-module (&rest _) t)
                (ewm-keyboard-redirect-capture-clear-module (&rest _))
                (ewm-set-drag-source (&rest _))
                (ewm-get-focused-id (&rest _))
                (ewm-get-focused-frame-id (&rest _))
                (ewm-get-pointer-location (&rest _) '(0 . 0))
                (ewm-output-layout-module (&rest _))
                (ewm-floating-layout-module (&rest _))
                (ewm-close-module (&rest _))
                (ewm-warp-pointer-module (&rest _))
                (ewm-get-debug-state-module (&rest _))
                (ewm-debug-mode-module (&rest _))
                (ewm-prepare-frame-module (&rest _))
                (ewm-prepare-floating-frame-module (&rest _))
                (ewm-prepare-frame-close-module (&rest _))
                (ewm-move-floating-frame-module (&rest _))
                (ewm-resize-floating-frame-module (&rest _))
                (ewm-workspace-rename-module (&rest _))
                (ewm-workspace-mark-urgent-module (&rest _))
                (ewm-toggle-fullscreen-module (&rest _))
                (ewm-get-active-outputs (&rest _))
                (ewm-get-output-origin (&rest _) '(0 . 0))
                (ewm-get-frame-origin (&rest _) '(0 . 0))
                (ewm-entry-under-floating-center-module (&rest _))
                (ewm-configure-cursor-module (&rest _))
                (ewm-configure-cursor-hide-module (&rest _))
                (ewm-start (&rest _) t)
                (ewm-list-xdg-apps (&rest _))
                (ewm-set-focus-follows-mouse (&rest _))
                (ewm-set-unfocused-alpha (&rest _))
                (ewm-set-animations-enabled (&rest _))
                (ewm-notify-initialized-module (&rest _))
                (ewm-focus-output-direction-module (&rest _))
                (ewm-init-event-channel (&rest _))
                (ewm-set-selection-module (&rest _))
                (ewm-gtk-set-style (&rest _))
                (ewm-im-commit-module (&rest _))
                (ewm-text-input-intercept-module (&rest _))))
  (unless (fboundp (car stub))
    (eval `(defun ,(car stub) ,(cadr stub) ,@(cddr stub)))))
(provide 'ewm-core)

(require 'ewm)
(load (expand-file-name "lisp/ewm/sz-ewm.el" sz/ewm-test-emacs-directory) nil 'nomessage t)
(load (expand-file-name "lisp/functions/sz-org-capture-frame.el" sz/ewm-test-emacs-directory)
      nil 'nomessage t)

;; Load the actual tab configuration and navigation without unrelated packages.
;; vtab must already be on load-path; tests never install packages.
(with-temp-buffer
  (insert-file-contents (expand-file-name "lisp/sz-base.el" sz/ewm-test-emacs-directory))
  (goto-char (point-min))
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (or (and (eq (car-safe form) 'use-package) (eq (cadr form) 'vtab))
                    (and (eq (car-safe form) 'defun)
                         (memq (cadr form) '(sz/move-or-switch-tab
                                            sz/left-or-tab-previous
                                            sz/right-or-tab-next))))
            (cl-letf (((symbol-function 'use-package-vc-install) #'ignore))
              (eval form t)))))
    (end-of-file nil)))
(vtab-mode -1)

(defmacro sz/ewm-test-with-tabs (&rest body)
  "Run BODY with real vtab windows and an isolated set of tabs."
  (declare (indent 0) (debug t))
  `(let ((saved-tabs (frame-parameter nil 'tabs))
         (ewm--module-mode nil))
     (unwind-protect
         (save-window-excursion
           (set-frame-parameter nil 'tabs nil)
           (delete-other-windows)
           (vtab-mode 1)
           ,@body)
       (vtab-mode -1)
       (set-frame-parameter nil 'tabs saved-tabs))))

(ert-deftest sz/ewm-profile-keeps-editor-prefixes-out-of-external-apps ()
  (let ((ewm--module-mode nil)
        (sz/ewm-output-selector nil)
        sent)
    (sz/ewm-apply-profile)
    (should (eq (lookup-key ewm-mode-map (kbd "M-s-l")) #'sz/ewm-split-right))
    (should (eq (lookup-key ewm-mode-map (kbd "s-j")) #'tab-next))
    (should (eq (lookup-key ewm-mode-map (kbd "s-k")) #'tab-previous))
    (should (eq (lookup-key ewm-mode-map (kbd "s-n")) #'tab-new))
    (should (eq (lookup-key ewm-mode-map (kbd "s-'")) #'bury-buffer))
    (should (eq (lookup-key ewm-mode-map (kbd "s-u")) #'tab-close))
    (should (eq (lookup-key ewm-mode-map (kbd "M-s-u")) #'kill-current-buffer))
    (should (eq (lookup-key ewm-mode-map (kbd "s-i")) #'sz/ewm-consult-app))
    (should (eq (lookup-key ewm-mode-map (kbd "M-s-i")) #'sz/ewm-consult-app-new-tab))
    (should (eq (lookup-key ewm-mode-map (kbd "s-;")) #'org-capture))
    (should (eq (lookup-key global-map (kbd "M-:")) #'eval-expression))
    (should (eq (lookup-key ewm-mode-map (kbd "S-s-e")) #'sz/ewm-logout))
    (should-not ewm-surface-emulate-keys)
    (should (eq confirm-kill-emacs #'yes-or-no-p))
    (cl-letf (((symbol-function 'ewm-intercept-keys-module)
               (lambda (specs) (setq sent specs))))
      (ewm--send-intercept-keys))
    (dolist (key '("s-t" "M-s-," "M-s-." "s-w" "s-," "s-."
                   "S-s-<left>" "S-s-<right>" "C-s-<left>" "C-s-<right>"
                   "s-1" "s-2" "s-3" "s-4" "s-5" "s-6" "s-7" "s-8" "s-9"))
      (should-not (lookup-key ewm-mode-map (kbd key)))
      (should-not (seq-find (lambda (spec)
                             (equal (plist-get spec :description)
                                    (key-description (kbd key))))
                           sent)))
    (should (seq-find (lambda (spec)
                       (equal (plist-get spec :description) "M-:"))
                     sent))
    (should (seq-find (lambda (spec)
                       (equal (plist-get spec :description) "M-x"))
                     sent))
    (dolist (description '("C-x" "C-u" "C-h"))
      (should-not (seq-find (lambda (spec)
                              (equal (plist-get spec :description) description))
                            sent)))
    (dolist (description '("s-f" "s-u" "M-s-u" "s-<escape>" "S-s-e" "s-<f8>" "S-s-<f8>" "s-;"
                           "s-i" "M-s-i" "s-m" "s-n" "s-'" "s-j" "s-k"
                           "s-<tab>" "S-s-<tab>" "s-<iso-lefttab>"
                           "<Print>" "C-<Print>" "S-<Print>"
                           "<MonBrightnessUp>" "<MonBrightnessDown>"
                           "<AudioPlay>" "<AudioRaiseVolume>"
                           "<AudioLowerVolume>" "<AudioMicMute>"
                           "<HomePage>" "<AudioMute>" "S-s-m"))
      (let ((spec (seq-find (lambda (candidate)
                              (equal (plist-get candidate :description) description))
                            sent)))
        (should spec)
        (should (eq (plist-get spec :fullscreen) t))))
    (dolist (spec (append sent nil))
      (should-not (plist-member spec :translate))
      (ert-info ((plist-get spec :description))
        (if (member (plist-get spec :description) '("M-:" "M-x"))
            (should (eq (plist-get spec :fullscreen) :false))
          (should (eq (plist-get spec :fullscreen) t)))))))

(ert-deftest sz/ewm-super-tap-tools-event-opens-keypad ()
  ;; evdev's KEY_F13 becomes XF86Tools under the standard XKB inet mapping;
  ;; PGTK exposes that keysym to Emacs as Tools.
  (let (sent called)
    (should (eq (lookup-key ewm-mode-map [Tools]) #'meow-keypad))
    (cl-letf (((symbol-function 'ewm-intercept-keys-module)
               (lambda (specs) (setq sent specs)))
              ((symbol-function 'meow-keypad)
               (lambda () (interactive) (setq called t))))
      (ewm--send-intercept-keys)
      (let ((spec (seq-find (lambda (entry)
                             (equal (plist-get entry :description) "<Tools>"))
                           sent)))
        (should spec)
        (should (eq (plist-get spec :fullscreen) t))
        (should (equal (plist-get spec :dispatch) "command")))
      (should (equal (lookup-key function-key-map [XF86Tools]) [Tools]))
      (ewm--handle-intercepted-command '((key . "<Tools>")))
      (should called))))

(ert-deftest sz/ewm-intercepted-commands-use-the-selected-window-buffer ()
  ;; Live failure: the event callback's current buffer stays on Telegram
  ;; while the selected window shows Ghostty or Firefox.
  (let* ((ewm--module-mode nil)
         (ewm--surfaces (make-hash-table :test #'eql))
         (buffers (mapcar #'generate-new-buffer
                          '("*ewm-test-ghostty*" "*ewm-test-telegram*"
                            "*ewm-test-firefox*")))
         visited)
    (unwind-protect
        (sz/ewm-test-with-tabs
          (cl-loop for buffer in buffers for id from 3 do
                   (with-current-buffer buffer
                     (ewm-surface-mode)
                     (setq-local ewm-surface-id id)
                     (puthash id buffer ewm--surfaces)))
          (switch-to-buffer (car buffers))
          (dolist (buffer (cdr buffers))
            (ewm--handle-event '((event . "intercepted-command") (key . "s-n")))
            (should (eq (window-buffer) (get-buffer "*scratch*")))
            (switch-to-buffer buffer))
          (tab-bar-select-tab 1)
          ;; Native tab navigation wraps at both ends.
          ;; A previous click in another window must not redirect keyboard commands.
          (let ((last-nonmenu-event
                 (list 'mouse-1 (list (split-window-right) 'tab-line '(0 . 0) 0))))
            (dolist (key '("s-k" "s-j" "s-j" "s-j" "s-j"
                           "s-k" "s-k" "s-k" "s-k"))
              (with-current-buffer (nth 1 buffers)
                (ewm--handle-event `((event . "intercepted-command") (key . ,key))))
              (push (buffer-local-value 'ewm-surface-id (window-buffer)) visited)))
          (should (equal (nreverse visited) '(5 3 4 5 3 5 4 3 5)))
          (tab-bar-select-tab 1)
          ;; Hiding an app keeps its workspace; closing a workspace keeps apps.
          (let ((ewm--module-mode t)
                closed)
            (cl-letf (((symbol-function 'ewm-close)
                       (lambda (id) (push id closed))))
              (with-current-buffer (nth 1 buffers)
                (ewm--handle-event '((event . "intercepted-command") (key . "s-'"))))
              (should-not closed)
              (should (buffer-live-p (car buffers)))
              (should (memq (car buffers) (buffer-list)))
              (should-not (eq (window-buffer) (car buffers)))
              (should (= 3 (length (tab-bar-tabs))))
              (switch-to-buffer (car buffers))
              (ewm--handle-event '((event . "intercepted-command") (key . "s-u")))
              (should (= 2 (length (tab-bar-tabs))))
              (should-not closed)
              (should (buffer-live-p (car buffers)))
              (switch-to-buffer (car buffers))
              (with-current-buffer (nth 1 buffers)
                (ewm--handle-event '((event . "intercepted-command") (key . "M-s-u"))))
              (should (equal closed '(3)))
              ;; EWM waits for the application's close event before killing.
              (should (buffer-live-p (car buffers)))))
          (ewm--handle-close-surface '((id . 3)))
          (should-not (buffer-live-p (car buffers)))
          (should (buffer-live-p (nth 1 buffers)))
          (tab-close-other)
          (should-error
           (ewm--handle-event '((event . "intercepted-command") (key . "s-u")))
           :type 'user-error)
          (should (= 1 (length (tab-bar-tabs))))
          (should (frame-live-p (selected-frame))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer) (kill-buffer buffer)))
            buffers))))

(ert-deftest sz/ewm-app-picker-preserves-layout-or-creates-a-new-tab ()
  (let* ((ewm--module-mode nil)
         (editor (generate-new-buffer "ewm-picker-notes.org"))
         (apps (mapcar #'generate-new-buffer
                       '("ewm-picker-first" "ewm-picker-second"
                         "ewm-picker-third" "ewm-picker-fourth")))
         choice
         (completing-read-function
          (lambda (_prompt collection predicate require-match &rest _)
            (should require-match)
            (should (equal (sort (all-completions "" collection predicate) #'string<)
                           (sort (mapcar #'buffer-name apps) #'string<)))
            (if (eq choice 'cancel) (signal 'quit nil) (buffer-name choice)))))
    (unwind-protect
        (sz/ewm-test-with-tabs
          (cl-loop for app in apps for id from 101 do
                   (with-current-buffer app
                     (ewm-surface-mode)
                     (setq-local ewm-surface-id id)))
          (switch-to-buffer editor)
          (let ((other (split-window-below)))
            (set-window-buffer other (car apps))
            (setq choice (nth 1 apps))
            (with-current-buffer (nth 2 apps)
              (ewm--handle-event '((event . "intercepted-command") (key . "s-i"))))
            (should (eq (window-buffer) choice))
            (should (eq (window-buffer other) (car apps)))
            (should (= 1 (length (tab-bar-tabs))))
            (let ((layout (window-state-get nil t)))
              ;; Even the current app gets a fresh tab on each confirmation.
              (dotimes (index 2)
                (ewm--handle-event '((event . "intercepted-command") (key . "M-s-i")))
                (should (eq (window-buffer) choice))
                (should (= (+ 2 index) (length (tab-bar-tabs)))))
              (tab-bar-select-tab 1)
              (should (equal layout (window-state-get nil t)))))
          ;; Cancelling either picker leaves the selected buffer and tabs alone.
          (setq choice 'cancel)
          (dolist (key '("s-i" "M-s-i"))
            (should (eq (condition-case nil
                            (ewm--handle-event `((event . "intercepted-command") (key . ,key)))
                          (quit 'cancelled))
                        'cancelled))
            (should (eq (window-buffer) (nth 1 apps)))
            (should (= 3 (length (tab-bar-tabs)))))
          (dolist (buffer (cons editor apps))
            (should (buffer-live-p buffer))))
      (mapc #'kill-buffer (cons editor apps)))))

(ert-deftest sz/ewm-app-preview-restores-layout-before-accept-or-cancel ()
  (let* ((ewm--module-mode nil)
         (editor (generate-new-buffer "ewm-preview-notes.org"))
         (apps (mapcar #'generate-new-buffer
                       '("ewm-preview-first" "ewm-preview-second" "ewm-preview-third"))))
    (unwind-protect
        (sz/ewm-test-with-tabs
          (cl-loop for app in apps for id from 201 do
                   (with-current-buffer app
                     (ewm-surface-mode)
                     (setq-local ewm-surface-id id)))
          (dolist (key '("s-i" "M-s-i"))
            (dolist (cancel '(nil t))
              (tab-close-other)
              (switch-to-buffer editor)
              ;; Exercise the real Consult preview state at the reader boundary.
              (cl-letf (((symbol-function 'consult--read)
                         (lambda (_table &rest options)
                           (let ((state (plist-get options :state)))
                             (should (functionp state))
                             (funcall state 'setup nil)
                             (unwind-protect
                                 (progn
                                   (dolist (app (reverse apps))
                                     (funcall state 'preview (buffer-name app))
                                     (should (eq (window-buffer) app))
                                     (vtab--refresh)
                                     (should (= 1 (length (tab-bar-tabs)))))
                                   (if cancel (signal 'quit nil)
                                     (buffer-name (nth 1 apps))))
                               (funcall state 'preview nil)
                               (funcall state 'exit nil)
                               (funcall state 'return
                                        (unless cancel (buffer-name (nth 1 apps))))
                               (should (eq (window-buffer) editor)))))))
                (condition-case nil
                    (ewm--handle-event `((event . "intercepted-command") (key . ,key)))
                  (quit (should cancel))))
              (should (eq (window-buffer) (if cancel editor (nth 1 apps))))
              (should (= (length (tab-bar-tabs))
                         (if (and (not cancel) (equal key "M-s-i")) 2 1)))
              (when (and (not cancel) (equal key "M-s-i"))
                (tab-previous)
                (should (eq (window-buffer) editor))))))
      (dolist (buffer (cons editor apps))
        (should (buffer-live-p buffer))
        (kill-buffer buffer)))))

(ert-deftest sz/ewm-launcher-key-opens-wmenu ()
  (let (started)
    (cl-letf (((symbol-function 'sz/ewm--start)
               (lambda (&rest args) (setq started args))))
      (ewm--handle-event '((event . "intercepted-command") (key . "s-m")))
      (should (equal started '("wmenu-run" "wmenu-run" "-i" "-b" "-l" "10"
                              "-f" "Iosevka 14"))))))

(ert-deftest sz/ewm-vtab-layout-includes-sidebar-and-selected-surface ()
  (let ((ewm--surfaces (make-hash-table :test #'eql)))
    (unwind-protect
        (sz/ewm-test-with-tabs
          (should-not global-tab-line-mode)
          (should-not (lookup-key vtab-mode-map (kbd "M-s")))
          (ewm--create-surface-buffer 7 "tab-test" 0)
          (cl-letf (((symbol-function 'ewm--surface-target-frame-for-output)
                     (lambda (_) (selected-frame))))
            (ewm--place-surface-buffer (gethash 7 ewm--surfaces) nil nil nil))
          (should (= 1 (length (tab-bar-tabs))))
          (vtab--refresh)
          (let* ((sidebar (get-buffer-window (frame-parameter nil 'vtab--buffer)))
                 (layout (ewm-layout--build-frame-plist (selected-frame) nil))
                 (entries (plist-get layout :entries))
                 (app (seq-find (lambda (entry) (eq (plist-get entry :surface-id) 7))
                                entries)))
            (should sidebar)
            (should (eq (window-parameter sidebar 'window-side) 'left))
            (should (= 2 (length entries)))
            (should app)
            (should (equal (plist-get layout :selected-entry-id)
                           (plist-get app :entry-id)))
            (should (> (plist-get app :x) 0))
            (should (> (plist-get app :w) 0))))
      (maphash (lambda (_ buffer) (kill-buffer buffer)) ewm--surfaces))))

(ert-deftest sz/ewm-vtab-native-redisplay ()
  ;; Long EWM names with bidi isolates previously crashed tab-line redisplay.
  (skip-unless (display-graphic-p))
  (let ((buffer (generate-new-buffer
                 (concat "*ewm:test\u2068" (make-string 80 ?x) "\u2069*"))))
    (unwind-protect
        (sz/ewm-test-with-tabs
          (switch-to-buffer buffer)
          (vtab--refresh)
          (redisplay t)
          (tab-new)
          (redisplay t)
          (tab-previous)
          (redisplay t)
          (should (eq (window-buffer) buffer))
          (should (get-buffer-window (frame-parameter nil 'vtab--buffer)))
          (should bidi-display-reordering))
      (kill-buffer buffer))))

(ert-deftest sz/ewm-directional-navigation-wraps-after-window-edge ()
  (sz/ewm-test-with-tabs
    (tab-new)
    (let ((other (split-window-below)))
      (sz/move-or-switch-tab 'below)
      (should (eq (selected-window) other))
      (should (= 2 (length (tab-bar-tabs))))
      (sz/right-or-tab-next)
      (should (eq (car (car (tab-bar-tabs))) 'current-tab))
      ;; The vtab sidebar is a real left-hand window; exercise the tab edge
      ;; with a direction that has no adjacent window.
      (sz/move-or-switch-tab 'above)
      (should (eq (car (car (last (tab-bar-tabs)))) 'current-tab)))))

(ert-deftest sz/ewm-refresh-survives-upstream-output-reapply ()
  (let ((sz/ewm-output-selector "Live output selector")
        (sz/ewm-output-refresh 240)
        (ewm--module-mode t)
        applied)
    (cl-letf (((symbol-function 'start-process) (lambda (&rest _) nil))
              ((symbol-function 'ewm-configure-output-module)
               (lambda (&rest args) (push args applied))))
      (sz/ewm-power-saver)
      (should (= sz/ewm-output-refresh 60))
      (should (equal (plist-get (cdr (car ewm-output-config)) :refresh) 60))
      (setq applied nil)
      ;; Actual upstream topology completion calls `ewm--apply-output-config'.
      (ewm--handle-outputs-complete)
      (should applied))))

(ert-deftest sz/ewm-capture-uses-org-directly-while-ewm-runs ()
  (let (captured)
    (cl-letf (((symbol-function 'ewm-running) (lambda () t))
              ((symbol-function 'org-capture) (lambda () (setq captured t))))
      (sz/org-capture-in-frame)
      (should captured))))

(ert-deftest sz/ewm-logout-delegates-to-emacs-save-confirmation ()
  (let (called)
    (cl-letf (((symbol-function 'call-interactively)
               (lambda (command &rest _) (setq called command))))
      (sz/ewm-logout)
      (should (eq called #'save-buffers-kill-emacs)))))

(ert-deftest sz/ewm-split-selects-the-new-native-tile ()
  (let ((new-window 'new-window)
        selected)
    (cl-letf (((symbol-function 'split-window-right) (lambda () new-window))
              ((symbol-function 'select-window) (lambda (window) (setq selected window))))
      (sz/ewm-split-right)
      (should (eq selected new-window)))))

(ert-deftest sz/ewm-screenshots-keep-the-existing-grim-default-directory ()
  (let ((process-environment (cons "GRIM_DEFAULT_DIR=/tmp/Pictures/Screenshots"
                                   process-environment))
        command inherited-directory)
    (cl-letf (((symbol-function 'start-process-shell-command)
               (lambda (_name _buffer shell-command)
                 (setq command shell-command
                       inherited-directory (getenv "GRIM_DEFAULT_DIR")))))
      (sz/ewm-screenshot-region)
      (should (equal command "grim -g \"$(slurp)\""))
      (should (equal inherited-directory "/tmp/Pictures/Screenshots")))))

;;; sz-ewm-test.el ends here
