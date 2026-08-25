# River Machi/XKB live acceptance

Run these checks inside the active River 0.4.8 session after the status module is wired into `zelbar-river.service`.

1. Follow the module journal while watching the right-hand layout field and left-hand Machi fields:

   ```sh
   journalctl --user -fu zelbar-river.service
   ```

2. Press `Ctrl+Space` repeatedly. The Zelbar layout text must alternate promptly between `us` and `ru`. With two physical keyboards attached, switch them to different groups and verify `mixed`; remove one and verify the remaining keyboard's layout.
3. In another terminal, inspect the authoritative snapshots:

   ```sh
   machictl -watch eDP-1
   ```

   Create/switch Machi workspaces and panels, toggle single/split mode, focus windows, and change a window title. Zelbar must update `W`, `P`, mode, window count, and title from each complete snapshot. JSON indices remain zero-based while the displayed `W` and `P` indices are one-based.
4. Stop `machictl`'s Machi server or terminate River. The status module must fail and systemd must perform one bounded graph restart; a Wayland disconnect must not leave the old module or watcher alive.
