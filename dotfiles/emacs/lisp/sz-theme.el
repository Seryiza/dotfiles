(custom-set-variables
 '(custom-safe-themes
   '("a75fc55d480accd6f651d1bae492b7ab4c5b28894350b63ef39bf947bb8fd453"
     default)))

(custom-set-faces
 '(howm-mode-title-face ((t (:inherit unspecified :foreground unspecified :background unspecified))))
 '(tab-bar ((t (:height 1.0))))
 '(tab-bar-tab ((t (:box (:line-width (6 . 2) :color "#ffffff" :style nil)))))
 '(tab-bar-tab-inactive ((t (:box (:line-width (6 . 2) :color "#c2c2c2" :style nil))))))

(use-package modus-themes
  :ensure t
  :pin gnu

  :preface
  (defun sz/modus-theme-p (theme)
    (string-prefix-p "modus-" (symbol-name theme)))

  (defun sz/modus-clear-howm-title-face (&rest _)
    (custom-set-faces
     '(howm-mode-title-face ((t (:inherit unspecified
                                 :foreground unspecified
                                 :background unspecified))))))

  (defun sz/modus-configure-tab-bar (theme)
    (when (sz/modus-theme-p theme)
      (let ((tab-bg (modus-themes-get-color-value 'bg-tab-current :overrides))
            (tab-inactive-bg (modus-themes-get-color-value 'bg-tab-other :overrides)))
        (custom-set-faces
         '(tab-bar ((t (:height 0.8))))
         `(tab-bar-tab ((t (:box (:line-width (8 . 2) :color ,tab-bg :style nil)))))
         `(tab-bar-tab-inactive ((t (:box (:line-width (8 . 2) :color ,tab-inactive-bg :style nil)))))
         '(vtab-active-face ((t (:background "black" :foreground "white"))))))))

  :init
  (add-hook 'enable-theme-functions #'sz/modus-clear-howm-title-face)
  (add-hook 'enable-theme-functions #'sz/modus-configure-tab-bar)

  :hook
  (after-make-frame-functions . (lambda (frame)
                                  (when (daemonp)
                                    (with-selected-frame frame
                                      (enable-theme 'modus-operandi-deuteranopia)))))

  :config
  (setq shr-use-fonts nil)
  (load-theme 'modus-operandi-deuteranopia :no-confirm))
