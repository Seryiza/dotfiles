;;; sz-ewm.el --- Minimal EWM session integration -*- lexical-binding: t -*-

(defgroup sz/ewm nil
  "Personal EWM session integration."
  :group 'environment)

(defcustom sz/ewm-output-selector nil
  "Connector or Make-Model-Serial selector for the built-in output.
Set this from `ewm-list-outputs' after the first live EWM session; it is
intentionally nil until the actual output identity is known."
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
  (apply #'start-process name nil program args))

(defun sz/ewm--start-shell (name command)
  "Start fixed shell COMMAND under process NAME."
  (start-process-shell-command name nil command))

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

(defun sz/ewm--install-keymap ()
  "Install the accepted native EWM and hardware bindings."
  (dolist (binding
           '(("s-y" . (lambda () (interactive) (sz/ewm--start "ghostty" "ghostty" "+new-window")))
             ("s-n" . (lambda () (interactive) (sz/ewm--start "wmenu-run" "wmenu-run" "-i" "-b" "-l" "10" "-f" "Iosevka 14")))
             ("s-b" . (lambda () (interactive) (sz/ewm--start "firefox" "firefox")))
             ("S-s-b" . (lambda () (interactive) (sz/ewm--start "run-work-browser" "run-work-browser")))
             ("s-e" . sz/ewm-launch-enpass)
             ("s-m" . ewm-frame-new)
             ("M-s-," . ewm-frame-new)
             ("M-s-." . ewm-frame-new)
             ("s-w" . ewm-frame-close)
             ("s-;" . org-capture)
             ("s-<escape>" . sz/ewm-lock)
             ("S-s-e" . sz/ewm-logout)
             ("s-<f8>" . sz/ewm-power-saver)
             ("S-s-<f8>" . sz/ewm-power-balanced)
             ("s-," . ewm-frame-right)
             ("s-." . ewm-frame-left)
             ("s-h" . ewm-focus-left)
             ("s-l" . ewm-focus-right)
             ("M-s-l" . sz/ewm-split-right)
             ("s-k" . ewm-next-surface-buffer)
             ("s-j" . ewm-prev-surface-buffer)
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
             ("S-s-m" . (lambda () (interactive) (sz/ewm--start-shell "audio-mute" "toggle-audio-mute && display-current-volume")))))
    (keymap-set ewm-mode-map (car binding) (cdr binding))))

(defun sz/ewm-apply-profile ()
  "Reapply this EWM profile without restarting its compositor."
  (interactive)
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
   ewm-intercept-prefixes
   '(("s-<escape>" :fullscreen) ("S-s-e" :fullscreen)
     ("s-<f8>" :fullscreen) ("S-s-<f8>" :fullscreen)
     ("s-;" :fullscreen)
     ("<Print>" :fullscreen) ("C-<Print>" :fullscreen) ("S-<Print>" :fullscreen)
     ("<MonBrightnessUp>" :fullscreen) ("<MonBrightnessDown>" :fullscreen)
     ("<AudioPlay>" :fullscreen) ("<AudioRaiseVolume>" :fullscreen)
     ("<AudioLowerVolume>" :fullscreen) ("<AudioMicMute>" :fullscreen)
     ("<HomePage>" :fullscreen) ("<AudioMute>" :fullscreen)
     ("S-s-m" :fullscreen))
   ;; Do not turn Super-c/v into Ctrl-c/v: terminal Ctrl-c is SIGINT, not copy.
   ewm-surface-emulate-keys nil
   confirm-kill-emacs #'yes-or-no-p)
  (sz/ewm--apply-output-profile)
  (sz/ewm--install-keymap)
  (when (bound-and-true-p ewm--module-mode)
    (ewm--send-input-config)
    (ewm--send-intercept-keys)
    (ewm--apply-output-config)))

(with-eval-after-load 'ewm
  (require 'sz-ewm-status)
  (sz/ewm-status-install-event-advice)
  (add-hook 'ewm-mode-hook #'sz/ewm-status-start)
  (add-hook 'kill-emacs-hook #'sz/ewm-status-stop)
  (sz/ewm-apply-profile))

(provide 'sz-ewm)
;;; sz-ewm.el ends here
