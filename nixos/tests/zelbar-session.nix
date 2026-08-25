{
  pkgs,
  homeGeneration,
  toplevel,
  zelbar,
  river-zelbar-status,
  machi,
}:
pkgs.runCommand "zelbar-session-check"
  {
    nativeBuildInputs = [
      pkgs.man-db
      pkgs.systemd
    ];
  }
  ''
    home_files=${homeGeneration}/home-files
    unit_dir="$home_files/.config/systemd/user"
    unit="$unit_dir/zelbar-river.service"
    river_wants="$unit_dir/wayland-session@river.target.wants"
    river_link="$river_wants/zelbar-river.service"

    test -f "$unit"
    test -L "$river_link"
    test "$(readlink -f "$river_link")" = "$(readlink -f "$unit")"
    test ! -e "$river_wants/waybar@river.service"

    test "$(find "$unit_dir" -type l -path '*.target.wants/zelbar*.service' | wc -l)" -eq 1
    test "$(find "$river_wants" -maxdepth 1 -type l -name '*.service' | wc -l)" -eq 1

    grep -F 'After=wayland-session@river.target graphical-session.target' "$unit"
    grep -F 'BindsTo=wayland-session@river.target' "$unit"
    grep -F 'ConditionEnvironment=WAYLAND_DISPLAY' "$unit"
    grep -F 'Type=exec' "$unit"
    grep -F 'Restart=on-failure' "$unit"
    grep -F 'RestartSec=2' "$unit"
    grep -F 'KillMode=control-group' "$unit"
    grep -F 'TimeoutStopSec=3' "$unit"
    grep -F 'Slice=app-graphical.slice' "$unit"
    grep -F 'WantedBy=wayland-session@river.target' "$unit"

    launcher="$(${pkgs.gnused}/bin/sed -n 's|^ExecStart=\([^ ]*\)$|\1|p' "$unit")"
    test -x "$launcher"
    grep -F 'exec ${river-zelbar-status}/bin/river-zelbar-status' "$launcher"
    grep -F -- '--zelbar ${zelbar}/bin/zelbar' "$launcher"
    grep -F -- '--machictl ${machi}/bin/machictl' "$launcher"

    status_main=${river-zelbar-status.src}/cmd/river-zelbar-status/main.go
    grep -F 'const output = "eDP-1"' "$status_main"
    grep -F '"-L", "1"' "$status_main"
    grep -F '"-g", "0:20"' "$status_main"
    grep -F '"-fn", "Iosevka,Noto Color Emoji"' "$status_main"
    grep -F '"-B", "0xFFFFFFFF"' "$status_main"
    grep -F '"-F", "0x000000FF"' "$status_main"

    mkdir -p "$TMPDIR/runtime" "$TMPDIR/verify-units"
    session_target="$TMPDIR/verify-units/wayland-session@river.target"
    ln -s "${toplevel}/etc/systemd/user/wayland-session@.target" "$session_target"

    MANPATH="${toplevel}/sw/share/man" \
      XDG_RUNTIME_DIR="$TMPDIR/runtime" \
      SYSTEMD_UNIT_PATH="$TMPDIR/verify-units:$unit_dir:${toplevel}/etc/systemd/user" \
      ${pkgs.systemd}/bin/systemd-analyze --user verify \
        "$unit" \
        "$session_target" \
        "${toplevel}/etc/systemd/user/wayland-session@.target" \
        "${toplevel}/etc/systemd/user/wayland-session-pre@.target" \
        "${toplevel}/etc/systemd/user/wayland-session-envelope@.target" \
        "${toplevel}/etc/systemd/user/wayland-wm@.service" \
        "${toplevel}/etc/systemd/user/wayland-wm-env@.service"

    touch "$out"
  ''
