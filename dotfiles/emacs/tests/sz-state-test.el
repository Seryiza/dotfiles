(require 'ert)
(require 'cl-lib)

(defconst sz/state-test-emacs-directory
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name))))
(defconst sz/state-test-file
  (expand-file-name "lisp/sz-state.el" sz/state-test-emacs-directory))
(defconst sz/state-test-base-file
  (expand-file-name "lisp/sz-base.el" sz/state-test-emacs-directory))
(defconst sz/state-test-org-file
  (expand-file-name "lisp/sz-org.el" sz/state-test-emacs-directory))

(defmacro sz/state-test-with-sandbox (&rest body)
  `(let* ((home (make-temp-file "sz-state-home" t))
          (process-environment (copy-sequence process-environment))
          (user-emacs-directory sz/state-test-emacs-directory)
          (native-comp-eln-load-path
           '("/old-user-eln/" "/nix/store/native-lisp/" "/system/native-lisp/")))
     (setenv "HOME" home)
     (unwind-protect
         (progn ,@body)
       (delete-directory home t))))

(defmacro sz/state-test-with-environment (data state cache &rest body)
  `(sz/state-test-with-sandbox
    (setenv "XDG_DATA_HOME" ,data)
    (setenv "XDG_STATE_HOME" ,state)
    (setenv "XDG_CACHE_HOME" ,cache)
    (load sz/state-test-file nil 'nomessage t)
    ,@body))

(defun sz/state-test--eval-file (file)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (eval (read (current-buffer)) t))
      (end-of-file nil))))

(defun sz/state-test--read-forms (file)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file (nreverse forms))))))

