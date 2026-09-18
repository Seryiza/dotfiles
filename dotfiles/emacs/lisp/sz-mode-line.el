;;; sz-mode-line.el --- Personal mode line, with an EWM-only desktop view -*- lexical-binding: t -*-

(require 'cl-lib)
(require 'subr-x)

(setq-default mode-line-percent-position nil)
(setq-default mode-line-position-column-line-format '("(%l,%c)"))

(defconst sz/ewm-mode-line--divider " · ")

(defun sz/ewm-mode-line--join (&rest fields)
  "Join nonblank status FIELDS with the same separator used for width budgets."
  (string-join (mapcar #'string-trim
                       (cl-remove-if-not #'sz/ewm-mode-line--nonempty-p fields))
               sz/ewm-mode-line--divider))

(defun sz/ewm-mode-line--surface-p ()
  "Return non-nil when the current buffer is an EWM surface proxy."
  (derived-mode-p 'ewm-surface-mode))

(defun sz/ewm-mode-line--ewm-p ()
  "Return non-nil while this Emacs is hosting EWM."
  (bound-and-true-p ewm-mode))

(defun sz/ewm-mode-line--desktop-p ()
  "Return non-nil for the one window that may show desktop status."
  (and (sz/ewm-mode-line--ewm-p)
       ;; The collector is loaded after EWM.  Do not make startup order an
       ;; error, and do not show a half-initialized desktop block.
       (bound-and-true-p sz/ewm-status-active)
       (mode-line-window-selected-p)))

(defun sz/ewm-mode-line--cached (symbol)
  "Return cached nonempty string SYMBOL, without asking its collector to work."
  (when (boundp symbol)
    (let ((value (symbol-value symbol)))
      (and (stringp value) (not (string-empty-p value)) value))))

(defun sz/ewm-mode-line--truncate (text width)
  "Fit TEXT in WIDTH columns, retaining TEXT in `help-echo' when shortened."
  (if (<= (string-width text) width)
      text
    (propertize (truncate-string-to-width text width nil nil "…")
                'help-echo text)))

(defun sz/ewm-mode-line--window-width ()
  "Return the current mode-line window width in columns."
  (window-total-width (selected-window)))

(defun sz/ewm-mode-line--identification ()
  "Render the existing buffer identification, compacting only surface titles."
  (let ((text (if (sz/ewm-mode-line--surface-p)
                  ;; EWM keeps this title up to date.  Showing it directly
                  ;; avoids exposing the proxy buffer's *ewm:...* wrapper.
                  (or (and (boundp 'ewm-surface-title)
                           (stringp ewm-surface-title)
                           (not (string-empty-p ewm-surface-title))
                           ewm-surface-title)
                      (and (boundp 'ewm-surface-app)
                           (stringp ewm-surface-app)
                           (not (string-empty-p ewm-surface-app))
                           ewm-surface-app)
                      (format-mode-line mode-line-buffer-identification))
                (format-mode-line mode-line-buffer-identification))))
    (if (sz/ewm-mode-line--surface-p)
        (sz/ewm-mode-line--truncate
         text
         ;; Status takes priority over a long external title.  Rendering this
         ;; context twice is formatting cached strings only, not a poll.
         (max 1 (min 48 (- (sz/ewm-mode-line--window-width)
                            (string-width (sz/ewm-mode-line--right-context))
                            4))))
      text)))

(defun sz/ewm-mode-line--tabs ()
  "Return the selected buffer's position in the window's native tab line."
  (when (bound-and-true-p tab-line-mode)
    (let* ((buffers (funcall tab-line-tabs-function))
           (position (cl-position (window-buffer) buffers)))
      (when position
        (format "Tabs %d/%d" (1+ position) (length buffers))))))

(defun sz/ewm-mode-line--narrow-audio (audio)
  "Keep AUDIO's meaningful warning on a narrow tile, if it has one."
  (cond ((string-prefix-p "MUTED" audio) audio)
        ((string-suffix-p " +MIC" audio) "+MIC")
        ((string= audio "audio?") audio)))

(defun sz/ewm-mode-line--desktop-status (&optional width tile-width)
  "Return in-memory EWM status for WIDTH columns on TILE-WIDTH.
Escape literal percent signs only when embedding this text in the mode line."
  (let* ((width (or width (sz/ewm-mode-line--window-width)))
         ;; WIDTH can be just the share reserved for status.  It constrains
         ;; content, but it is not the tile geometry that determines whether
         ;; optional desktop state belongs on a normal-sized display.
         (tile-width (or tile-width width))
         (narrow (< tile-width 100))
         (tabs (sz/ewm-mode-line--tabs))
         (timeblock (sz/ewm-mode-line--cached 'sz/ewm-status-timeblock))
         (audio (sz/ewm-mode-line--cached 'sz/ewm-status-audio))
         (network (sz/ewm-mode-line--cached 'sz/ewm-status-network))
         (wireguard (sz/ewm-mode-line--cached 'sz/ewm-status-wireguard))
         (layout (sz/ewm-mode-line--cached 'sz/ewm-status-layout))
         (power-saver (sz/ewm-mode-line--cached 'sz/ewm-status-power-saver))
         (audio-warning (and audio (sz/ewm-mode-line--narrow-audio audio)))
         (audio (if narrow audio-warning audio))
         (fields (delq nil (list tabs audio network
                                 (and (not narrow) layout)
                                 (and (not narrow) power-saver)))))
    ;; Keep the tab count and warnings whole.  Drop ordinary numeric volume
    ;; first when space runs out, while retaining its +MIC warning.
    (when (> (string-width (apply #'sz/ewm-mode-line--join fields)) width)
      (setq fields (delq audio fields)
            audio audio-warning)
      (when audio
        (setq fields (append fields (list audio)))))
    (dolist (field (list power-saver layout))
      (when (> (string-width (apply #'sz/ewm-mode-line--join fields)) width)
        (setq fields (delq field fields))))
    (let* ((fixed-width (string-width
                         (apply #'sz/ewm-mode-line--join fields)))
           (variable-count (+ (if timeblock 1 0) (if wireguard 1 0)))
           (content-width (max 0 (- width fixed-width
                                    (* variable-count
                                       (string-width sz/ewm-mode-line--divider)))))
           (time-width (and timeblock
                            (if wireguard
                                (/ (+ content-width 1) 2)
                              content-width)))
           (wireguard-width (and wireguard
                                 (if timeblock
                                     (/ content-width 2)
                                   content-width))))
      (sz/ewm-mode-line--join
       tabs
       (and (> (or time-width 0) 0)
            (sz/ewm-mode-line--truncate timeblock time-width))
       (and (memq audio fields) audio)
       (and (memq network fields) network)
       (and (> (or wireguard-width 0) 0)
            (sz/ewm-mode-line--truncate wireguard wireguard-width))
       (and (memq layout fields) layout)
       (and (memq power-saver fields) power-saver)))))

(defconst sz/ewm-mode-line--editor-indicators
  '(:propertize
    ("" mode-line-mule-info mode-line-client mode-line-modified
     mode-line-remote mode-line-window-dedicated)
    display (min-width (6.0))))

(defun sz/ewm-mode-line--format (construct)
  "Format CONSTRUCT for this buffer without changing its state."
  (format-mode-line construct nil (selected-window) (current-buffer)))

(defun sz/ewm-mode-line--editor-context ()
  "Return the existing editor-only right-side context for ordinary buffers."
  (unless (sz/ewm-mode-line--surface-p)
    (sz/ewm-mode-line--join
     (sz/ewm-mode-line--format '(project-mode-line project-mode-line-format))
     (sz/ewm-mode-line--format sz/ewm-mode-line--editor-indicators))))

(defun sz/ewm-mode-line--nonempty-p (text)
  "Return non-nil when TEXT is a nonblank mode-line string."
  (and (stringp text) (not (string-blank-p text))))

(defun sz/ewm-mode-line--global-context (&optional width components)
  "Return global status once, shortening only Org clock text for WIDTH.
Battery and clock remain whole, so a low battery is not displaced by a long
clocked heading.  With COMPONENTS, return (OTHER ORG TIME) unjoined."
  (let* ((items (if (listp global-mode-string)
                     global-mode-string
                   (list global-mode-string)))
          (org-items (cl-remove-if-not (lambda (item) (eq item 'org-mode-line-string)) items))
          (time-items (cl-remove-if-not (lambda (item) (eq item 'display-time-string)) items))
          (other-items (cl-remove-if (lambda (item)
                                       (memq item '(org-mode-line-string display-time-string)))
                                     items))
          (other (apply #'sz/ewm-mode-line--join
                        (mapcar (lambda (item) (sz/ewm-mode-line--format (list "" item)))
                                other-items)))
          (org (and org-items
                    (sz/ewm-mode-line--format (cons "" org-items))))
          (time (and time-items
                     (sz/ewm-mode-line--format (cons "" time-items))))
          ;; Reserve two thirds of a narrow tile for desktop warnings and the
          ;; app title.  Built-in non-Org items are never clipped here.
          (org-width (and width
                          (max 0 (- (/ width 3)
                                    (string-width (sz/ewm-mode-line--join other time))))))
          (org (and (sz/ewm-mode-line--nonempty-p org)
                    (if org-width
                        (and (> org-width 0)
                             (sz/ewm-mode-line--truncate org org-width))
                      org))))
    (if components
        (list other org time)
      (sz/ewm-mode-line--join other org time))))

(defun sz/ewm-mode-line-keep-clock-last ()
  "Move an existing display clock last; never start, stop, or add one.
The EWM status collector owns display-time and battery lifecycle."
  (when (and (sz/ewm-mode-line--ewm-p)
             (memq 'display-time-string global-mode-string))
    (setq global-mode-string
          (append (delq 'display-time-string (copy-sequence global-mode-string))
                  '(display-time-string)))))

(defun sz/ewm-mode-line--right-context ()
  "Render context without duplicating desktop status in inactive EWM tiles."
  (let ((width (sz/ewm-mode-line--window-width)))
    (if (not (sz/ewm-mode-line--ewm-p))
        ;; Ordinary editor buffers retain their original misc-info format.
        (sz/ewm-mode-line--format 'mode-line-misc-info)
      (let ((editor (sz/ewm-mode-line--editor-context)))
        (if (not (mode-line-window-selected-p))
            (sz/ewm-mode-line--join editor)
          (let* ((global-parts (sz/ewm-mode-line--global-context nil t))
               (global-other (nth 0 global-parts))
               (global-org (nth 1 global-parts))
               (global-time (nth 2 global-parts))
               ;; This is the non-negotiable floor: Tabs and whole warnings,
               ;; plus the actual battery/clock strings in the global parts.
               ;; Tiny tiles may be narrower than the floor, by design.
               (desktop-floor (and (sz/ewm-mode-line--desktop-p)
                                   (sz/ewm-mode-line--desktop-status 0 width)))
               (fixed (sz/ewm-mode-line--join editor desktop-floor global-other global-time))
               ;; Give status half the remaining room, then let Org reclaim
               ;; whatever its actual timeblock/WG rendering did not use.
               (desktop-budget (+ (string-width (or desktop-floor ""))
                                  (max 0 (/ (- width (string-width fixed)) 2))))
               (desktop (and (sz/ewm-mode-line--desktop-p)
                             (sz/ewm-mode-line--desktop-status desktop-budget width)))
               (without-org (sz/ewm-mode-line--join editor desktop global-other global-time))
               (org-width (and global-org
                               (max 0 (- width (string-width without-org)
                                         (string-width sz/ewm-mode-line--divider))))))
            (sz/ewm-mode-line--join
             editor desktop global-other
             (and org-width (> org-width 0)
                  (sz/ewm-mode-line--truncate global-org org-width))
             global-time)))))))

(setq-default mode-line-format
              '("%e"
                (:eval (meow-indicator))
                " "
                (:eval (string-replace "%" "%%" (sz/ewm-mode-line--identification)))
                (:eval (unless (sz/ewm-mode-line--surface-p) "  "))
                (:eval (unless (sz/ewm-mode-line--surface-p)
                         (string-replace "%" "%%"
                                         (sz/ewm-mode-line--format mode-line-position))))

                mode-line-format-right-align
                (:eval (string-replace "%" "%%" (sz/ewm-mode-line--right-context)))
                mode-line-end-spaces))
