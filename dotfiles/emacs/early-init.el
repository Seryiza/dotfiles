(setq package-enable-at-startup nil)

(load (expand-file-name "lisp/sz-state.el" user-emacs-directory) nil 'nomessage t)

;; Startup speed, annoyance suppression
(defvar sz/gc-cons-threshold-default 800000)
(defvar sz/gc-cons-percentage-default 0.1)
(setq gc-cons-threshold (* 128 1024 1024))
(setq gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold sz/gc-cons-threshold-default)
            (setq gc-cons-percentage sz/gc-cons-percentage-default)))

(setq package-quickstart t)

(setq byte-compile-warnings '(not obsolete))
(setq warning-suppress-log-types '((comp) (bytecomp)))
(setq native-comp-async-report-warnings-errors 'silent)

;; Silence stupid startup message
(setq inhibit-startup-echo-area-message (user-login-name))

(when (boundp 'pgtk-wait-for-event-timeout)
  (setq pgtk-wait-for-event-timeout 0.001))
