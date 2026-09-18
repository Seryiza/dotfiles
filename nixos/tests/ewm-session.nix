{
  pkgs,
  homeGeneration,
  ewmSystem,
  ewmPortalConfig,
  xwaylandSatellite,
  hasSatelliteSystemdPackage,
  bashrc,
  emacsPackage,
}:
assert !hasSatelliteSystemdPackage;
pkgs.runCommand "ewm-session-contract-check"
  { nativeBuildInputs = [ emacsPackage pkgs.desktop-file-utils pkgs.systemd ]; }
  ''
    sessions=${ewmSystem}/share/wayland-sessions
    home_files=${homeGeneration}/home-files
    home_path=${homeGeneration}/home-path
    unit_dir="$home_files/.config/systemd/user"

    test -f "$sessions/ewm.desktop"
    grep -Fx 'Exec=ewm-session' "$sessions/ewm.desktop"
    ! grep -E 'uwsm|UWSM' "$sessions/ewm.desktop"

    launcher=${ewmSystem}/bin/ewm-launch
    test -x "$launcher"
    grep -F -- '--fg-daemon' "$launcher"
    grep -F "(require 'ewm)" "$launcher"
    grep -F '(ewm-start-module)' "$launcher"

    test -f ${ewmSystem}/lib/systemd/user/ewm.service
    test -f ${ewmSystem}/lib/systemd/user/ewm-shutdown.target
    grep -F 'ExecStart=/run/current-system/sw/bin/ewm-launch' ${ewmSystem}/lib/systemd/user/ewm.service
    grep -F 'BindsTo=graphical-session.target' ${ewmSystem}/lib/systemd/user/ewm.service

    ${emacsPackage}/bin/emacs --batch --eval "(require 'ewm)"

    emacs_unit="$unit_dir/emacs.service"
    test -f "$emacs_unit"
    grep -F 'ConditionEnvironment=!XDG_CURRENT_DESKTOP=ewm' "$emacs_unit"
    ! test -e "$unit_dir/emacs.socket"
    grep -F -- '--fg-daemon' "$emacs_unit"

    session_vars="$home_path/etc/profile.d/hm-session-vars.sh"
    editor="${emacsPackage}/bin/emacsclient --reuse-frame"
    grep -Fx "export EDITOR=\"$editor\"" "$session_vars"
    grep -Fx "export VISUAL=\"$editor\"" "$session_vars"
    grep -Fx "export SUDO_EDITOR=\"$editor\"" "$session_vars"

    fresh_editor=$(env -i \
      EDITOR="$editor" \
      HOME="$TMPDIR/home" \
      PATH="${pkgs.bash}/bin:${pkgs.ncurses}/bin" \
      TERM=dumb \
      ${pkgs.bash}/bin/bash --noprofile --rcfile ${bashrc} -ic 'printf %s "$EDITOR"' 2>/dev/null)
    test "$fresh_editor" = "$editor"

    mime_desktop="$home_path/share/applications/emacsclient.desktop"
    grep -Fx "Exec=$editor %F" "$mime_desktop"
    grep -Fx 'NoDisplay=true' "$mime_desktop"

    client_frame_desktop="$home_path/share/applications/emacs-client-frame.desktop"
    grep -Fx 'Name=New Emacs Client Frame' "$client_frame_desktop"
    grep -Fx "Exec=${emacsPackage}/bin/emacsclient -c" "$client_frame_desktop"
    ! grep -F 'NoDisplay=' "$client_frame_desktop"

    workspace_desktop="$home_path/share/applications/emacs-ewm-workspace.desktop"
    grep -Fx 'Name=New EWM Workspace' "$workspace_desktop"
    grep -Fx "Exec=${emacsPackage}/bin/emacsclient --eval \"(ewm-frame-new)\"" "$workspace_desktop"
    ! grep -F 'NoDisplay=' "$workspace_desktop"

    standalone_desktop="$home_path/share/applications/emacs.desktop"
    grep -Fx 'Name=Emacs — Separate Process' "$standalone_desktop"
    grep -Fx "Exec=${emacsPackage}/bin/emacs" "$standalone_desktop"
    ! grep -F 'MimeType=' "$standalone_desktop"
    ! grep -F 'NoDisplay=' "$standalone_desktop"

    ${pkgs.desktop-file-utils}/bin/desktop-file-validate \
      "$mime_desktop" \
      "$client_frame_desktop" \
      "$workspace_desktop" \
      "$standalone_desktop"

    mimeapps="$home_files/.config/mimeapps.list"
    for mime in text/plain text/markdown text/x-shellscript application/json application/xml; do
      grep -Fx "$mime=emacsclient.desktop" "$mimeapps"
    done

    ewm_idle="$unit_dir/swayidle-ewm.service"
    test -f "$ewm_idle"
    ewm_wayland=$(grep -Fx 'ConditionEnvironment=WAYLAND_DISPLAY' "$ewm_idle")
    ewm_desktop=$(grep -Fx 'ConditionEnvironment=XDG_CURRENT_DESKTOP=ewm' "$ewm_idle")
    mkdir -p "$TMPDIR/runtime"
    env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=ewm \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$ewm_wayland" "$ewm_desktop"
    ! env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=river \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$ewm_wayland" "$ewm_desktop"
    ! env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" XDG_CURRENT_DESKTOP=ewm \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$ewm_wayland" "$ewm_desktop"
    grep -F 'timeout 600' "$ewm_idle"
    grep -F 'before-sleep' "$ewm_idle"
    ! grep -F 'wlopm' "$ewm_idle"
    river_idle="$unit_dir/swayidle.service"
    river_wayland=$(grep -Fx 'ConditionEnvironment=WAYLAND_DISPLAY' "$river_idle")
    river_desktop=$(grep -Fx 'ConditionEnvironment=!XDG_CURRENT_DESKTOP=ewm' "$river_idle")
    env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=river \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$river_wayland" "$river_desktop"
    ! env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=ewm \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$river_wayland" "$river_desktop"
    ! env -i XDG_RUNTIME_DIR="$TMPDIR/runtime" XDG_CURRENT_DESKTOP=river \
      ${pkgs.systemd}/bin/systemd-analyze --user condition "$river_wayland" "$river_desktop"

    ! test -e "$unit_dir/xwayland-satellite.service"
    ! test -e "$unit_dir/graphical-session.target.wants/xwayland-satellite.service"
    test -x ${xwaylandSatellite}/bin/xwayland-satellite
    ${xwaylandSatellite}/bin/xwayland-satellite --test-listenfd-support

    grep -Fx 'default=gnome;gtk' ${ewmPortalConfig}
    grep -Fx 'org.freedesktop.impl.portal.Access=gtk' ${ewmPortalConfig}
    grep -Fx 'org.freedesktop.impl.portal.Notification=gtk' ${ewmPortalConfig}
    ! grep -F 'org.freedesktop.impl.portal.Secret=' ${ewmPortalConfig}

    touch "$out"
  ''
