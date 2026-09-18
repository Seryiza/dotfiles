;;; sz-ewm-status.el --- Cached EWM status collectors -*- lexical-binding: t -*-

;; Mode-line code reads only these values.  All I/O happens in timers,
;; subprocess sentinels, or D-Bus callbacks.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'time)
(require 'battery)
(require 'dbus)

(defvar sz/ewm-status-timeblock "")
(defvar sz/ewm-status-audio "")
(defvar sz/ewm-status-network "")
(defvar sz/ewm-status-wireguard "")
(defvar sz/ewm-status-layout "")
(defvar sz/ewm-status-power-saver "")
(defvar sz/ewm-status-active nil)

(defvar sz/ewm-status--audio-process nil)
(defvar sz/ewm-status--audio-timeout nil)
(defvar sz/ewm-status--audio-timer nil)
(defvar sz/ewm-status--audio-generation 0)
(defvar sz/ewm-status--timeblock-timer nil)
(defvar sz/ewm-status--timeblock-debounce nil)
(defvar sz/ewm-status--dbus-debounce nil)
(defvar sz/ewm-status--dbus-retry nil)
(defvar sz/ewm-status--dbus-registration-retry nil)
(defvar sz/ewm-status--dbus-pending-refresh nil)
(defvar sz/ewm-status--dbus-objects nil)
(defvar sz/ewm-status--dbus-provider-objects nil)
(defvar sz/ewm-status--dbus-generation 0)
(defvar sz/ewm-status--nm-inflight nil)
(defvar sz/ewm-status--power-inflight nil)
(defvar sz/ewm-status--nm-timeout nil)
(defvar sz/ewm-status--power-timeout nil)
(defvar sz/ewm-status--dbus-pending nil)
(defvar sz/ewm-status--saved-time nil)
(defvar sz/ewm-status--saved-battery nil)
(defvar sz/ewm-status--event-advice-installed nil)

(defconst sz/ewm-status--nm "org.freedesktop.NetworkManager")
(defconst sz/ewm-status--nm-root "/org/freedesktop/NetworkManager")
(defconst sz/ewm-status--properties "org.freedesktop.DBus.Properties")
(defconst sz/ewm-status--power "org.freedesktop.UPower.PowerProfiles")
(defconst sz/ewm-status--power-path "/org/freedesktop/UPower/PowerProfiles")

(defun sz/ewm-status--publish (symbol value)
  "Set cached SYMBOL to string VALUE and redraw only when it changed."
  (setq value (or value ""))
  (unless (equal (symbol-value symbol) value)
    (set symbol value)
    (force-mode-line-update t)))

(defun sz/ewm-status--cancel (timer)
  (when (timerp timer) (cancel-timer timer)))

(defun sz/ewm-status--current-p (generation)
  "Return non-nil when GENERATION belongs to the live D-Bus collector."
  (and sz/ewm-status-active (= generation sz/ewm-status--dbus-generation)))

(defun sz/ewm-status--snapshot-current-p (generation token)
  "Return non-nil while TOKEN is the live snapshot for its provider."
  (and (sz/ewm-status--current-p generation)
       (or (eq token sz/ewm-status--nm-inflight)
           (eq token sz/ewm-status--power-inflight))))

;;; Audio

(defun sz/ewm-status--audio-value (output input)
  "Format parsed wpctl OUTPUT and INPUT alists, or return nil on malformed data."
  (when (and output input)
    (concat (if (plist-get output :muted)
                "MUTED"
              (format "%d%% audio" (round (* 100 (plist-get output :volume)))))
            (unless (plist-get input :muted) " +MIC"))))

(defun sz/ewm-status--parse-wpctl (text)
  "Parse wpctl get-volume TEXT into (:volume FLOAT :muted BOOL), or nil."
  (when (string-match "Volume:[[:space:]]*\\([0-9.]+\\)\\(?:.*\\[MUTED\\]\\)?" text)
    (list :volume (string-to-number (match-string 1 text))
          :muted (string-match-p "\\[MUTED\\]" text))))

(defun sz/ewm-status--audio-cleanup (generation sink source)
  "Dispose of GENERATION's temporary audio state."
  (when (= generation sz/ewm-status--audio-generation)
    (sz/ewm-status--cancel sz/ewm-status--audio-timeout)
    (setq sz/ewm-status--audio-timeout nil
          sz/ewm-status--audio-process nil))
  (when (buffer-live-p sink) (kill-buffer sink))
  (when (buffer-live-p source) (kill-buffer source)))

(defun sz/ewm-status--audio-fail (generation sink source)
  (when (and sz/ewm-status-active
             (= generation sz/ewm-status--audio-generation))
    (sz/ewm-status--publish 'sz/ewm-status-audio "audio?"))
  (sz/ewm-status--audio-cleanup generation sink source))

(defun sz/ewm-status--audio-finish (generation sink source)
  (when (and sz/ewm-status-active
             (= generation sz/ewm-status--audio-generation))
    (if-let ((value (sz/ewm-status--audio-value
                     (with-current-buffer sink
                       (sz/ewm-status--parse-wpctl (buffer-string)))
                     (with-current-buffer source
                       (sz/ewm-status--parse-wpctl (buffer-string))))))
        (sz/ewm-status--publish 'sz/ewm-status-audio value)
      (sz/ewm-status--publish 'sz/ewm-status-audio "audio?")))
  (sz/ewm-status--audio-cleanup generation sink source))

(defun sz/ewm-status--audio-refresh ()
  "Refresh sink and source serially under one shared 1.5 second budget."
  (when (and sz/ewm-status-active
             (not (process-live-p sz/ewm-status--audio-process)))
    (let* ((generation (cl-incf sz/ewm-status--audio-generation))
           (sink (generate-new-buffer " *ewm-wpctl-sink*"))
           (source (generate-new-buffer " *ewm-wpctl-source*")))
      (condition-case nil
          (setq sz/ewm-status--audio-process
                (make-process
                 :name "ewm-wpctl-sink" :buffer sink :noquery t
                 :command '("wpctl" "get-volume" "@DEFAULT_AUDIO_SINK@")
                 :sentinel
                 (lambda (process _event)
                   (when (memq (process-status process) '(exit signal))
                     (if (and (zerop (process-exit-status process))
                              sz/ewm-status-active
                              (= generation sz/ewm-status--audio-generation))
                         (condition-case nil
                             (setq sz/ewm-status--audio-process
                                   (make-process
                                    :name "ewm-wpctl-source" :buffer source :noquery t
                                    :command '("wpctl" "get-volume" "@DEFAULT_AUDIO_SOURCE@")
                                    :sentinel
                                    (lambda (source-process _source-event)
                                      (when (memq (process-status source-process) '(exit signal))
                                        (if (zerop (process-exit-status source-process))
                                            (sz/ewm-status--audio-finish generation sink source)
                                          (sz/ewm-status--audio-fail generation sink source))))))
                           (error (sz/ewm-status--audio-fail generation sink source)))
                       (sz/ewm-status--audio-fail generation sink source))))))
        (error (sz/ewm-status--audio-fail generation sink source)))
      (setq sz/ewm-status--audio-timeout
            (run-at-time
             1.5 nil
             (lambda ()
               (when (and sz/ewm-status-active
                          (= generation sz/ewm-status--audio-generation))
                 (when (process-live-p sz/ewm-status--audio-process)
                   (delete-process sz/ewm-status--audio-process))
                 (sz/ewm-status--audio-fail generation sink source))))))))

;;; Org timeblock

(defun sz/ewm-status--ten-minute-boundary ()
  "Return the next local ten-minute boundary."
  (let* ((now (current-time)) (parts (decode-time now))
         (minute (nth 1 parts)) (delta (- 10 (% minute 10))))
    (time-add now (seconds-to-time (- (* delta 60) (nth 0 parts))))))

(defun sz/ewm-status--timeblock-refresh ()
  "Cache the current Org timeblock and schedule its next bounded refresh."
  (sz/ewm-status--cancel sz/ewm-status--timeblock-debounce)
  (setq sz/ewm-status--timeblock-debounce nil)
  (when sz/ewm-status-active
    (let* ((state (condition-case nil
                      (if (fboundp 'sz/org-waybar-timeblock-state)
                          (sz/org-waybar-timeblock-state)
                        (cons "" nil))
                    (error (cons "" nil))))
           (next (cdr state))
           (boundary (sz/ewm-status--ten-minute-boundary))
           (deadline (if (and next (time-less-p next boundary)) next boundary)))
      (sz/ewm-status--publish 'sz/ewm-status-timeblock (or (car state) ""))
      (sz/ewm-status--cancel sz/ewm-status--timeblock-timer)
      (setq sz/ewm-status--timeblock-timer
            (run-at-time deadline nil #'sz/ewm-status--timeblock-refresh)))))

(defun sz/ewm-status-timeblock-invalidate (&rest _)
  "Debounce changes that can alter the Org timeblock cache."
  (when sz/ewm-status-active
    (sz/ewm-status--cancel sz/ewm-status--timeblock-debounce)
    (setq sz/ewm-status--timeblock-debounce
          (run-with-idle-timer 0.5 nil #'sz/ewm-status--timeblock-refresh))))

(defun sz/ewm-status--agenda-change (&rest _)
  "Invalidate after edits in an agenda file, without parsing during the edit."
  (when (and buffer-file-name
             (member buffer-file-name (org-agenda-files)))
    (sz/ewm-status-timeblock-invalidate)))

(defun sz/ewm-status--org-mode ()
  (add-hook 'after-change-functions #'sz/ewm-status--agenda-change nil t))

;;; Builtin clock and battery

(defun sz/ewm-status--battery-update (data)
  "Hide only a genuinely Full battery; retain 100% Charging immediately."
  (let ((format (unless (equal (cdr (assq ?B data)) "Full") " %p%% battery")))
    (setq battery-mode-line-format (or format "")
          ;; `battery-update-functions' runs after the builtin formats its
          ;; string, so replace this update too rather than waiting 60 seconds.
          battery-mode-line-string (and format (battery-format format data)))))

;;; D-Bus

(defun sz/ewm-status--dbus-get (service path interface property generation token callback failure)
  "Asynchronously read PROPERTY, with a bounded request and stale callback guard."
  (condition-case nil
      (dbus-call-method-asynchronously
       :system service path sz/ewm-status--properties "Get"
        ;; Properties.Get returns one variant argument.  Emacs represents that
        ;; variant as a one-element list, including false and array values.
        (lambda (variant)
          (when (sz/ewm-status--snapshot-current-p generation token)
            (condition-case nil
                (funcall callback (car variant))
              (error (condition-case nil (funcall failure) (error nil))))))
        :timeout 5000 interface property)
    (error (when (sz/ewm-status--snapshot-current-p generation token)
             (condition-case nil (funcall failure) (error nil))))))

(defun sz/ewm-status--alist (key object)
  "Get KEY from OBJECT accepting D-Bus alists with string or symbol keys."
  (or (cdr (assoc key object)) (cdr (assoc (intern-soft key) object))))

(defun sz/ewm-status--network-string (devices wifi-enabled wifi-hardware-enabled)
  "Return the selected primary Ethernet/Wi-Fi problem string.
The simple Ethernet-first selection is deliberate; NM connectivity probing and
the old multi-uplink ranking are not part of this mode-line collector."
  (let ((candidates (seq-filter (lambda (device)
                                  (and (memq (plist-get device :type) '(1 2))
                                       (<= 40 (or (plist-get device :state) -1) 100)
                                       (stringp (plist-get device :interface))))
                                devices)))
    (cond
     ((null devices) "network?")
     ((null candidates) (if (and wifi-enabled wifi-hardware-enabled)
                            "Disconnected" "Wi-Fi disabled"))
     (t (let* ((chosen (car (sort candidates
                                  (lambda (a b) (< (plist-get a :type) (plist-get b :type))))))
               (name (plist-get chosen :interface)))
          (cond ((not (plist-get chosen :ip4)) (format "%s (No IP)" name))
                ((and (= (plist-get chosen :type) 2)
                      (< (or (plist-get chosen :strength) 100) 20)) "<20% wlan")
                (t "")))))))

(defun sz/ewm-status--dbus-schedule-retry ()
  (when sz/ewm-status-active
    (sz/ewm-status--cancel sz/ewm-status--dbus-retry)
    (setq sz/ewm-status--dbus-retry
          (run-at-time 1 nil
                       (lambda ()
                         (setq sz/ewm-status--dbus-retry nil)
                         (sz/ewm-status--dbus-refresh))))))

(defun sz/ewm-status--dbus-schedule-registration-retry ()
  (when sz/ewm-status-active
    (sz/ewm-status--cancel sz/ewm-status--dbus-registration-retry)
    (setq sz/ewm-status--dbus-registration-retry
          (run-at-time 1 nil
                       (lambda ()
                         (setq sz/ewm-status--dbus-registration-retry nil)
                         (sz/ewm-status--register-dbus)
                         (sz/ewm-status--dbus-refresh))))))

(defun sz/ewm-status--dbus-finished ()
  "Start one deferred refresh after an in-flight snapshot settles."
  (when (and sz/ewm-status-active
             sz/ewm-status--dbus-pending
             (not sz/ewm-status--nm-inflight)
             (not sz/ewm-status--power-inflight))
    (setq sz/ewm-status--dbus-pending nil)
    (sz/ewm-status--cancel sz/ewm-status--dbus-pending-refresh)
    (setq sz/ewm-status--dbus-pending-refresh
          (run-at-time 0 nil #'sz/ewm-status--dbus-refresh))))

(defun sz/ewm-status--nm-fail (generation token)
  (when (sz/ewm-status--snapshot-current-p generation token)
    (sz/ewm-status--cancel sz/ewm-status--nm-timeout)
    (setq sz/ewm-status--nm-timeout nil sz/ewm-status--nm-inflight nil)
    ;; Network and WireGuard have one NetworkManager failure domain.
    (sz/ewm-status--publish 'sz/ewm-status-network "network?")
    (sz/ewm-status--publish 'sz/ewm-status-wireguard "")
    (sz/ewm-status--dbus-schedule-retry)
    (sz/ewm-status--dbus-finished)))

(defun sz/ewm-status--nm-success (generation token network wireguard)
  (when (sz/ewm-status--snapshot-current-p generation token)
    (sz/ewm-status--cancel sz/ewm-status--nm-timeout)
    (setq sz/ewm-status--nm-timeout nil sz/ewm-status--nm-inflight nil)
    (sz/ewm-status--publish 'sz/ewm-status-network network)
    (sz/ewm-status--publish 'sz/ewm-status-wireguard wireguard)
    (sz/ewm-status--dbus-finished)))

(defun sz/ewm-status--nm-network (generation token devices wireless hardware done fail)
  "Resolve the primary device's IPv4 and, for Wi-Fi, its AP strength."
  (let ((candidates (seq-filter (lambda (device)
                                  (and (memq (plist-get device :type) '(1 2))
                                       (<= 40 (or (plist-get device :state) -1) 100)))
                                devices)))
    (if (null candidates)
        (funcall done (sz/ewm-status--network-string devices wireless hardware))
      (let* ((device (car (sort candidates
                                (lambda (a b) (< (plist-get a :type) (plist-get b :type))))))
             (ip4-path (plist-get device :ip4-path)))
        (if (equal ip4-path "/")
            (funcall done (sz/ewm-status--network-string
                           (list (plist-put device :ip4 nil)) wireless hardware))
          (sz/ewm-status--dbus-get
           sz/ewm-status--nm ip4-path "org.freedesktop.NetworkManager.IP4Config" "AddressData"
           generation token
           (lambda (addresses)
             (setq device (plist-put device :ip4 (and addresses t)))
             (if (and (= (plist-get device :type) 2) (plist-get device :ip4))
                 (sz/ewm-status--dbus-get
                  sz/ewm-status--nm (plist-get device :path)
                  "org.freedesktop.NetworkManager.Device.Wireless" "ActiveAccessPoint" generation token
                  (lambda (ap)
                    (if (equal ap "/")
                        (funcall fail)
                      (sz/ewm-status--dbus-get
                       sz/ewm-status--nm ap "org.freedesktop.NetworkManager.AccessPoint" "Strength"
                       generation token
                       (lambda (strength)
                         (funcall done (sz/ewm-status--network-string
                                        (list (plist-put device :strength strength)) wireless hardware)))
                       fail)))
                  fail)
               (funcall done (sz/ewm-status--network-string (list device) wireless hardware))))
           fail))))))

(defun sz/ewm-status--nm-devices (generation token paths wireless hardware done fail)
  (if (null paths)
      (funcall done nil)
    (let ((left (length paths)) devices failed)
      (dolist (path paths)
        (let ((data nil) (pending 4))
          (dolist (property '("DeviceType" "State" "Interface" "Ip4Config"))
            (sz/ewm-status--dbus-get
             sz/ewm-status--nm path "org.freedesktop.NetworkManager.Device" property generation token
             (lambda (value)
               (push (cons property value) data)
               (cl-decf pending)
               (when (zerop pending)
                 (push (list :path path
                             :type (sz/ewm-status--alist "DeviceType" data)
                             :state (sz/ewm-status--alist "State" data)
                             :interface (sz/ewm-status--alist "Interface" data)
                             :ip4-path (sz/ewm-status--alist "Ip4Config" data)) devices)
                 (cl-decf left)
                 (when (zerop left)
                   (if failed (funcall fail)
                     (sz/ewm-status--nm-network generation token devices wireless hardware done fail)))))
             (lambda ()
               (setq failed t)
               (cl-decf pending)
               (when (zerop pending)
                 (cl-decf left)
                 (when (zerop left) (funcall fail)))))))))))

(defun sz/ewm-status--nm-get-settings (generation token path done fail)
  (condition-case nil
      (dbus-call-method-asynchronously
       :system sz/ewm-status--nm path "org.freedesktop.NetworkManager.Settings.Connection" "GetSettings"
       (lambda (settings)
         (when (sz/ewm-status--snapshot-current-p generation token)
           (condition-case nil
               ;; GetSettings returns a{sa{sv}} list entries with nested variants.
               (if-let* ((connection (cadr (assoc "connection" settings)))
                         (id (car (cadr (assoc "id" connection)))))
                   (funcall done id)
                 (funcall fail))
             (error (condition-case nil (funcall fail) (error nil))))))
       :timeout 5000)
    (error (when (sz/ewm-status--snapshot-current-p generation token)
             (condition-case nil (funcall fail) (error nil))))))

(defun sz/ewm-status--nm-wireguard (generation token paths done fail)
  "Read active NM WireGuard settings ids; profile ids are not interface names."
  (if (null paths)
      (funcall done "")
    (let ((left (length paths)) names failed)
      (cl-labels ((finish ()
                    (cl-decf left)
                    (when (zerop left)
                      (if failed (funcall fail)
                        (funcall done (mapconcat #'identity (sort names #'string<) " | "))))))
        (dolist (path paths)
          (let ((data nil) (pending 3))
            (dolist (property '("Type" "State" "Connection"))
              (sz/ewm-status--dbus-get
               sz/ewm-status--nm path "org.freedesktop.NetworkManager.Connection.Active" property generation token
               (lambda (value)
                 (push (cons property value) data)
                 (cl-decf pending)
                 (when (zerop pending)
                   (if (and (equal (sz/ewm-status--alist "Type" data) "wireguard")
                            (= (or (sz/ewm-status--alist "State" data) -1) 2))
                       (sz/ewm-status--nm-get-settings
                        generation token (sz/ewm-status--alist "Connection" data)
                        (lambda (id) (push id names) (finish))
                        (lambda () (setq failed t) (finish)))
                     (finish))))
               (lambda ()
                 (setq failed t)
                 (cl-decf pending)
                 (when (zerop pending) (finish)))))))))))

(defun sz/ewm-status--nm-refresh ()
  "Take one atomic asynchronous NetworkManager snapshot."
  (when (and sz/ewm-status-active (not sz/ewm-status--nm-inflight))
    (let ((generation sz/ewm-status--dbus-generation) (token (list nil))
          (root nil) (pending 4) failed network wireguard)
      (setq sz/ewm-status--nm-inflight token
            sz/ewm-status--nm-timeout
            (run-at-time 5 nil (lambda () (sz/ewm-status--nm-fail generation token))))
      (cl-labels ((finish-root ()
                    (cl-decf pending)
                    (when (zerop pending)
                      (if failed
                          (sz/ewm-status--nm-fail generation token)
                        (let ((complete (lambda ()
                                          (when (and network wireguard)
                                            (sz/ewm-status--nm-success generation token network wireguard)))))
                          (sz/ewm-status--nm-devices
                           generation token (sz/ewm-status--alist "Devices" root)
                           (sz/ewm-status--alist "WirelessEnabled" root)
                           (sz/ewm-status--alist "WirelessHardwareEnabled" root)
                           (lambda (value) (setq network value) (funcall complete))
                           (lambda () (sz/ewm-status--nm-fail generation token)))
                          (sz/ewm-status--nm-wireguard
                           generation token (sz/ewm-status--alist "ActiveConnections" root)
                           (lambda (value) (setq wireguard value) (funcall complete))
                           (lambda () (sz/ewm-status--nm-fail generation token)))))))
                  (read (property)
                    (sz/ewm-status--dbus-get
                     sz/ewm-status--nm sz/ewm-status--nm-root sz/ewm-status--nm property generation token
                     (lambda (value) (push (cons property value) root) (finish-root))
                     (lambda () (setq failed t) (finish-root)))))
        (read "Devices") (read "WirelessEnabled")
        (read "WirelessHardwareEnabled") (read "ActiveConnections")))))

(defun sz/ewm-status--power-fail (generation token)
  (when (sz/ewm-status--snapshot-current-p generation token)
    (sz/ewm-status--cancel sz/ewm-status--power-timeout)
    (setq sz/ewm-status--power-timeout nil sz/ewm-status--power-inflight nil)
    (sz/ewm-status--publish 'sz/ewm-status-power-saver "")
    (sz/ewm-status--dbus-schedule-retry)
    (sz/ewm-status--dbus-finished)))

(defun sz/ewm-status--power-refresh ()
  (when (and sz/ewm-status-active (not sz/ewm-status--power-inflight))
    (let ((generation sz/ewm-status--dbus-generation) (token (list nil)))
      (setq sz/ewm-status--power-inflight token
            sz/ewm-status--power-timeout
            (run-at-time 5 nil (lambda () (sz/ewm-status--power-fail generation token))))
      (sz/ewm-status--dbus-get
       sz/ewm-status--power sz/ewm-status--power-path sz/ewm-status--power "ActiveProfile" generation token
       (lambda (profile)
         (when (sz/ewm-status--snapshot-current-p generation token)
           (sz/ewm-status--cancel sz/ewm-status--power-timeout)
           (setq sz/ewm-status--power-timeout nil sz/ewm-status--power-inflight nil)
           (sz/ewm-status--publish 'sz/ewm-status-power-saver
                                   (if (equal profile "power-saver") "POWER SAVER" ""))
           (sz/ewm-status--dbus-finished)))
       (lambda () (sz/ewm-status--power-fail generation token))))))

(defun sz/ewm-status--dbus-refresh ()
  (dolist (timer (list sz/ewm-status--dbus-debounce sz/ewm-status--dbus-retry
                       sz/ewm-status--dbus-pending-refresh))
    (sz/ewm-status--cancel timer))
  (setq sz/ewm-status--dbus-debounce nil sz/ewm-status--dbus-retry nil
        sz/ewm-status--dbus-pending-refresh nil)
  (when sz/ewm-status-active
    (if (or sz/ewm-status--nm-inflight sz/ewm-status--power-inflight)
        (setq sz/ewm-status--dbus-pending t)
      (cl-incf sz/ewm-status--dbus-generation)
      (sz/ewm-status--nm-refresh)
      (sz/ewm-status--power-refresh))))

(defun sz/ewm-status--dbus-invalidate (&rest _)
  (when sz/ewm-status-active
    (sz/ewm-status--cancel sz/ewm-status--dbus-debounce)
    (setq sz/ewm-status--dbus-debounce
          (run-at-time 0.1 nil #'sz/ewm-status--dbus-refresh))))

(defun sz/ewm-status--unregister-provider (name)
  (when-let ((objects (cdr (assoc name sz/ewm-status--dbus-provider-objects))))
    (dolist (object objects) (ignore-errors (dbus-unregister-object object))))
  (setq sz/ewm-status--dbus-provider-objects
        (cl-delete name sz/ewm-status--dbus-provider-objects :key #'car :test #'equal)))

(defun sz/ewm-status--register-provider (name owner)
  "Rebind NAME's signals to its current unique OWNER."
  (sz/ewm-status--unregister-provider name)
  (condition-case nil
      (let ((objects nil)
            (specs (if (equal name sz/ewm-status--nm)
                       `((:system ,owner nil ,sz/ewm-status--properties "PropertiesChanged"
                                  ,#'sz/ewm-status--dbus-invalidate)
                         (:system ,owner nil "org.freedesktop.NetworkManager.Settings.Connection" "Updated"
                                  ,#'sz/ewm-status--dbus-invalidate)
                         (:system ,owner nil "org.freedesktop.NetworkManager.Settings.Connection" "Removed"
                                  ,#'sz/ewm-status--dbus-invalidate))
                     `((:system ,owner ,sz/ewm-status--power-path ,sz/ewm-status--properties "PropertiesChanged"
                                ,#'sz/ewm-status--dbus-invalidate)))))
        (dolist (spec specs) (push (apply #'dbus-register-signal spec) objects))
        (push (cons name objects) sz/ewm-status--dbus-provider-objects)
        t)
    (error (sz/ewm-status--unregister-provider name) nil)))

(defun sz/ewm-status--dbus-name-owner (name old new)
  (when (and sz/ewm-status-active
             (member name (list sz/ewm-status--nm sz/ewm-status--power)))
    ;; A replacement has the same stale-callback risk as a departure, but only
    ;; the affected provider is retired; its healthy sibling keeps its snapshot.
    (if (equal name sz/ewm-status--nm)
        (progn (setq sz/ewm-status--nm-inflight nil)
               (sz/ewm-status--cancel sz/ewm-status--nm-timeout)
               (setq sz/ewm-status--nm-timeout nil)
               (when (string-empty-p new)
                 (sz/ewm-status--publish 'sz/ewm-status-network "network?")
                 (sz/ewm-status--publish 'sz/ewm-status-wireguard "")))
      (setq sz/ewm-status--power-inflight nil)
      (sz/ewm-status--cancel sz/ewm-status--power-timeout)
      (setq sz/ewm-status--power-timeout nil)
      (when (string-empty-p new) (sz/ewm-status--publish 'sz/ewm-status-power-saver "")))
    (when (and (not (string-empty-p new))
                (not (sz/ewm-status--register-provider name new)))
      (sz/ewm-status--dbus-schedule-registration-retry))
    (when (or (not (equal old new)) (string-empty-p new))
      (sz/ewm-status--dbus-invalidate))))

(defun sz/ewm-status--register-dbus ()
  "Keep owner watches and rebind provider signals to their unique owners."
  (unless sz/ewm-status--dbus-objects
    (condition-case nil
        (dolist (name (list sz/ewm-status--nm sz/ewm-status--power))
          (push (dbus-register-signal :system "org.freedesktop.DBus" "/org/freedesktop/DBus"
                                      "org.freedesktop.DBus" "NameOwnerChanged"
                                      #'sz/ewm-status--dbus-name-owner :arg0 name)
                sz/ewm-status--dbus-objects))
      (error (sz/ewm-status--dbus-schedule-registration-retry))))
  (dolist (name (list sz/ewm-status--nm sz/ewm-status--power))
    (when (not (assoc name sz/ewm-status--dbus-provider-objects))
      (condition-case nil
          (unless (sz/ewm-status--register-provider name (dbus-get-name-owner :system name))
             (sz/ewm-status--dbus-schedule-registration-retry))
        (error (sz/ewm-status--dbus-schedule-registration-retry)))))
  (when (and (= (length sz/ewm-status--dbus-objects) 2)
             (assoc sz/ewm-status--nm sz/ewm-status--dbus-provider-objects)
             (assoc sz/ewm-status--power sz/ewm-status--dbus-provider-objects))
    (sz/ewm-status--cancel sz/ewm-status--dbus-registration-retry)
    (setq sz/ewm-status--dbus-registration-retry nil)))

;;; Native XKB events

(defun sz/ewm-status--handle-event (original event)
  "Cache native XKB EVENTs and delegate every upstream event unchanged."
  (pcase (alist-get 'event event)
    ("layouts" (let ((layouts (alist-get 'layouts event)) (current (alist-get 'current event)))
                 (when (and (or (listp layouts) (vectorp layouts))
                            (integerp current) (<= 0 current) (< current (length layouts)))
                   (sz/ewm-status--publish 'sz/ewm-status-layout (elt layouts current)))))
    ("layout-switched" (sz/ewm-status--publish 'sz/ewm-status-layout (alist-get 'layout event))))
  (funcall original event))

(defun sz/ewm-status-install-event-advice ()
  "Install the narrow XKB event advice before `ewm-start-module'."
  (when (fboundp 'ewm--handle-event)
    (unless (advice-member-p #'sz/ewm-status--handle-event 'ewm--handle-event)
      (advice-add 'ewm--handle-event :around #'sz/ewm-status--handle-event))
    (setq sz/ewm-status--event-advice-installed t)))

;;; Lifecycle

(defun sz/ewm-status-start ()
  "Start EWM-only collectors after the compositor mode is ready."
  (unless sz/ewm-status-active
    (setq sz/ewm-status-active t
          sz/ewm-status--saved-time (list display-time-format display-time-interval display-time-mode)
          sz/ewm-status--saved-battery
          (list battery-mode-line-format battery-mode-line-limit display-battery-mode))
    (sz/ewm-status-install-event-advice)
    (setq display-time-format "%d %b %H:%M" display-time-interval 60
          ;; The builtin default of 100 hides a 100%-Charging battery too.
          battery-mode-line-limit 101)
    (display-time-mode 1)
    (when (fboundp 'sz/ewm-mode-line-keep-clock-last)
      (sz/ewm-mode-line-keep-clock-last))
    (add-hook 'battery-update-functions #'sz/ewm-status--battery-update)
    (display-battery-mode 1)
    (add-hook 'after-save-hook #'sz/ewm-status-timeblock-invalidate)
    (add-hook 'after-revert-hook #'sz/ewm-status-timeblock-invalidate)
    (add-hook 'org-capture-after-finalize-hook #'sz/ewm-status-timeblock-invalidate)
    (add-hook 'org-mode-hook #'sz/ewm-status--org-mode)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (derived-mode-p 'org-mode) (sz/ewm-status--org-mode))))
    (sz/ewm-status--timeblock-refresh)
    (sz/ewm-status--audio-refresh)
    (setq sz/ewm-status--audio-timer (run-at-time 2 2 #'sz/ewm-status--audio-refresh))
    (sz/ewm-status--register-dbus)
    (sz/ewm-status--dbus-refresh)
    ;; The native getter queues a `layouts' event; it does not return state.
    (when (fboundp 'ewm-get-layouts-module) (ewm-get-layouts-module))))

(defun sz/ewm-status-stop ()
  "Stop collectors, child processes, subscriptions, and the XKB advice."
  (when sz/ewm-status-active
    (setq sz/ewm-status-active nil)
    (cl-incf sz/ewm-status--audio-generation)
    (cl-incf sz/ewm-status--dbus-generation)
    (dolist (timer (list sz/ewm-status--audio-timeout sz/ewm-status--audio-timer
                          sz/ewm-status--timeblock-timer sz/ewm-status--timeblock-debounce
                          sz/ewm-status--dbus-debounce sz/ewm-status--dbus-retry
                          sz/ewm-status--dbus-registration-retry sz/ewm-status--dbus-pending-refresh
                          sz/ewm-status--nm-timeout sz/ewm-status--power-timeout))
      (sz/ewm-status--cancel timer))
    (when (process-live-p sz/ewm-status--audio-process) (delete-process sz/ewm-status--audio-process))
    (dolist (object sz/ewm-status--dbus-objects)
      (ignore-errors (dbus-unregister-object object)))
    (dolist (entry sz/ewm-status--dbus-provider-objects)
      (dolist (object (cdr entry)) (ignore-errors (dbus-unregister-object object))))
    (setq sz/ewm-status--dbus-objects nil sz/ewm-status--audio-process nil
          sz/ewm-status--dbus-provider-objects nil sz/ewm-status--dbus-retry nil
          sz/ewm-status--dbus-registration-retry nil sz/ewm-status--dbus-pending-refresh nil
          sz/ewm-status--nm-inflight nil sz/ewm-status--power-inflight nil
          sz/ewm-status--dbus-pending nil)
    (remove-hook 'battery-update-functions #'sz/ewm-status--battery-update)
    (remove-hook 'after-save-hook #'sz/ewm-status-timeblock-invalidate)
    (remove-hook 'after-revert-hook #'sz/ewm-status-timeblock-invalidate)
    (remove-hook 'org-capture-after-finalize-hook #'sz/ewm-status-timeblock-invalidate)
    (remove-hook 'org-mode-hook #'sz/ewm-status--org-mode)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (remove-hook 'after-change-functions #'sz/ewm-status--agenda-change t)))
    (pcase-let ((`(,format ,interval ,enabled) sz/ewm-status--saved-time)
                (`(,battery-format ,battery-limit ,battery-enabled) sz/ewm-status--saved-battery))
      (setq display-time-format format display-time-interval interval
            battery-mode-line-format battery-format battery-mode-line-limit battery-limit)
      (display-time-mode (if enabled 1 -1))
      (display-battery-mode (if battery-enabled 1 -1)))
    (when (and sz/ewm-status--event-advice-installed (fboundp 'ewm--handle-event))
      (advice-remove 'ewm--handle-event #'sz/ewm-status--handle-event)
      (setq sz/ewm-status--event-advice-installed nil))
    (force-mode-line-update t)))

(provide 'sz-ewm-status)
;;; sz-ewm-status.el ends here
