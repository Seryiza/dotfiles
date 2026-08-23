{
  pkgs,
  homeGeneration,
  toplevel,
}:
pkgs.runCommand "waybar-session-profiles-check"
  {
    nativeBuildInputs = [
      pkgs.man-db
      pkgs.python3
      pkgs.systemd
    ];
  }
  ''
    home_files=${homeGeneration}/home-files
    unit_dir="$home_files/.config/systemd/user"
    profile_dir="$home_files/.config/waybar"

    test -f "$profile_dir/mango.json"
    test -f "$profile_dir/generic.json"
    test -f "$unit_dir/waybar@.service"
    test ! -e "$unit_dir/waybar.service"
    test ! -e "$unit_dir/graphical-session.target.wants/waybar.service"
    test ! -e "$unit_dir/tray.target.wants/waybar.service"

    export PROFILE_DIR="$profile_dir"
    ${pkgs.python3}/bin/python <<'PY'
    import json
    import os
    from pathlib import Path

    profile_dir = Path(os.environ["PROFILE_DIR"])
    mango = json.loads((profile_dir / "mango.json").read_text())
    generic = json.loads((profile_dir / "generic.json").read_text())

    generic_modules = {
        "custom/org_timeblock",
        "custom/org_clock",
        "privacy",
        "wireplumber",
        "network",
        "custom/wireguard",
        "battery",
        "clock",
        "tray",
    }

    def displayed_modules(bars):
        return {
            module
            for bar in bars
            for group in ("modules-left", "modules-center", "modules-right")
            for module in bar.get(group, [])
        }

    assert len(generic) == 1, "generic profile must contain one bar"
    assert displayed_modules(generic) == generic_modules
    assert generic[0]["position"] == "top"

    generic_text = json.dumps(generic)
    forbidden = ("mango/", "river/", "machi", "/language", "xkb")
    assert not any(value in generic_text.lower() for value in forbidden)

    assert len(mango) == 2, "Mango profile must preserve both bars"
    assert displayed_modules(mango) == generic_modules | {
        "mango/window",
        "mango/language",
        "mango/workspaces",
    }
    assert mango[1]["position"] == "bottom"
    assert {"mango/taskbar", "sway/language", "mango/layout"} <= mango[0].keys()
    PY

    for instance in mango river sway; do
      link="$unit_dir/wayland-session@$instance.target.wants/waybar@$instance.service"
      test -L "$link"
      test "$(readlink -f "$link")" = "$(readlink -f "$unit_dir/waybar@.service")"
    done

    grep -F 'After=wayland-session@%i.target graphical-session.target' "$unit_dir/waybar@.service"
    grep -F 'BindsTo=wayland-session@%i.target' "$unit_dir/waybar@.service"
    grep -F 'ConditionEnvironment=WAYLAND_DISPLAY' "$unit_dir/waybar@.service"
    grep -F '%i' "$unit_dir/waybar@.service"
    ! grep -E 'WAYBAR_(PROFILE|COMPOSITOR)|SWAYSOCK|socket' "$unit_dir/waybar@.service"

    launcher="$(${pkgs.gnused}/bin/sed -n 's|^ExecStart=\([^ ]*\) %i$|\1|p' "$unit_dir/waybar@.service")"
    test -x "$launcher"
    grep -F 'case "$1" in' "$launcher"
    grep -F 'mango) profile=mango ;;' "$launcher"
    grep -F 'river) profile=generic ;;' "$launcher"
    grep -F 'sway) profile=generic ;;' "$launcher"
    ! grep -E 'WAYBAR_(PROFILE|COMPOSITOR)|SWAYSOCK|WAYLAND_DISPLAY|socket' "$launcher"

    mkdir -p "$TMPDIR/runtime" "$TMPDIR/verify-units"
    for instance in mango river sway; do
      waybar_instance="$unit_dir/wayland-session@$instance.target.wants/waybar@$instance.service"
      session_target="$TMPDIR/verify-units/wayland-session@$instance.target"
      ln -s "${toplevel}/etc/systemd/user/wayland-session@.target" "$session_target"

      MANPATH="${toplevel}/sw/share/man" \
        XDG_RUNTIME_DIR="$TMPDIR/runtime" \
        SYSTEMD_UNIT_PATH="$TMPDIR/verify-units:$unit_dir:${toplevel}/etc/systemd/user" \
        ${pkgs.systemd}/bin/systemd-analyze --user verify \
          "$waybar_instance" \
          "$session_target" \
          "${toplevel}/etc/systemd/user/wayland-session@.target" \
          "${toplevel}/etc/systemd/user/wayland-session-pre@.target" \
          "${toplevel}/etc/systemd/user/wayland-session-envelope@.target" \
          "${toplevel}/etc/systemd/user/wayland-wm@.service" \
          "${toplevel}/etc/systemd/user/wayland-wm-env@.service"
    done

    touch "$out"
  ''