(defun sz/state-test--use-package-form (file package &optional keyword)
  "Return PACKAGE's declaration from FILE, optionally requiring KEYWORD."
  (or (seq-find
       (lambda (candidate)
         (and (eq (car-safe candidate) 'use-package)
              (eq (cadr candidate) package)
              (or (null keyword) (memq keyword candidate))))
       (sz/state-test--read-forms file))
      (error "No use-package declaration for %s in %s" package file)))

(defun sz/state-test--use-package-section (file package keyword)
  "Return PACKAGE's top-level KEYWORD forms as written in FILE."
  (let* ((form (sz/state-test--use-package-form file package keyword))
         (tail (cdr (memq keyword form)))
         section)
    (while (and tail (not (keywordp (car tail))))
      (push (pop tail) section))
    (nreverse section)))

(defun sz/state-test--eval-use-package-section (file package keyword)
  "Evaluate PACKAGE's actual KEYWORD forms from FILE without expanding use-package."
  (dolist (form (sz/state-test--use-package-section file package keyword))
    (eval form)))

(defun sz/state-test--eval-init-with-boundaries ()
  (let ((events nil)
        (package-archives nil)
        (package-hidden-regexps nil)
        (load-path (copy-sequence load-path))
        (real-load (symbol-function 'load)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest _)
                 (push (list :require feature) events)))
              ((symbol-function 'package-initialize)
               (lambda () (push '(:package-initialize) events)))
              ((symbol-function 'load)
               (lambda (file &optional noerror nomessage nosuffix &rest _)
                 (push (list :load file noerror nomessage nosuffix) events)
                 (when (equal file custom-file)
                   (funcall real-load file noerror nomessage nosuffix)))))
      (sz/state-test--eval-file
       (expand-file-name "init.el" sz/state-test-emacs-directory)))
    (nreverse events)))

(ert-deftest sz/state-use-package-errors-stop-before-consumers ()
  (require 'use-package)
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (let* ((savehist-path (expand-file-name "history" sz/state-directory))
          (outside (expand-file-name "outside" home))
          (savehist-form
           (macroexpand
            (sz/state-test--use-package-form sz/state-test-base-file 'savehist)))
          (features
           (seq-remove
            (lambda (feature)
              (memq feature '(savehist recentf bookmark tramp transient url
                              svg-lib treesit)))
            (copy-sequence features)))
          (use-package-always-ensure nil)
          events installs)
     (with-temp-file outside (insert "outside"))
     (make-symbolic-link outside savehist-path)
     (cl-letf (((symbol-function 'require)
                (lambda (feature &rest _)
                  (push (list :require feature
                              (file-directory-p sz/state-directory))
                        events)
                  t))
               ((symbol-function 'package-install)
                (lambda (&rest args) (push args installs)))
               ((symbol-function 'savehist-mode)
                (lambda (&rest args)
                  (push (list :savehist-mode args
                              (file-directory-p sz/state-directory))
                        events))))
       (should-error (eval savehist-form))
       (should-not events)
       (should-not installs)
       (delete-file savehist-path)
       (delete-directory sz/state-directory t)
       (eval savehist-form)
       (should (equal (nreverse events)
                      '((:require savehist t) (:savehist-mode (1) t))))
       (should-not installs)
       (setq events nil)
       (dolist (package '(recentf bookmark tramp transient url svg-lib treesit))
         (eval (macroexpand
                (sz/state-test--use-package-form
                 sz/state-test-base-file package))))
       (should-not events)
       (should-not installs)))))

(ert-deftest sz/state-xdg-invalid-values-use-defaults ()
  (dolist (values '((nil nil nil)
                    ("" "" "")
                    ("relative" "~/x" "./cache")
                    ("~" "~" "~")))
    (sz/state-test-with-environment
     (nth 0 values) (nth 1 values) (nth 2 values)
     (should (equal sz/data-directory
                    (file-name-as-directory
                     (expand-file-name ".local/share/emacs" home))))
     (should (equal sz/state-directory
                    (file-name-as-directory
                     (expand-file-name ".local/state/emacs" home))))
     (should (equal sz/cache-directory
                    (file-name-as-directory
                     (expand-file-name ".cache/emacs" home)))))))

(ert-deftest sz/state-xdg-normalizes-valid-absolute-values ()
  (sz/state-test-with-environment
   (expand-file-name "roots/one/../data" home)
   (expand-file-name "roots/two/../state" home)
   (expand-file-name "roots/three/../cache" home)
   (should (equal sz/data-directory
                  (expand-file-name "roots/data/emacs/" home)))
   (should (equal sz/state-directory
                  (expand-file-name "roots/state/emacs/" home)))
   (should (equal sz/cache-directory
                  (expand-file-name "roots/cache/emacs/" home)))))

(ert-deftest sz/state-xdg-valid-values-and-early-paths ()
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (let ((data (expand-file-name "data/emacs/" home))
         (state (expand-file-name "state/emacs/" home))
         (cache (expand-file-name "cache/emacs/" home)))
     (should (equal sz/data-directory data))
     (should (equal sz/state-directory state))
     (should (equal sz/cache-directory cache))
     (should (equal user-emacs-directory sz/state-test-emacs-directory))
     (should (equal (locate-user-emacs-file "templates")
                    (expand-file-name "templates" sz/state-test-emacs-directory)))
     (dolist (directory
              (list data
                    (expand-file-name "elpa/" data)
                    state
                    cache
                    (expand-file-name "eln-cache/" cache)))
       (should (file-directory-p directory))
       (should (= (file-modes directory) #o700)))
     (dolist (setting
              `((,package-user-dir . ,(expand-file-name "elpa/" data))
                (,custom-file . ,(expand-file-name "custom.el" state))
                (,package-quickstart-file . ,(expand-file-name "package-quickstart.el" cache))))
       (should (equal (car setting) (cdr setting))))
     (dolist (relative '("elfeed" "backups" "auto-save-list"
                         "projectile-sessions" "transient" "eshell" "agent" "url"))
       (should-not (file-exists-p (expand-file-name relative state))))
     (dolist (relative '("url" "tree-sitter" "svg-lib" "org-persist"))
       (should-not (file-exists-p (expand-file-name relative cache)))))))

(ert-deftest sz/state-package-owned-paths-match-migration-contract ()
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (let ((data sz/data-directory)
         (state sz/state-directory)
         (cache sz/cache-directory)
         (features (seq-remove
                    (lambda (feature)
                      (memq feature '(savehist recentf bookmark tramp transient url
                                      svg-lib treesit eshell project elfeed agent-shell
                                      projectile org)))
                    (copy-sequence features)))
         (treesit-extra-load-path nil)
         requires projectile-calls savehist-calls)
     (cl-letf (((symbol-function 'require)
                (lambda (feature &rest _)
                  (push feature requires)
                  t))
               ((symbol-function 'projectile-mode)
                (lambda (&rest args) (push args projectile-calls)))
               ((symbol-function 'savehist-mode)
                (lambda (&rest args) (push args savehist-calls))))
       (dolist (package '(emacs savehist recentf bookmark tramp transient url
                          svg-lib treesit eshell project elfeed agent-shell projectile))
         (sz/state-test--eval-use-package-section
          sz/state-test-base-file package :init))
       (sz/state-test--eval-use-package-section sz/state-test-org-file 'org :init)
       (sz/state-test--eval-use-package-section
        sz/state-test-base-file 'savehist :config))
     (should-not requires)
     (should (equal projectile-calls '((+1))))
     (should (equal savehist-calls '((1))))
     (dolist (setting
              `((,savehist-file . ,(expand-file-name "history" state))
                (,recentf-save-file . ,(expand-file-name "recentf" state))
                (,bookmark-default-file . ,(expand-file-name "bookmarks" state))
                (,tramp-persistency-file-name . ,(expand-file-name "tramp" state))
                (,transient-levels-file . ,(expand-file-name "transient/levels.el" state))
                (,transient-values-file . ,(expand-file-name "transient/values.el" state))
                (,transient-history-file . ,(expand-file-name "transient/history.el" state))
                (,url-configuration-directory . ,(expand-file-name "url/" state))
                (,url-cookie-file . ,(expand-file-name "url/cookies" state))
                (,url-history-file . ,(expand-file-name "url/history" state))
                (,url-cache-directory . ,(expand-file-name "url/" cache))
                (,svg-lib-icons-dir . ,(expand-file-name "svg-lib/" cache))
                (,sz/tree-sitter-directory . ,(expand-file-name "tree-sitter/" cache))
                (,eshell-directory-name . ,(expand-file-name "eshell/" state))
                (,project-list-file . ,(expand-file-name "projects" state))
                (,elfeed-db-directory . ,(expand-file-name "elfeed/" data))
                (,shell-maker-root-path . ,state)
                (,projectile-known-projects-file . ,(expand-file-name "projectile-bookmarks.eld" state))
                (,projectile-frecency-file . ,(expand-file-name "projectile-frecency.eld" state))
                (,projectile-session-directory . ,(expand-file-name "projectile-sessions/" state))
                (,org-id-locations-file . ,(expand-file-name ".org-id-locations" state))
                (,org-clock-persist-file . ,(expand-file-name "org-clock-save.el" state))
                (,org-persist-directory . ,(expand-file-name "org-persist/" cache))))
       (should (equal (car setting) (cdr setting))))
     (should (member (expand-file-name "tree-sitter/" cache)
                     treesit-extra-load-path))
     (dolist (directory
              (list (expand-file-name "backups/" state)
                    (expand-file-name "auto-save-list/" state)
                    (expand-file-name "transient/" state)
                    (expand-file-name "url/" state)
                    (expand-file-name "url/" cache)
                    (expand-file-name "svg-lib/" cache)
                    (expand-file-name "tree-sitter/" cache)
                    (expand-file-name "eshell/" state)
                    (expand-file-name "elfeed/" data)
                    (expand-file-name "agent/" state)
                    (expand-file-name "projectile-sessions/" state)
                    (expand-file-name "org-persist/" cache)))
       (should (file-directory-p directory))
       (should (= (file-modes directory) #o700)))
     (should (equal backup-directory-alist
                    `(("." . ,(expand-file-name "backups/" state)))))
     (should (equal auto-save-file-name-transforms
                    `((".*" ,(expand-file-name "auto-save-list/" state) t))))
     (should (equal auto-save-list-file-prefix
                    (expand-file-name "auto-save-list/.saves-" state)))
     (should backup-by-copying)
     (should delete-old-versions)
     (should (= kept-new-versions 6))
     (should (= kept-old-versions 2))
     (should version-control))))

(ert-deftest sz/state-early-layer-leaves-package-paths-to-owners ()
  (sz/state-test-with-sandbox
   (setenv "XDG_DATA_HOME" (expand-file-name "data" home))
   (setenv "XDG_STATE_HOME" (expand-file-name "state" home))
   (setenv "XDG_CACHE_HOME" (expand-file-name "cache" home))
   (let ((savehist-file 'untouched)
         (recentf-save-file 'untouched)
         (bookmark-default-file 'untouched)
         (tramp-persistency-file-name 'untouched)
         (transient-levels-file 'untouched)
         (transient-values-file 'untouched)
         (transient-history-file 'untouched)
         (url-configuration-directory 'untouched)
         (url-cookie-file 'untouched)
         (url-history-file 'untouched)
         (url-cache-directory 'untouched)
         (svg-lib-icons-dir 'untouched)
         (sz/tree-sitter-directory 'untouched)
         (eshell-directory-name 'untouched)
         (project-list-file 'untouched)
         (elfeed-db-directory 'untouched)
         (shell-maker-root-path 'untouched)
         (projectile-known-projects-file 'untouched)
         (projectile-frecency-file 'untouched)
         (projectile-session-directory 'untouched)
         (org-id-locations-file 'untouched)
         (org-clock-persist-file 'untouched)
         (org-persist-directory 'untouched))
     (load sz/state-test-file nil 'nomessage t)
     (should (seq-every-p
              (lambda (value) (eq value 'untouched))
              (list savehist-file recentf-save-file bookmark-default-file
                    tramp-persistency-file-name transient-levels-file
                    transient-values-file transient-history-file
                    url-configuration-directory url-cookie-file url-history-file
                    url-cache-directory svg-lib-icons-dir sz/tree-sitter-directory
                    eshell-directory-name project-list-file elfeed-db-directory
                    shell-maker-root-path projectile-known-projects-file
                    projectile-frecency-file projectile-session-directory
                    org-id-locations-file org-clock-persist-file
                    org-persist-directory))))))

(ert-deftest sz/state-package-owner-validates-before-side-effects ()
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (let ((bad-file (expand-file-name "projectile-bookmarks.eld" sz/state-directory))
         (session-directory (expand-file-name "projectile-sessions/" sz/state-directory))
         projectile-calls)
     (make-directory bad-file)
     (cl-letf (((symbol-function 'projectile-mode)
                (lambda (&rest args) (push args projectile-calls))))
       (should-error
        (sz/state-test--eval-use-package-section
         sz/state-test-base-file 'projectile :init)))
     (should-not projectile-calls)
     (should-not (file-exists-p session-directory)))))

(ert-deftest sz/state-foundational-declarations-precede-consumers ()
  (let ((forms (sz/state-test--read-forms sz/state-test-base-file)))
    (cl-labels ((index (package)
                  (cl-position-if
                   (lambda (form)
                     (and (eq (car-safe form) 'use-package)
                          (eq (cadr form) package)))
                   forms)))
      (let ((first-install
             (cl-position-if
              (lambda (form)
                (and (eq (car-safe form) 'use-package)
                     (or (eq (cadr (memq :ensure form)) t)
                         (memq :vc form))))
              forms)))
        (dolist (package '(transient url svg-lib treesit))
          (should (< (index package) first-install)))
        (should (< (index 'url) (index 'elfeed)))
        (should (< (index 'transient) (index 'magit)))
        (should (< (index 'transient) (index 'agent-shell)))
        (should (< (index 'svg-lib) (index 'kind-icon)))
        (should (< (index 'treesit) (index 'treesit-auto))))
    (dolist (package '(emacs savehist recentf bookmark tramp transient url
                        svg-lib treesit eshell project elfeed agent-shell projectile))
      (let ((form (sz/state-test--use-package-form
                   sz/state-test-base-file package :init)))
        (should (memq :catch form))
        (should-not (cadr (memq :catch form)))))
    (let ((org-form (sz/state-test--use-package-form
                     sz/state-test-org-file 'org :init)))
      (should (memq :catch org-form))
      (should-not (cadr (memq :catch org-form))))
    (dolist (package '(recentf bookmark tramp transient url svg-lib treesit))
      (let ((form (nth (cl-position-if
                        (lambda (candidate)
                          (and (eq (car-safe candidate) 'use-package)
                               (eq (cadr candidate) package)))
                        forms)
                       forms)))
        (should (memq :ensure form))
        (should-not (cadr (memq :ensure form)))
        (should (eq (cadr (memq :defer form)) t))))
    (let ((savehist (nth (cl-position-if
                          (lambda (form)
                            (and (eq (car-safe form) 'use-package)
                                 (eq (cadr form) 'savehist)))
                          forms)
                         forms)))
      (should (< (cl-position :init savehist)
                 (cl-position :config savehist)))))))

(ert-deftest sz/state-rejects-unsupported-absolute-xdg-values ()
  (dolist (value '("/ssh:host:/x" "/sudo::/x" "/local:dir/x" "/local/dir:/x"))
    (sz/state-test-with-sandbox
     (setenv "XDG_DATA_HOME" value)
     (setenv "XDG_STATE_HOME" (expand-file-name "state" home))
     (setenv "XDG_CACHE_HOME" (expand-file-name "cache" home))
     (should-error (load sz/state-test-file nil 'nomessage t))))
  (sz/state-test-with-sandbox
   (let ((real-getenv (symbol-function 'getenv)))
     (cl-letf (((symbol-function 'getenv)
                (lambda (name &optional frame)
                  (if (equal name "XDG_DATA_HOME")
                      (concat "/local/" (string 0) "x")
                    (funcall real-getenv name frame)))))
       (should-error (load sz/state-test-file nil 'nomessage t))))))

(ert-deftest sz/state-validates-early-plan-before-creation ()
  (sz/state-test-with-sandbox
   (let ((data (expand-file-name "data" home))
         (state (expand-file-name "state" home))
         (cache (expand-file-name "cache" home)))
     (dolist (directory (list data state cache))
       (make-directory directory)
       (set-file-modes directory #o750))
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (load sz/state-test-file nil 'nomessage t)
     (dolist (directory (list data state cache))
       (should (= (file-modes directory) #o750))
       (should (= (file-modes (expand-file-name "emacs" directory)) #o700)))))
  (sz/state-test-with-sandbox
   (let ((real (expand-file-name "real" home))
         (data (expand-file-name "data" home))
         (state (expand-file-name "state" home))
         (cache (expand-file-name "cache" home)))
     (make-directory real)
     (make-symbolic-link real data)
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (should-error (load sz/state-test-file nil 'nomessage t))
     (should-not (file-exists-p (expand-file-name "emacs" state)))
     (should-not (file-exists-p (expand-file-name "emacs" cache)))))
  (sz/state-test-with-sandbox
   (let ((data (expand-file-name "data" home))
         (state (expand-file-name "state" home))
         (cache (expand-file-name "cache" home)))
     (make-directory data)
     (set-file-modes data #o777)
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (should-error (load sz/state-test-file nil 'nomessage t))
     (should-not (file-exists-p (expand-file-name "emacs" state)))
     (should-not (file-exists-p (expand-file-name "emacs" cache)))))
  (sz/state-test-with-sandbox
   (let ((data (expand-file-name "shared" home))
         (state (expand-file-name "shared/emacs" home))
         (cache (expand-file-name "cache" home)))
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (should-error (load sz/state-test-file nil 'nomessage t))
     (should-not (file-exists-p data))
     (should-not (file-exists-p cache))))
  (sz/state-test-with-sandbox
   (let ((data (expand-file-name "data" home))
         (state (expand-file-name "state" home))
         (cache (expand-file-name "cache" home)))
     (make-directory (expand-file-name "emacs/custom.el" state) t)
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (should-error (load sz/state-test-file nil 'nomessage t))
     (should-not (file-exists-p (expand-file-name "emacs" data)))
     (should-not (file-exists-p (expand-file-name "emacs" cache))))))

(ert-deftest sz/state-canonicalizes-source-symlink-and-rejects-overlap ()
  (sz/state-test-with-sandbox
   (let ((source (expand-file-name "source" home))
         (source-link (expand-file-name "source-link" home)))
     (make-directory source)
     (make-symbolic-link source source-link)
     (setq user-emacs-directory (file-name-as-directory source-link))
     (setenv "XDG_DATA_HOME" (expand-file-name "data" home))
     (setenv "XDG_STATE_HOME" (expand-file-name "state" home))
     (setenv "XDG_CACHE_HOME" (expand-file-name "cache" home))
     (load sz/state-test-file nil 'nomessage t)
     (should (equal sz/source-directory
                    (file-name-as-directory (file-truename source))))
     (should (equal user-emacs-directory
                    (file-name-as-directory source-link)))))
  (sz/state-test-with-sandbox
   (let* ((data (expand-file-name "data" home))
          (source (expand-file-name "emacs/source" data))
          (state (expand-file-name "state" home))
          (cache (expand-file-name "cache" home)))
     (make-directory source t)
     (setq user-emacs-directory (file-name-as-directory source))
     (setenv "XDG_DATA_HOME" data)
     (setenv "XDG_STATE_HOME" state)
     (setenv "XDG_CACHE_HOME" cache)
     (should-error (load sz/state-test-file nil 'nomessage t))
     (should-not (file-exists-p (expand-file-name "emacs" state)))
     (should-not (file-exists-p (expand-file-name "emacs" cache))))))

(ert-deftest sz/state-retains-native-paths-and-adapts-treesit-install ()
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (sz/state-test--eval-use-package-section
    sz/state-test-base-file 'treesit :init)
   (let ((tree-dir (expand-file-name "cache/emacs/tree-sitter/" home))
         (explicit (expand-file-name "explicit" home))
         (chosen (expand-file-name "chosen" home))
         calls prompts answers)
     (should (equal native-comp-eln-load-path
                    (list (expand-file-name "cache/emacs/eln-cache/" home)
                          "/nix/store/native-lisp/"
                          "/system/native-lisp/")))
     (should (member tree-dir treesit-extra-load-path))
     (require 'treesit)
     (should (advice-member-p #'sz/state--treesit-install-language-grammar
                              'treesit-install-language-grammar))
     (should (interactive-form 'treesit-install-language-grammar))
     (let ((treesit-language-source-alist
            '((go "mock") (rust "mock") (python "mock") (bash "mock"))))
       (cl-letf (((symbol-function 'treesit--install-language-grammar-1)
                  (lambda (&rest args) (push args calls)))
                 ((symbol-function 'treesit-language-available-p)
                  (lambda (&rest _) '(t)))
                 ((symbol-function 'read-string)
                  (lambda (&rest args)
                    (push args prompts)
                    (let ((answer (pop answers)))
                      (if (eq answer :default) (nth 3 args) answer)))))
         (treesit-install-language-grammar 'go nil)
         (treesit-install-language-grammar 'rust explicit)
         (setq treesit--install-language-grammar-out-dir-history nil
               answers '(:default))
         (treesit-install-language-grammar 'python 'interactive)
         (setq treesit--install-language-grammar-out-dir-history
               '("/old/source/tree-sitter/")
               answers (list chosen))
         (treesit-install-language-grammar 'bash 'interactive))
       (setq calls (nreverse calls)
             prompts (nreverse prompts))
       (should (equal (mapcar #'car calls)
                      (list tree-dir explicit tree-dir chosen)))
       (should (= (length prompts) 2))
       (should (equal (mapcar (lambda (prompt) (nth 3 prompt)) prompts)
                      (list tree-dir tree-dir)))))))

(ert-deftest sz/state-cold-startup-stops-after-early-state-failure ()
  (sz/state-test-with-sandbox
   (let* ((early-init (expand-file-name "early-init.el" sz/state-test-emacs-directory))
          (init (expand-file-name "init.el" sz/state-test-emacs-directory))
          (allowed-loads (list (file-name-sans-extension early-init)
                               (file-name-sans-extension init)
                               sz/state-test-file))
          (features (delq 'sz-state (copy-sequence features)))
          (package-enable-at-startup t)
          (custom-file (expand-file-name "custom.el" home))
          (user-init-file nil)
          (init-file-user (user-login-name))
          (inhibit-default-init t)
          (real-load (symbol-function 'load))
          package-activations package-initializations requires blocked-loads)
     (with-temp-file custom-file
       (insert "(setq sz/state-test-custom-marker 'should-not-load)\n"))
     (setenv "XDG_DATA_HOME" "/bad:path")
     (setenv "XDG_STATE_HOME" (expand-file-name "state" home))
     (setenv "XDG_CACHE_HOME" (expand-file-name "cache" home))
     (cl-letf (((symbol-function 'load)
                (lambda (file &rest args)
                  (if (member (expand-file-name file) allowed-loads)
                      (apply real-load file args)
                    (push file blocked-loads))))
               ((symbol-function 'require)
                (lambda (feature &rest _)
                  (push feature requires)
                  t))
               ((symbol-function 'package-activate-all)
                (lambda () (setq package-activations (1+ (or package-activations 0)))))
               ((symbol-function 'package-initialize)
                (lambda () (setq package-initializations
                                  (1+ (or package-initializations 0))))))
       ;; This is the real startup error-catching boundary, not `should-error'.
       (startup--load-user-init-file (lambda () early-init))
       (when package-enable-at-startup
         (package-activate-all))
       (startup--load-user-init-file (lambda () init)))
     (should-not package-enable-at-startup)
     (should-not (featurep 'sz-state))
     (should-not package-activations)
     (should-not package-initializations)
     (should-not requires)
     (should-not blocked-loads)
     (should-not (boundp 'sz/state-test-custom-marker)))))

(ert-deftest sz/state-loader-order-is-explicit-and-safe ()
  (let ((early-init (expand-file-name "early-init.el" sz/state-test-emacs-directory))
        (user-emacs-directory sz/state-test-emacs-directory)
        (package-enable-at-startup t)
        loads)
    (cl-letf (((symbol-function 'load)
               (lambda (file &rest args)
                 (push (cons file args) loads))))
      (sz/state-test--eval-file early-init))
    (should (= (length loads) 1))
    (should-not package-enable-at-startup)
    (should (equal (caar loads) sz/state-test-file))
    (should (equal (cdar loads) '(nil nomessage t))))
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (with-temp-file custom-file
     (insert "(setq sz/state-test-custom-marker 'loader)\n"))
   (let ((events nil)
         (package-archives nil)
         (package-hidden-regexps nil)
         (load-path load-path))
     (cl-letf (((symbol-function 'require)
                (lambda (feature &rest _)
                  (push (list :require feature) events)))
               ((symbol-function 'package-initialize)
                (lambda () (push '(:package-initialize) events)))
               ((symbol-function 'load)
                (lambda (file &optional noerror nomessage nosuffix &rest _)
                  (push (list :load file noerror nomessage nosuffix) events))))
       (sz/state-test--eval-file
        (expand-file-name "init.el" sz/state-test-emacs-directory)))
     (setq events (nreverse events))
     (let* ((loads (seq-filter (lambda (event) (eq (car event) :load)) events))
            (files (mapcar #'cadr loads))
            (expected
             (append
              (list custom-file)
              (mapcar (lambda (file)
                        (expand-file-name file
                                          (expand-file-name "lisp/" sz/state-test-emacs-directory)))
                      '("sz-base.el" "sz-theme.el" "sz-meow.el" "sz-eat.el"
                        "sz-alerts.el" "sz-org.el" "sz-telega.el" "sz-mode-line.el"))
              (mapcar (lambda (file)
                        (expand-file-name file
                                          (expand-file-name "lisp/functions/" sz/state-test-emacs-directory)))
                      '("sz-howm-create-note.el"
                        "sz-org-capture-frame.el"
                        "sz-org-capture-timeblocks-loop.el"
                        "sz-org-waybar-current-timeblock.el"
                        "sz-telega-capture-message-to-inbox.el"
                        "sz-telega-save-msg-media.el")))))
       (should (equal files expected))
       (should (equal (car loads) (list :load custom-file nil 'nomessage t)))
       (should (seq-every-p (lambda (event) (eq (nth 4 event) t)) loads))
       (should (< (cl-position '(:package-initialize) events :test #'equal)
                  (cl-position (car loads) events :test #'equal)))))))

(ert-deftest sz/state-custom-file-absence-and-errors ()
  (sz/state-test-with-environment
   (expand-file-name "data" home)
   (expand-file-name "state" home)
   (expand-file-name "cache" home)
   (should-not (file-exists-p custom-file))
   (let ((events (sz/state-test--eval-init-with-boundaries)))
     (should-not (seq-find (lambda (event)
                            (and (eq (car event) :load)
                                 (equal (cadr event) custom-file)))
                          events)))
   (setq sz/state-test-custom-marker nil)
   (with-temp-file custom-file
     (insert "(setq sz/state-test-custom-marker 'loaded)\n"))
   (let* ((events (sz/state-test--eval-init-with-boundaries))
          (custom-event (seq-find (lambda (event)
                                    (and (eq (car event) :load)
                                         (equal (cadr event) custom-file)))
                                  events))
          (first-module (seq-find (lambda (event)
                                    (and (eq (car event) :load)
                                         (not (equal (cadr event) custom-file))))
                                  events)))
     (should (eq sz/state-test-custom-marker 'loaded))
     (should (equal custom-event
                    (list :load custom-file nil 'nomessage t)))
     (should (< (cl-position '(:package-initialize) events :test #'equal)
                (cl-position custom-event events :test #'equal)))
     (should (< (cl-position custom-event events :test #'equal)
                (cl-position first-module events :test #'equal))))
   (with-temp-file custom-file
     (insert "(setq sz/state-test-custom-marker 'broken))\n"))
   (should-error (sz/state-test--eval-init-with-boundaries)
                 :type 'invalid-read-syntax)
   (with-temp-file custom-file
     (insert "(setq sz/state-test-custom-marker 'unreadable)\n"))
   (unwind-protect
       (progn
         (set-file-modes custom-file #o000)
         (should-not (file-readable-p custom-file))
         (should-error (sz/state-test--eval-init-with-boundaries)
                       :type 'file-error))
     (set-file-modes custom-file #o600))))
