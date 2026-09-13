;;; sz-state.el --- XDG locations for generated Emacs state -*- lexical-binding: t; -*-

(defun sz/state--xdg-directory (environment fallback)
  "Return a normalized, colon-free local Emacs directory.
Use FALLBACK when ENVIRONMENT is unset, empty, or relative."
  (let* ((value (getenv environment))
         (base
          (cond
           ((or (null value)
                (= (length value) 0)
                (not (string-prefix-p "/" value)))
            (expand-file-name fallback))
           ((or (string-search ":" value)
                (string-search "\0" value))
            (error "%s must be a colon-free absolute local path" environment))
           (t (expand-file-name value))))
         (directory (file-name-as-directory (expand-file-name "emacs" base))))
    (when (or (string-search ":" directory)
              (string-search "\0" directory))
      (error "%s resolves outside the supported local path policy" environment))
    directory))

(defun sz/state--paths-overlap-p (left right)
  "Return non-nil when normalized directories LEFT and RIGHT overlap."
  (or (string-prefix-p left right)
      (string-prefix-p right left)))

(defun sz/state--validate-roots (roots source)
  "Reject overlapping ROOTS and overlap between any root and SOURCE."
  (let ((remaining roots))
    (while remaining
      (let ((root (car remaining)))
        (when (sz/state--paths-overlap-p root source)
          (error "State root overlaps Emacs source: %s" root))
        (dolist (other (cdr remaining))
          (when (sz/state--paths-overlap-p root other)
            (error "Emacs state roots overlap: %s and %s" root other))))
      (setq remaining (cdr remaining)))))

(defun sz/state--validate-existing-component (path directory-p)
  "Validate existing PATH, requiring a directory when DIRECTORY-P is non-nil."
  (when (file-symlink-p path)
    (error "Symlinked state path component is unsupported: %s" path))
  (when (file-exists-p path)
    (let* ((attributes (file-attributes path 'integer))
           (owner (file-attribute-user-id attributes))
           (modes (file-modes path)))
      (if directory-p
          (unless (file-directory-p path)
            (error "State path component is not a directory: %s" path))
        (unless (file-regular-p path)
          (error "Persistent state target is not a regular file: %s" path)))
      (unless (memq owner (list (user-uid) 0))
        (error "Unsafe owner for state path component: %s" path))
      (when (and (/= 0 (logand modes #o022))
                 (not (and directory-p
                           (= owner 0)
                           (/= 0 (logand modes #o1000)))))
        (error "Group/world-writable state path component is unsupported: %s"
               path)))))

(defun sz/state--validate-path (path directory-p)
  "Validate PATH and every existing parent without following symlinks.
DIRECTORY-P says PATH itself is a directory target; parents always are."
  (let ((current (directory-file-name path))
        (target-p t)
        done)
    (while (not done)
      (sz/state--validate-existing-component
       current (or directory-p (not target-p)))
      (let ((parent (directory-file-name (file-name-directory current))))
        (if (equal parent current)
            (setq done t)
          (setq current parent
                target-p nil))))))

(defun sz/state--ensure-directory (directory)
  "Create missing DIRECTORY components privately, without changing existing ones."
  (let ((cursor (directory-file-name directory))
        missing)
    (while (not (file-exists-p cursor))
      (when (file-symlink-p cursor)
        (error "Symlinked state path component is unsupported: %s" cursor))
      (push cursor missing)
      (setq cursor (directory-file-name (file-name-directory cursor))))
    (dolist (path missing)
      (make-directory path)
      (set-file-modes path #o700))))

(defun sz/state-prepare-paths (directories files)
  "Validate DIRECTORIES and FILES completely, then create dirs and file parents."
  (dolist (directory directories)
    (sz/state--validate-path directory t))
  (dolist (file files)
    (sz/state--validate-path file nil))
  (dolist (directory directories)
    (sz/state--ensure-directory directory))
  (dolist (file files)
    (sz/state--ensure-directory (file-name-directory file))))

(setq sz/source-directory
      (file-name-as-directory (file-truename user-emacs-directory))
      sz/data-directory (sz/state--xdg-directory "XDG_DATA_HOME" "~/.local/share")
      sz/state-directory (sz/state--xdg-directory "XDG_STATE_HOME" "~/.local/state")
      sz/cache-directory (sz/state--xdg-directory "XDG_CACHE_HOME" "~/.cache"))

(sz/state--validate-roots
 (list sz/data-directory sz/state-directory sz/cache-directory)
 sz/source-directory)

(setq package-user-dir (expand-file-name "elpa/" sz/data-directory)
      package-quickstart-file (expand-file-name "package-quickstart.el" sz/cache-directory)
      custom-file (expand-file-name "custom.el" sz/state-directory))

(let ((eln-cache (expand-file-name "eln-cache/" sz/cache-directory)))
  ;; Validate all root and early startup paths before creating directories.
  (sz/state-prepare-paths
   (list sz/data-directory package-user-dir sz/state-directory
         sz/cache-directory eln-cache)
   (list package-quickstart-file custom-file))
  (when (fboundp 'startup-redirect-eln-cache)
    (startup-redirect-eln-cache eln-cache)))

(provide 'sz-state)
;;; sz-state.el ends here
