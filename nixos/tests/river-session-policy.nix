{
  pkgs,
  homeGeneration,
  toplevel,
  river,
  machi,
  channel,
}:
pkgs.runCommand "river-session-policy-check"
  {
    nativeBuildInputs = [
      pkgs.libxkbcommon
      pkgs.python3
    ];
  }
  ''
    sessions=${toplevel}/sw/share/wayland-sessions
    home_files=${homeGeneration}/home-files

    test "${river.version}" = 0.4.8
    test "${machi.rev}" = 65a0fc12f2796f41f4c9cbb7e034aaa137009b01
    test "${channel.version}" = 0.4.1
    test "${channel.rev}" = 4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446

    test -f "$sessions/00-sway-uwsm.desktop"
    test -f "$sessions/mango-uwsm.desktop"
    test -f "$sessions/river-uwsm.desktop"
    test "$(${pkgs.findutils}/bin/find -L "$sessions" -maxdepth 1 -type f -iname '*river*.desktop' | wc -l)" -eq 1
    grep -F 'UWSM' "$sessions/river-uwsm.desktop"
    grep -F 'uwsm start' "$sessions/river-uwsm.desktop"
    ! test -e "$sessions/river.desktop"

    river_wrapper=$(readlink -f ${toplevel}/sw/bin/river)
    grep -F -- '-c ' "$river_wrapper"
    river_init=$(${pkgs.gnused}/bin/sed -n 's/.*-c \([^ ]*\).*/\1/p' "$river_wrapper")
    test -x "$river_init"
    test "$(grep -Ec '(^|/)machi([[:space:]]|$)' "$river_init")" -eq 1
    test "$(grep -Ec '(^|/)channel([[:space:]]|$)' "$river_init")" -eq 1
    ! grep -F 'kwim' "$river_init"
    grep -F 'set -eu' "$river_init"
    grep -F 'kill -0 "$machi_pid" "$channel_pid"' "$river_init"
    grep -F 'uwsm finalize' "$river_init"
    grep -F 'wlr-randr' "$river_init"
    grep -F -- '--output eDP-1 --mode 2560x1600@240Hz --pos 0,0 --scale 2' "$river_init"
    ! grep -E -- '--output (DP|HDMI|USB|DVI)-' "$river_init"

    machi_config="$home_files/.config/machi/machi.ini"
    channel_config="$home_files/.config/river/config.rh"
    test -f "$machi_config"
    test -f "$channel_config"

    for section in \
      '[keybindings.workspace]' \
      '[keybindings.panel]' \
      '[keybindings.window]' \
      '[keybindings.spawn]'; do
      grep -F "$section" "$machi_config"
    done
    grep -F 'uwsm stop=super+shift+e' "$machi_config"
    grep -F 'close=super+u' "$machi_config"
    grep -F 'toggle-fullscreen=super+f' "$machi_config"
    grep -F 'toggle-split-view=super+s' "$machi_config"
    grep -F 'alacritty=super+y' "$machi_config"
    grep -F 'swaylock -c 000000=super+escape' "$machi_config"
    grep -F "wmenu-run -i -b -l 10 -f 'Iosevka 14'=super+n" "$machi_config"
    grep -F 'emacsclient -c=super+m' "$machi_config"
    grep -F 'firefox=super+b' "$machi_config"
    grep -F 'run-work-browser=super+shift+b' "$machi_config"
    grep -F 'run-enpass-x11=super+e' "$machi_config"
    grep -F 'grim -g "$(slurp)" - | wl-copy=print' "$machi_config"
    grep -F 'grim -g "$(slurp)"=ctrl+print' "$machi_config"
    grep -F 'grim - | wl-copy | drawing -c=shift+print' "$machi_config"
    grep -F 'increase-backlight && display-backlight=XF86MonBrightnessUp' "$machi_config"
    grep -F 'decrease-backlight && display-backlight=XF86MonBrightnessDown' "$machi_config"
    grep -F 'playerctl play-pause=XF86AudioPlay' "$machi_config"
    grep -F 'increase-current-volume && display-current-volume=XF86AudioRaiseVolume' "$machi_config"
    grep -F 'decrease-current-volume && display-current-volume=XF86AudioLowerVolume' "$machi_config"
    grep -F 'toggle-microphone-mute && display-current-microphone=XF86AudioMicMute' "$machi_config"
    grep -F 'toggle-microphone-mute && display-current-microphone=XF86HomePage' "$machi_config"
    grep -F 'toggle-audio-mute && display-current-volume=XF86AudioMute' "$machi_config"
    grep -F 'toggle-audio-mute && display-current-volume=super+shift+m' "$machi_config"

    grep -F 'layout us,ru' "$channel_config"
    grep -F 'options grp:ctrl_space_toggle,custom:types,custom:positional-latin-shortcuts' "$channel_config"
    ! grep -F 'ctrl:nocaps' "$channel_config"
    grep -F 'tap_to_click true' "$channel_config"
    grep -F 'natural_scroll true' "$channel_config"
    grep -F 'disable_while_typing true' "$channel_config"
    grep -F 'tap_button_map lrm' "$channel_config"
    grep -F 'middle_mouse_emulation true' "$channel_config"

    mango_config="$home_files/.config/mango/config.conf"
    sway_config="$home_files/.config/sway/config"
    grep -F 'xkb_rules_options = grp:ctrl_space_toggle' "$mango_config"
    grep -F 'xkb_options grp:ctrl_space_toggle' "$sway_config"
    ! grep -F 'ctrl:nocaps' "$mango_config" "$sway_config"

    xkb_root="$home_files/.config/xkb"
    test -f "$xkb_root/rules/evdev"
    test -f "$xkb_root/types/custom"
    test -f "$xkb_root/symbols/custom"
    grep -F '! include %S/evdev' "$xkb_root/rules/evdev"
    grep -F 'custom:types' "$xkb_root/rules/evdev"
    grep -F 'custom:positional-latin-shortcuts' "$xkb_root/rules/evdev"
    grep -F 'type "POSITIONAL_LATIN_SHORTCUT"' "$xkb_root/types/custom"
    ! grep -E 'Mod5|LevelThree' "$xkb_root/types/custom"
    test "$(grep -c 'type\[Group1\] = "POSITIONAL_LATIN_SHORTCUT"' "$xkb_root/symbols/custom")" -eq 26

    ${pkgs.libxkbcommon}/bin/xkbcli compile-keymap \
      --include "$xkb_root" \
      --include-defaults \
      --test \
      --layout us,ru \
      --options grp:ctrl_space_toggle,custom:types,custom:positional-latin-shortcuts \
      >/dev/null

    xremap_unit="$home_files/.config/systemd/user/xremap.service"
    xremap_config=$(${pkgs.gnused}/bin/sed -n 's|^ExecStart=.* \(/nix/store/[^ ]*-config.yml\)$|\1|p' "$xremap_unit")
    test -f "$xremap_config"
    grep -F 'CapsLock' "$xremap_config"
    grep -F 'Control_L' "$xremap_config"
    grep -F 'KEY_F23' "$xremap_config"
    grep -F 'C-KEY_LEFTBRACE' "$xremap_config"

    river_wants="$home_files/.config/systemd/user/wayland-session@river.target.wants"
    river_zelbar="$river_wants/zelbar-river.service"
    river_waybar="$river_wants/waybar@river.service"
    test -L "$river_zelbar"
    test ! -e "$river_waybar"
    test "$(find "$river_wants" -maxdepth 1 -type l -name '*.service' | wc -l)" -eq 1
    grep -F 'BindsTo=wayland-session@river.target' "$river_zelbar"

    touch "$out"
  ''
