# River Zelbar live acceptance on `yuri-alpha`

Automated checks prove Wayland buffer scale, SHM dimensions, damage and commit ordering. Pixel sharpness on the real eDP panel remains a mandatory human gate.

## 1. Build and rollback-protected activation

From the repository root, keep the currently running system path and build the candidate before changing the session:

```sh
previous_system=$(readlink -f /run/current-system)
printf 'rollback path: %s\n' "$previous_system"
nix flake check
candidate=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.yuri-alpha.config.system.build.toplevel)
printf 'candidate path: %s\n' "$candidate"
```

Use a non-persistent test activation first. Do not use `switch` before visual acceptance:

```sh
sudo nixos-rebuild test --flake .#yuri-alpha
```

If the graphical session or bar becomes unusable, activate the captured system from a TTY, or reboot (the `test` command does not change the boot default):

```sh
sudo "$previous_system/bin/switch-to-configuration" test
```

After every gate below passes, make the candidate persistent:

```sh
sudo nixos-rebuild switch --flake .#yuri-alpha
```

## 2. Confirm the normal session contract

Log into a fresh River session and record the output and renderer command:

```sh
wlr-randr
pgrep -af 'river-zelbar-status|/zelbar( |$)'
systemctl --user status zelbar-river.service --no-pager
```

Expected facts:

- `eDP-1` is 2560×1600 with scale 2;
- exactly one `river-zelbar-status` and one child Zelbar exist;
- Zelbar still has `-o eDP-1 -L 1 -g 0:20` and the existing font/color arguments;
- `-L 1` remains the layer-shell layer selector; it is not a display-scale flag.

## 3. Compare scale 1 and scale 2

First exercise a live 2→1→2 transition without restarting the service. This checks runtime `wl_output.scale` handling rather than only startup:

```sh
wlr-randr --output eDP-1 --scale 1
sleep 2
grim -o eDP-1 /tmp/zelbar-scale-1.png

wlr-randr --output eDP-1 --scale 2
sleep 2
grim -o eDP-1 /tmp/zelbar-scale-2.png
```

At both scales inspect Iosevka vertical stems, diagonals, Cyrillic and emoji at 1:1 image zoom. Accept only if:

- text edges are crisp, without the fuzzy halo or doubled pixels from compositor upscaling;
- the bar stays flush against the top edge;
- its height remains 20 logical pixels (20 physical pixels at scale 1, 40 physical pixels at scale 2);
- baseline, background, lines and borders scale together;
- no glyph, top/bottom edge or right-aligned status is clipped;
- the bar does not move or reserve 40 logical pixels at scale 2.

Leave the output at its normal scale after the comparison:

```sh
wlr-randr --output eDP-1 --scale 2
```

### Optional protocol capture

This records the same seams checked headlessly. Enable tracing only briefly because it is verbose:

```sh
since=$(date --iso-8601=seconds)
systemctl --user set-environment WAYLAND_DEBUG=client
systemctl --user restart zelbar-river.service
sleep 2
journalctl --user -u zelbar-river.service --since "$since" --no-pager \
  | grep -E 'configure\(|create_buffer\(|set_buffer_scale\(|damage_buffer\(|attach\(|commit\('
systemctl --user unset-environment WAYLAND_DEBUG
systemctl --user restart zelbar-river.service
```

At scale 2 the trace must include a 20-logical-pixel layer configure, `set_buffer_scale(2)`, a 40-physical-pixel SHM buffer, full-buffer damage, attach and then commit. For the 2560-wide physical mode, the expected full-width buffer is 2560×40.

## 4. Content, positioning and clipping

Follow the journal while exercising status changes:

```sh
journalctl --user -fu zelbar-river.service
```

In another terminal:

```sh
machictl -watch eDP-1
```

Verify all of the following:

1. Press `Ctrl+Space` repeatedly. The layout text alternates promptly between `us` and `ru`. If two keyboards are available, differing groups show `mixed`; removing one restores the remaining layout.
2. Create/switch Machi workspaces and panels, then focus windows and change a title. The left side shows only the current title, offset 4 logical pixels from the screen edge. The right side shows one-based `W` and `P` modules separated from each other and subsequent modules by ` | `; mode and window count are not displayed.
3. Check Org, WireGuard, audio, network, battery and minute-clock fields against their sources.
4. Use long ASCII, Cyrillic, emoji and combining-mark titles, including literal `%{}`. Text must neither inject markup nor clip vertically; optional empty fields must not leave duplicate separators.

## 5. Restart and session lifecycle

Restart the graph and confirm it returns once, without stale children or high CPU:

```sh
before=$(systemctl --user show zelbar-river.service -p NRestarts --value)
systemctl --user restart zelbar-river.service
sleep 3
systemctl --user status zelbar-river.service --no-pager
pgrep -af 'river-zelbar-status|/zelbar( |$)'
after=$(systemctl --user show zelbar-river.service -p NRestarts --value)
printf 'NRestarts: %s -> %s\n' "$before" "$after"
```

Exercise `Restart=on-failure`, not only a clean administrative restart. First kill the status main process and verify systemd replaces the entire graph exactly once:

```sh
main_before=$(systemctl --user show zelbar-river.service -p MainPID --value)
children_before=$(pgrep -P "$main_before" || true)
restarts_before=$(systemctl --user show zelbar-river.service -p NRestarts --value)
kill -KILL "$main_before"

for _ in $(seq 1 50); do
  main_after=$(systemctl --user show zelbar-river.service -p MainPID --value)
  if systemctl --user is-active --quiet zelbar-river.service \
    && [ "$main_after" -gt 0 ] && [ "$main_after" != "$main_before" ]; then
    break
  fi
  sleep 0.1
done

restarts_after=$(systemctl --user show zelbar-river.service -p NRestarts --value)
test "$restarts_after" -eq "$((restarts_before + 1))"
! kill -0 "$main_before" 2>/dev/null
for pid in $children_before; do ! kill -0 "$pid" 2>/dev/null; done
pgrep -af 'river-zelbar-status|/zelbar( |$)|machictl -watch'
ps -o pid,ppid,stat,%cpu,cmd -p "$main_after" $(pgrep -P "$main_after" || true)
journalctl --user -u zelbar-river.service --since '-30 seconds' --no-pager
```

Repeat the failure through the authoritative Machi watcher seam. Killing `machictl -watch eDP-1` must make the status module fail, then produce one new bounded graph restart:

```sh
main_before=$main_after
watcher=$(pgrep -P "$main_before" -x machictl | head -1)
test -n "$watcher"
restarts_before=$restarts_after
kill -KILL "$watcher"

for _ in $(seq 1 50); do
  main_after=$(systemctl --user show zelbar-river.service -p MainPID --value)
  [ "$main_after" -gt 0 ] && [ "$main_after" != "$main_before" ] && break
  sleep 0.1
done

restarts_after=$(systemctl --user show zelbar-river.service -p NRestarts --value)
test "$restarts_after" -eq "$((restarts_before + 1))"
! kill -0 "$watcher" 2>/dev/null
pgrep -af 'river-zelbar-status|/zelbar( |$)|machictl -watch'
```

Reject the build if old PIDs survive, restart counts jump by more than one, the journal loops continuously, or any replacement process remains at sustained high CPU.

Then perform these human-driven gates:

1. Suspend and resume; verify sharpness, top positioning and scale-2 clipping again.
2. Log out of River completely (`uwsm stop` or the normal logout action).
3. From a TTY, confirm no old `river-zelbar-status` or Zelbar remains.
4. Log into a fresh River session and repeat `wlr-randr`, `pgrep` and the scale-2 screenshot.
5. Log into Mango and Sway once and confirm their existing Waybar setup is unchanged.

Do not mark issue 08 or the feature accepted until the real scale-1/scale-2 screenshots and the restart/logout/fresh-session lifecycle all pass.
