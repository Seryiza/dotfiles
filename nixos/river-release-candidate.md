# River release candidate handoff

Generated: 2026-08-23

## Candidate

- Configuration revision: `e613665623fd7ed0b246fef2d9084ed4da1d4d41`
- NixOS toplevel / bootable generation artifact: `/nix/store/r1g8m7z5jhihh881z6r9q64lnv7385f1-nixos-system-yuri-alpha-26.05.20260817.0dd31db`
- Home Manager generation inspected by the checks: `/nix/store/qbfpdj40kfrfcd2a7y84wvn8x1hx7lq8-home-manager-generation`
- Boot label: `NixOS Yarara 26.05.20260817.0dd31db (Linux 7.1.8)`
- Kernel: `/nix/store/qnabzsdp1cnqgfybf0xr47kzbcz9f2v0-linux-7.1.8/bzImage`
- Initrd: `/nix/store/dbnm6caihvvyl4lyv5iib3phqsh13qx2-initrd-linux-7.1.8/initrd`

The immutable candidate generation is identified by the toplevel store path above. Its local system-profile generation number is assigned only when a human installs it; that mutable sequence number is not part of the candidate identity. The candidate contains `boot.json`, `kernel`, `initrd`, `init`, and an executable `bin/switch-to-configuration`. It was built but not installed or activated by the automated verification.

### Package provenance

- Stable nixpkgs: `a82ccc39b39b621151d6732718e3e250109076fa`
- Narrow unstable nixpkgs input: `e5bdc4a41d4c072fe1e3787eaa0320a384741d44`
- River 0.4.8: `/nix/store/xfllwqwr6z7zzhadn3piqlnsxnljrs8n-river-0.4.8`
- Machi `65a0fc12f2796f41f4c9cbb7e034aaa137009b01`: `/nix/store/i9fnad0dyn0wz4g40yrcy1lr8p7zrmkv-machi-0.5.0-dev-65a0fc1`
- `channel` 0.4.1, revision `4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446`: `/nix/store/khpqbac0jwi5qdhn8ihq04hv2ci8qpcf-channel-0.4.1`

## Automated verification completed

The following commands passed against the candidate revision:

```console
nix build --no-link .#river .#machi .#channel
nix build --no-link \
  .#checks.x86_64-linux.river-session-policy \
  .#checks.x86_64-linux.waybar-session-profiles \
  .#checks.x86_64-linux.soteria-session-agent
nix build --no-link .#nixosConfigurations.yuri-alpha.config.system.build.toplevel
nix flake check --print-build-logs
```

Check artifacts:

- River/session/package policy: `/nix/store/bnryxm1w1pdcrrhsks65ca62lsr2xc9w-river-session-policy-check`
- Waybar profiles and generated systemd units: `/nix/store/yasacyabafl2pwkdv2jz0dm3is8n29mx-waybar-session-profiles-check`
- Soteria lifecycle, exclusivity, and generated systemd units: `/nix/store/kdfz5q1x9nrha4bpx8n893xsi8pbf0kd-soteria-session-agent-check`

The evaluated display-manager session set is exactly:

- `00-sway-uwsm.desktop`: `Sway`
- `mango-uwsm.desktop`: `Mango (UWSM)`
- `river-uwsm.desktop`: `River (UWSM)`

There is one River entry, it launches through `uwsm start`, and no plain `river.desktop` exists. Waybar uses `waybar@mango.service`, `waybar@river.service`, and `waybar@sway.service`, all backed by the same template and bound to their matching `wayland-session@<name>.target`. Soteria is the only configured graphical polkit activation path and is bound to `graphical-session.target`.

No automated blocker remains.

## Human installation and runtime checklist

Do not switch the running graphical session to this candidate. From a TTY or an existing stable session, install the exact already-built artifact for the next boot:

```bash
sudo nix-env -p /nix/var/nix/profiles/system \
  --set /nix/store/r1g8m7z5jhihh881z6r9q64lnv7385f1-nixos-system-yuri-alpha-26.05.20260817.0dd31db
sudo /nix/store/r1g8m7z5jhihh881z6r9q64lnv7385f1-nixos-system-yuri-alpha-26.05.20260817.0dd31db/bin/switch-to-configuration boot
```

Record the assigned generation number before reboot:

```bash
readlink -f /nix/var/nix/profiles/system
sudo nix-env --list-generations -p /nix/var/nix/profiles/system
```

Then complete issue 07 without treating any item below as already verified:

1. Reboot into the candidate generation and log into Mango first.
2. Confirm Mango, River, and Sway remain selectable; then select `River (UWSM)`.
3. Verify UWSM environment finalization, normal and abnormal exit, `uwsm stop`, and repeated login/logout without stale processes or environment.
4. Verify exactly one matching Waybar process and one Soteria agent in each session, including a real graphical polkit prompt.
5. Verify keyboard, touchpad, xremap, `eDP-1` mode/scale, DPMS, lock, idle, suspend/resume, lock-before-suspend, and media idle inhibition.
6. Confirm the automatic `wlr-randr` policy runs on every River login without manual recovery.
7. Confirm configured and hotplug-discovered output coordinates remain nonnegative and within River's Xwayland coordinate bounds.
8. Verify portals, screen sharing, privacy indication, screenshots, clipboard/Drawing, notifications, and hardware/media controls.
9. Smoke-test required native Wayland, Xwayland, Electron, browser, tray, activation, focus, transient, Picture-in-Picture, decorated, and layer-shell workflows.
10. Confirm AMD is the primary renderer and visibly run `nvidia-offload vkcube` on NVIDIA.
11. Complete at least one working-day River pilot.

## Rollback

Generation 900 is the tested rollback baseline:

- Store path: `/nix/store/gfbas27xdpy4qam2g03bpgsc5isigjk5-nixos-system-yuri-alpha-26.05.20260817.0dd31db`
- Evidence: it was the system booted at handoff time (`/run/booted-system`) and its kernel, initrd, `boot.json`, and `switch-to-configuration` were present.

If the candidate fails, select generation 900 from GRUB. Mango and Sway are also retained as session-level fallbacks. If graphical logout is stuck, use a TTY to stop the UWSM session or reboot; do not remove Mango during this pilot.

## Verification boundary

Only builds, evaluated artifacts, package provenance, session identities, generated profiles, and generated systemd units were checked automatically. No production session was activated. Login, display behavior, input devices, lock, suspend/resume, portals, graphical prompts, applications, GPU rendering, and the working-day pilot remain physical human acceptance work.
