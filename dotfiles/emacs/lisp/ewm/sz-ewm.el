;;; sz-ewm.el --- Minimal EWM session integration -*- lexical-binding: t -*-

(require 'use-package)
(require 'tab-line)

(defgroup sz/ewm nil
  "Personal EWM session integration."
  :group 'environment)

(defcustom sz/ewm-output-selector "eDP-1"
  "Connector or Make-Model-Serial selector for the built-in output.
Use the identity reported by `ewm-list-outputs'."
  :type '(choice (const :tag "Unset" nil) string)
  :group 'sz/ewm)

(defcustom sz/ewm-output-refresh 240
  "Desired refresh rate for `sz/ewm-output-selector', in Hz."
  :type '(choice (const 60) (const 240))
  :group 'sz/ewm)

(defun sz/ewm--output-config (refresh)
  "Return the persistent EWM config for REFRESH, or nil without a selector."
  (when (and (stringp sz/ewm-output-selector)
             (not (string-empty-p sz/ewm-output-selector)))
    `((,sz/ewm-output-selector :width 2560 :height 1600 :refresh ,refresh
                               :x 0 :y 0 :scale 2.0))))

(defun sz/ewm--apply-output-profile ()
  "Record the desired output mode for EWM topology reapplication."
  (when-let ((config (sz/ewm--output-config sz/ewm-output-refresh)))
    (setq-default ewm-output-config config)))

(defun sz/ewm--start (name program &rest args)
  "Start PROGRAM with ARGS under process NAME."
  ;; Avoid SIGHUP to launched apps when a short-lived launcher exits.
  (let ((process-connection-type nil))
    (apply #'start-process name nil program args)))

(defun sz/ewm--start-shell (name command)
  "Start fixed shell COMMAND under process NAME."
  (start-process-shell-command name nil command))

(defun sz/ewm-org-capture ()
  "Select the English XKB layout before opening the capture menu."
  (interactive)
  (ewm-switch-layout-module "us")
  (call-interactively #'org-capture))

(defun sz/ewm-lock ()
  "Lock the current session with the existing swaylock policy."
  (interactive)
  (sz/ewm--start "swaylock" "swaylock" "-c" "000000"))

(defun sz/ewm-logout ()
  "Save modified buffers and confirm before ending the EWM Emacs session."
  (interactive)
  (call-interactively #'save-buffers-kill-emacs))

(defun sz/ewm-power-profile (profile refresh)
  "Apply TLP PROFILE and retain REFRESH across EWM output topology events."
  (interactive)
  (unless (sz/ewm--output-config refresh)
    (user-error "Set sz/ewm-output-selector from ewm-list-outputs first"))
  (setq-default sz/ewm-output-refresh refresh)
  (sz/ewm--apply-output-profile)
  (when (bound-and-true-p ewm--module-mode)
    (ewm--apply-output-config))
  (sz/ewm--start "tlpctl" "tlpctl" profile))

(defun sz/ewm-power-saver ()
  "Select TLP power saver and 60 Hz for the configured EWM output."
  (interactive)
  (sz/ewm-power-profile "power-saver" 60))

(defun sz/ewm-power-balanced ()
  "Select TLP balanced and 240 Hz for the configured EWM output."
  (interactive)
  (sz/ewm-power-profile "balanced" 240))

(defun sz/ewm-launch-enpass ()
  "Launch Enpass through Xwayland, matching the existing session policy."
  (interactive)
  (let ((process-environment (cons "QT_QPA_PLATFORM=xcb" process-environment)))
    (sz/ewm--start "Enpass" "Enpass")))

(defun sz/ewm-screenshot-region-copy ()
  "Copy a selected screenshot to the clipboard."
  (interactive)
  (sz/ewm--start-shell "screenshot-region-copy" "grim -g \"$(slurp)\" - | wl-copy"))

(defun sz/ewm-screenshot-region ()
  "Save a selected screenshot through the inherited GRIM_DEFAULT_DIR policy."
  (interactive)
  (sz/ewm--start-shell "screenshot-region" "grim -g \"$(slurp)\""))

(defun sz/ewm-screenshot-screen-drawing ()
  "Open Drawing with a full-screen screenshot."
  (interactive)
  (sz/ewm--start-shell "screenshot-screen-drawing" "grim - | wl-copy | drawing -c"))

(defun sz/ewm-split-right ()
  "Create and select the next native EWM tile."
  (interactive)
  (select-window (split-window-right)))

(defun sz/ewm--dispatch-in-selected-buffer (function &rest args)
  "Run intercepted FUNCTION with ARGS in the selected window's buffer."
  ;; EWM's async callback can retain a different current buffer after focus moves.
  (with-current-buffer (window-buffer (selected-window))
    ;; These are keyboard commands, not a replay of the last mouse event.
    (let ((last-nonmenu-event nil))
      (apply function args))))

(defun sz/ewm-tab-line-setup ()
  "Enable ordinary Emacs buffer tabs throughout the EWM session."
  (when (bound-and-true-p ewm-mode)
    ;; Emacs 30.2 aborts measuring truncated bidi isolates with boxed faces.
    ;; ponytail: LTR width measurement until the upstream bidi bug is fixed.
    (with-current-buffer tab-line-auto-hscroll-buffer
      (setq-local bidi-display-reordering nil))
    (setq-default tab-line-tabs-function #'tab-line-tabs-fixed-window-buffers
                  tab-line-switch-cycling nil
                  tab-line-close-button-show nil
                  tab-line-new-button-show nil
                  tab-line-tab-name-function #'tab-line-tab-name-truncated-buffer
                  tab-line-tab-name-truncated-max 50)
    (global-tab-line-mode 1)))

(defun sz/ewm-apply-profile ()
  "Send the configured EWM profile without restarting its compositor."
  (interactive)
  (sz/ewm--apply-output-profile)
  (when (bound-and-true-p ewm--module-mode)
    (ewm--send-input-config)
    (ewm--send-intercept-keys)
    (ewm--apply-output-config)))

(use-package ewm
  :ensure nil
  :catch nil
  ;; The Nix session loads EWM after personal init; ordinary Emacs stays deferred.
  :defer t
  :hook (ewm-mode . sz/ewm-tab-line-setup)
  :bind (:map ewm-mode-map
             ("<f13>" . meow-keypad)
             ;; XKB inet maps xremap's KEY_F13 to XF86Tools (PGTK: Tools).
             ("<Tools>" . meow-keypad)
             ("s-y" . (lambda () (interactive) (sz/ewm--start "ghostty" "ghostty" "+new-window")))
             ("s-n" . (lambda () (interactive) (sz/ewm--start "wmenu-run" "wmenu-run" "-i" "-b" "-l" "10" "-f" "Iosevka 14")))
             ("s-b" . (lambda () (interactive) (sz/ewm--start "firefox" "firefox")))
             ("S-s-b" . (lambda () (interactive) (sz/ewm--start "run-work-browser" "run-work-browser")))
             ("s-e" . sz/ewm-launch-enpass)
             ("s-m" . ewm-frame-new)
             ("M-s-," . ewm-frame-new)
             ("M-s-." . ewm-frame-new)
             ("s-w" . ewm-frame-close)
             ("s-;" . sz/ewm-org-capture)
             ("s-<escape>" . sz/ewm-lock)
             ("S-s-e" . sz/ewm-logout)
             ("s-<f8>" . sz/ewm-power-saver)
             ("S-s-<f8>" . sz/ewm-power-balanced)
             ("s-," . ewm-frame-right)
             ("s-." . ewm-frame-left)
             ("s-h" . ewm-focus-left)
             ("s-l" . ewm-focus-right)
             ("M-s-l" . sz/ewm-split-right)
             ("s-k" . tab-line-switch-to-prev-tab)
             ("s-j" . tab-line-switch-to-next-tab)
             ("s-<tab>" . tab-line-switch-to-next-tab)
             ("S-s-<tab>" . tab-line-switch-to-prev-tab)
             ("s-<iso-lefttab>" . tab-line-switch-to-prev-tab)
             ("s-f" . ewm-toggle-fullscreen)
             ("s-u" . kill-current-buffer)
             ("C-S-s-r" . sz/ewm-apply-profile)
             ("<Print>" . sz/ewm-screenshot-region-copy)
             ("C-<Print>" . sz/ewm-screenshot-region)
             ("S-<Print>" . sz/ewm-screenshot-screen-drawing)
             ("<MonBrightnessUp>" . (lambda () (interactive) (sz/ewm--start-shell "brightness-up" "increase-backlight && display-backlight")))
             ("<MonBrightnessDown>" . (lambda () (interactive) (sz/ewm--start-shell "brightness-down" "decrease-backlight && display-backlight")))
             ("<AudioPlay>" . (lambda () (interactive) (sz/ewm--start "playerctl" "playerctl" "play-pause")))
             ("<AudioRaiseVolume>" . (lambda () (interactive) (sz/ewm--start-shell "volume-up" "increase-current-volume && display-current-volume")))
             ("<AudioLowerVolume>" . (lambda () (interactive) (sz/ewm--start-shell "volume-down" "decrease-current-volume && display-current-volume")))
             ("<AudioMicMute>" . (lambda () (interactive) (sz/ewm--start-shell "microphone-mute" "toggle-microphone-mute && display-current-microphone")))
             ("<HomePage>" . (lambda () (interactive) (sz/ewm--start-shell "microphone-mute" "toggle-microphone-mute && display-current-microphone")))
             ("<AudioMute>" . (lambda () (interactive) (sz/ewm--start-shell "audio-mute" "toggle-audio-mute && display-current-volume")))
             ("S-s-m" . (lambda () (interactive) (sz/ewm--start-shell "audio-mute" "toggle-audio-mute && display-current-volume"))))
  :config
  ;; Floating frames must not inherit default-frame-alist's maximized state.
  (setf (alist-get 'fullscreen pop-up-frame-alist) nil)
  (advice-add 'ewm--handle-intercepted-command :around
              #'sz/ewm--dispatch-in-selected-buffer)
  (setq-default
   ;; Keep the River-like static, opaque desktop and persistent pointer.
   ewm-animations-enabled nil
   ewm-unfocused-alpha 1.0
   ewm-cursor-auto-hide nil
   ewm-cursor-hide-when-typing nil
   ewm-input-config
   '((keyboard :xkb-layouts "us,ru"
               :xkb-options "grp:ctrl_space_toggle,custom:types,custom:positional-latin-shortcuts")
     (touchpad :tap t :tap-button-map "left-right-middle"
               :natural-scroll t :dwt t :middle-emulation t))
   ewm-intercept-prefixes '("M-:" "M-x")
   ;; Do not turn Super-c/v into Ctrl-c/v: terminal Ctrl-c is SIGINT, not copy.
   ewm-surface-emulate-keys nil
   confirm-kill-emacs #'yes-or-no-p)
  (use-package sz-ewm-status
    :ensure nil
    :catch nil
    :demand t
    :hook ((ewm-mode . sz/ewm-status-start)
           (kill-emacs . sz/ewm-status-stop))
    :config
    (sz/ewm-status-install-event-advice)))

;; Run after :bind has populated the keymap, including when EWM is already loaded.
(with-eval-after-load 'ewm
  ;; Keep active EWM bindings available even when a client is fullscreen.
  (map-keymap
   (lambda (key binding)
     (when (ewm--live-binding-p binding)
       (add-to-list 'ewm-intercept-prefixes
                    (list (key-description (vector key)) :fullscreen))))
   ewm-mode-map)
  (sz/ewm-apply-profile))

(provide 'sz-ewm)
;;; sz-ewm.el ends here
