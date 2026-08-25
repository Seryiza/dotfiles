# River + Machi + Waybar migration

Status: wontfix

Archive note (2026-08-25): this document preserves the original Waybar-based River migration plan and its implementation history. The later Zelbar migration superseded its remaining runtime acceptance and Mango-retirement chain; active River status-panel requirements and human gates now live under `.scratch/river-machi-zelbar/`. Tickets 07–10 are therefore non-actionable, while statuses on completed implementation tickets remain as their original dispatch roles.

## Problem Statement

Пользователь `seryiza` на хосте `yuri-alpha` хочет перейти с Mango на современную немонолитную связку River + Machi, сохранив существующий UWSM lifecycle, sysc-greet, Waybar и повседневные desktop services. Текущая конфигурация связывает input policy, output policy, window-management semantics и compositor-specific Waybar modules с Mango, а интеграции Waybar `river/*` рассчитаны на river-classic и несовместимы с выбранной архитектурой River 0.4+.

Миграция не должна рискованно заменять рабочую графическую сессию: Mango должен оставаться доступным во время pilot, Sway — независимым fallback, а основной стабильный NixOS package set не должен глобально переходить на unstable. Новая сессия должна быть воспроизводимой, корректно управляться UWSM, сохранять generic Waybar functionality и проходить реальную проверку login/logout, suspend/resume, portal, lock, input, output, Wayland/Xwayland и hybrid-GPU behavior.

## Solution

Добавить River 0.4.8 и закреплённый Machi как параллельную UWSM-managed login session. Window-management policy передать Machi, input policy — единственному экземпляру `channel` 0.4.1, а настройку встроенного output — автоматически запускаемому `wlr-randr` one-shot. Сохранить Xwayland и существующие независимые desktop services.

Разделить Waybar на неизменный Mango profile и generic-only profile для River и Sway. Запускать ровно один Waybar через compositor-specific instances одного systemd template, используя UWSM unit identity вместо custom environment marker или обнаружения socket. Добавить Soteria как единственный graphical polkit authentication agent и связать его lifecycle с graphical session.

Проводить миграцию поэтапно: воспроизводимые package builds, полный NixOS toplevel build, отдельная boot generation, реальный River login и рабочий acceptance pilot. Mango удалять только после отдельного go/no-go решения; Sway не удалять вместе с Mango.

## User Stories

1. As a desktop user, I want River + Machi to appear as a separate login session, so that I can evaluate it without losing Mango or Sway.
2. As a desktop user, I want exactly one River entry in sysc-greet, so that I cannot accidentally start River outside UWSM.
3. As a desktop user, I want River login to initialize a complete UWSM environment, so that graphical user services and portals work consistently.
4. As a desktop user, I want logout to use `uwsm stop`, so that River, Machi and session-scoped services terminate together.
5. As a desktop user, I want repeated login/logout cycles to leave no stale environment or orphan processes, so that subsequent sessions remain predictable.
6. As a configuration owner, I want the main NixOS package set to remain stable, so that this desktop migration does not upgrade unrelated system components.
7. As a configuration owner, I want River to come only from the pinned unstable package set, so that its newer protocol stack has a controlled blast radius.
8. As a configuration owner, I want River fixed at version 0.4.8, so that the tested compositor behavior is reproducible.
9. As a configuration owner, I want Machi pinned to an exact trunk commit, so that post-release lifecycle fixes are present without following a floating branch.
10. As a configuration owner, I want Machi and its dependencies to build without network access in the sandbox, so that the session is reproducible.
11. As a configuration owner, I want `channel` pinned to release 0.4.1 and an exact commit, so that input policy does not depend on a floating source.
12. As a desktop user, I want exactly one River input-policy owner, so that input settings are not applied twice or conflict.
13. As a desktop user, I want `us,ru` keyboard layouts, so that both existing typing workflows remain available.
14. As a desktop user, I want `Ctrl+Space` to switch layouts, so that the existing keyboard habit is preserved.
15. As a desktop user, I want Caps Lock to act as Control, so that existing keybindings remain usable.
16. As a desktop user, I want tap-to-click and natural scrolling, so that touchpad behavior remains familiar.
17. As a desktop user, I want disable-while-typing and button mapping verified, so that the migration does not introduce accidental pointer actions.
18. As a desktop user, I want existing xremap mappings to continue working, so that compositor migration does not break higher-level remaps.
19. As a desktop user, I want the built-in `eDP-1` output configured automatically at `2560x1600@240Hz` and scale 2, so that no manual display command is required after login.
20. As a desktop user, I want output settings to survive DPMS and suspend/resume, so that the display returns in the expected mode.
21. As a configuration owner, I want no external-monitor profiles in the first pilot, so that nonexistent hardware does not add untestable complexity.
22. As a desktop user, I want Xwayland retained, so that Enpass and other required X11 applications continue to run.
23. As a desktop user, I want terminal, launcher, Emacs and browser bindings preserved by intent, so that daily application startup remains efficient.
24. As a desktop user, I want close, fullscreen, focus and navigation actions expressed in Machi semantics, so that core window management remains available without imitating Mango mechanically.
25. As a desktop user, I want Machi single/split, panel and workspace behavior evaluated on its own terms, so that acceptance reflects the target model rather than Mango parity.
26. As a desktop user, I want lock and logout bindings to remain immediately available, so that session security and recovery are preserved.
27. As a desktop user, I want screenshot, region capture, clipboard and Drawing pipelines preserved, so that existing capture workflows continue to work.
28. As a desktop user, I want brightness, volume, mute, microphone and media bindings preserved with their OSD feedback, so that hardware controls remain usable.
29. As a desktop user, I want Mako notifications to continue working, so that session feedback remains visible.
30. As a desktop user, I want swaylock, swayidle and wlopm behavior preserved, so that lock, idle and DPMS policy does not regress.
31. As a desktop user, I want the session locked before suspend, so that suspend does not expose an unlocked desktop.
32. As a desktop user, I want media playback to inhibit idle appropriately, so that active playback is not interrupted.
33. As a desktop user, I want portal screen sharing to work in browser and Electron applications, so that meetings and capture workflows remain usable.
34. As a desktop user, I want Waybar privacy status to reflect capture and microphone activity, so that active recording remains visible.
35. As a desktop user, I want Waybar to retain Org timeblock and current-clock modules, so that existing work tracking remains visible.
36. As a desktop user, I want Waybar to retain volume, network, WireGuard, battery, clock and tray modules, so that generic desktop status remains available.
37. As a desktop user, I want the River Waybar profile to omit incompatible Mango and river-classic modules, so that Waybar starts without unknown-module errors.
38. As a desktop user, I want no empty lower bar in River, so that removed workspace content does not leave a useless layer surface.
39. As a configuration owner, I want one Waybar service template for Mango, River and Sway, so that profile selection has one lifecycle-aware launch path.
40. As a configuration owner, I want Waybar profile selection to use UWSM systemd instance identity, so that no custom profile environment marker can become stale.
41. As a desktop user, I want exactly one Waybar process in the active session, so that layer surfaces and the tray are not duplicated.
42. As a desktop user, I want Waybar to stop on normal logout and compositor failure, so that it cannot leak into the next session.
43. As a desktop user, I want Sway to keep a generic Waybar profile as a fallback, so that disabling the old generic service does not remove the bar from Sway.
44. As a desktop user, I want one Soteria graphical authentication agent, so that privileged desktop actions can request credentials.
45. As a desktop user, I want Soteria to stop with the graphical session, so that it cannot remain registered after logout.
46. As a configuration owner, I want transitive polkit agents detected before and after login, so that Soteria is never duplicated.
47. As a desktop user, I want AMDGPU to remain the primary rendering GPU, so that the migration does not change the machine's hybrid-GPU policy.
48. As a desktop user, I want NVIDIA PRIME offload verified through a deterministic Vulkan workload, so that offload success is observable rather than assumed.
49. As a desktop user, I want Enpass, browser, work browser, Telegram, Electron and tray applications smoke-tested, so that critical Wayland and Xwayland workflows are covered.
50. As a desktop user, I want application activation and focus-stealing behavior checked, so that launches from bindings, Waybar and tray applications are usable.
51. As a desktop user, I want decorated, transient, Picture-in-Picture and layer-shell clients exercised repeatedly, so that lifecycle crashes are caught before production login.
52. As a desktop user, I want suspend/resume and login/logout acceptance performed from a new boot generation, so that rollback remains available from GRUB.
53. As a configuration owner, I want Mango retained through the River acceptance period, so that a critical regression does not block desktop access.
54. As a configuration owner, I want Mango cleanup isolated in a later commit, so that migration and removal remain independently reversible.
55. As a configuration owner, I want Sway removal to remain a separate future decision, so that the independent fallback is not lost accidentally.
56. As a desktop user, I want the first River Waybar release accepted without window, workspace, layout or language indicators, so that panel-state integration does not block the compositor pilot.
57. As a configuration owner, I want future Machi state integration to use one persistent watcher rather than polling or multiple watchers, so that any later adapter has a bounded process model.
58. As a configuration owner, I want every implementation commit to build the complete NixOS toplevel, so that intermediate history remains deployable.

## Implementation Decisions

- Keep NixOS 26.05 as the primary stable package set. Do not introduce a global unstable overlay.
- Source River 0.4.8 narrowly from the already pinned unstable package set.
- Do not enable the NixOS River module because it selects river-classic rather than River 0.4+.
- Wrap the River package so its plain desktop entry is absent. Register only the UWSM-managed River session in the display-manager session set.
- Keep UWSM as the owner of compositor startup, environment finalization, graphical targets and logout.
- Keep sysc-greet as the session selector.
- Pin Machi to commit `65a0fc12f2796f41f4c9cbb7e034aaa137009b01`. Package it locally with fixed source and Zig dependency hashes.
- Treat the Machi tag release only as historical research baseline; do not retain a parallel A/B package in production configuration.
- Start Machi from River initialization as part of the UWSM-managed River session.
- Assign composition and protocol exposure to River; assign focus, placement, geometry, workspace/panel behavior, keybindings, fullscreen/split/single policy and layer-shell policy to Machi.
- Preserve Xwayland during the pilot.
- Pin `channel` release 0.4.1 to commit `4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446`. Package it locally with fixed source and Zig dependency hashes.
- Make `channel` the only River input manager. Do not install or start `kwim` alongside it.
- Configure `channel` with `us,ru`, `Ctrl+Space`, tap-to-click, natural scrolling, disable-while-typing, `lrm` tap button mapping and middle emulation, matching the effective current baseline.
- Make xremap the single owner of Caps-to-Control across Mango, River and Sway, and remove `ctrl:nocaps` from their XKB options. The low-level remap must run before xremap keymap rules so Caps-based chords such as `Ctrl+[` continue to produce Escape.
- Configure only `eDP-1` in the first pilot, at `2560x1600@240Hz`, position `(0,0)` and integer scale 2.
- Apply output configuration automatically through a `wlr-randr` one-shot at every River session start. The user must never run the command manually after rebuild or login.
- Do not add external-monitor or dock profiles. If River loses output state after DPMS or suspend/resume, replace the one-shot output policy with kanshi rather than adding manual recovery steps.
- Preserve existing Mango and Sway sessions during the pilot. Remove Mango only after a separate acceptance decision; do not couple Sway removal to Mango cleanup.
- Split Waybar configuration into a Mango profile and a generic-only profile. River and Sway share the generic-only profile.
- The River generic-only profile contains Org timeblock, Org current clock, privacy, WirePlumber, network, WireGuard, battery, clock and StatusNotifier tray modules.
- The River profile contains no `mango/*`, river-classic `river/*`, Machi adapter or XKB language module and starts no empty lower panel.
- Replace the generic Waybar user service with one `waybar@.service` template. Instantiate it for Mango, River and Sway from their compositor-specific UWSM session targets.
- Select the Waybar profile through the systemd unit instance identity `%i`. Define and consume no custom Waybar profile environment marker and do not infer compositor identity from socket presence.
- Order each Waybar instance after both its compositor-specific UWSM session target and the generic graphical session target. Bind the instance to the compositor-specific target so normal logout and abnormal compositor exit stop it.
- Retain standard UWSM session variables such as `WAYLAND_DISPLAY`; they remain environment prerequisites but are not profile selectors.
- Disable the existing generic Waybar service so the template is the sole Waybar launch path.
- Enable `pkgs.soteria` through the NixOS Soteria option. Keep the configuration in the NixOS module graph rather than the Home Manager module graph.
- Extend the generated Soteria user unit lifecycle so it stops with the graphical session. Soteria remains the selected agent; if runtime inspection finds a competing transitive agent, disable that competing activation declaratively rather than suppressing Soteria.
- Preserve Mako, swaylock, swayidle, wlopm, media idle inhibition, xdg-desktop-portal-wlr, GTK portal, PipeWire, WirePlumber, wmenu, screenshot tools, clipboard tools, ActivityWatch integration, KDE Connect and unrelated services unless a migration failure demonstrates a direct incompatibility.
- Preserve the existing UWSM template-unit activation guardrails that prevent active compositor services from restarting during a package switch.
- Preserve AMDGPU as the primary renderer and the existing NVIDIA PRIME offload configuration.
- Use `nvidia-offload vkcube` as the deterministic PRIME acceptance workload and require evidence that it uses the NVIDIA renderer.
- Carry bindings over by user intent rather than mechanically translating Mango tags, overview, jump, scroller proportions or layout cycles.
- Keep current window/title, Machi workspace/panel/mode state, input-language indication and clickable workspace controls out of the River Waybar MVP.
- If Machi state is specified later, prefer one persistent `machictl -watch` process per output over polling or multiple independent watchers.
- Build and validate package-only artifacts before adding a login session. Accept that compositor-policy failures may first surface in the rollback-protected production login pilot.
- Activate the first production River session only through a newly built boot generation, then reboot and verify Mango before selecting River.
- Do not send AI-generated reports, comments, diagnostics or patches to River upstream. Any upstream interaction must be independently reproduced, investigated and written by the user.

## Testing Decisions

- Use two high-level seams. The automated seam is the complete `yuri-alpha` NixOS toplevel; the runtime seam is a real UWSM-managed graphical session. Prefer assertions about built artifacts and observable session behavior over implementation details of individual Nix expressions.
- Every implementation commit must build the complete toplevel. Package-only commits must additionally prove that River, Machi and `channel` build in the sandbox without network access and expose the expected executables and versions.
- Use the repository's existing full-system build/rebuild workflow as prior art for the automated seam. Existing Mango and Sway UWSM sessions provide prior art for session registration, environment finalization and rollback.
- Inspect the evaluated display-manager session set and assert that it contains exactly one UWSM River entry and no plain River entry while retaining Mango and Sway during the pilot.
- Inspect the evaluated package closure and assert that the primary package set remains stable, River is exactly 0.4.8 from the narrow unstable source, Machi uses the exact production commit, and `channel` uses the exact 0.4.1 commit.
- Validate generated Waybar profiles before login and reject unknown or incompatible compositor modules.
- Validate the evaluated systemd user-unit graph by passing the generated Waybar and UWSM unit files from the built artifact explicitly to `systemd-analyze verify`. Assert that Waybar instances have no ordering loop, use the expected Mango/River/Sway identities, define no custom profile marker and bind teardown to the compositor-specific target.
- In each real Mango, River and Sway login, assert that exactly one matching Waybar instance and one Waybar process run. Verify normal logout and abnormal compositor exit stop them.
- In a real River login, verify that `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE` and desktop identity are available after UWSM finalization and that `graphical-session.target` is active.
- Verify `uwsm stop`, repeated login/logout and compositor failure leave no River, Machi, Waybar, Soteria or stale session-environment artifacts.
- Verify Soteria with a real graphical polkit request. Assert that exactly one authentication agent is registered, the prompt succeeds, logout terminates it and the next login does not inherit it.
- Verify `channel` as the only active River input manager and test layouts, layout switching, tap-to-click, natural scrolling, disable-while-typing, button mapping and device reapply. Verify xremap-owned Caps-to-Control and Caps-based `Ctrl+[` → Escape in Mango, River and Sway.
- Verify automatic `wlr-randr` execution on every River login and observe `eDP-1` mode and scale. Repeat after DPMS and suspend/resume. Failure to preserve output state is the explicit gate for replacing the policy with kanshi.
- Assert that no external-output profiles are generated in the first pilot.
- Verify swaylock manually, through idle timeout and before suspend. Verify wlopm off/on timing and media idle inhibition.
- Verify portal screenshot and screencast behavior in browser/Electron clients, GTK fallback interfaces and Waybar privacy indication.
- Verify screenshot, region selection, clipboard and Drawing pipelines through their user-visible outputs.
- Verify Mako, audio, microphone, brightness and media controls through both state changes and visible feedback.
- Verify Alacritty, Emacs, browsers, work browser, Enpass, Telegram, Electron and tray applications. Include both native Wayland and Xwayland clients.
- Verify application activation and focus-stealing behavior for applications launched from bindings, launcher, Waybar and tray.
- Verify AMD remains the primary renderer. Run `nvidia-offload vkcube`, assert that it identifies the NVIDIA renderer and renders a visible test window.
- Verify configured and hotplug-discovered output coordinates remain nonnegative and within River's Xwayland coordinate bounds, even though no external profile is configured.
- Perform several login/logout cycles, suspend/resume, DPMS and at least one complete working-day pilot before considering Mango cleanup.
- Treat failures in session lifecycle, portal, lock, input, output, Waybar or critical applications as acceptance blockers. Roll back by selecting Mango/Sway or booting the previous NixOS generation.
- Separate agent-executable verification from human acceptance without creating another implementation design: the agent completes builds and evaluated-artifact checks, then hands the new generation to `seryiza` for physical login, lock, suspend/resume, graphical prompts and the working-day pilot. Human results are recorded before Mango cleanup.

## Out of Scope

- Replacing Waybar with ashell, SFWBar, Ironbar, Quickshell, Eww or another panel.
- Using River HEAD or globally moving the system to nixos-unstable.
- Enabling river-classic or using Waybar's river-classic modules.
- Implementing a custom River/Machi protocol client or Machi-native Waybar module.
- Showing current window/title, Machi workspace/panel/mode state or keyboard language in the River Waybar MVP.
- Clickable Machi workspace controls.
- Reproducing Mango tags, overview, jump, scroller proportions or layout cycles one-to-one.
- Adding external-monitor or dock profiles to the first pilot.
- Adding a new input-language watcher.
- Removing Mango before the acceptance period is complete.
- Removing Sway as part of Mango cleanup.
- Changing hardware, PRIME topology, networking, PipeWire or unrelated user services without a demonstrated migration requirement.
- Assuming native River trackpad gestures; gestures require separate explicit acceptance criteria if later declared necessary.
- Sending AI-generated material to River upstream.

## Further Notes

- The River Waybar MVP boundary is accepted: missing compositor state and keyboard-language indication do not block migration.
- `wlr-randr` is "one-shot" because its process exits after applying output state; it is still launched automatically on every River session and is not a manual post-rebuild step.
- Standard UWSM environment remains necessary for Wayland clients and graphical services. Only the proposed custom Waybar profile marker was eliminated.
- The Soteria package is available in the selected package set. Its generated service needs an explicit graphical-session lifecycle relationship beyond simple startup ordering.
- Source manifest: Machi uses `https://codeberg.org/machi/machi` at commit `65a0fc12f2796f41f4c9cbb7e034aaa137009b01` with unpacked source hash `sha256-StpGIGnIjtdEQ9fWdsei6n93IJOG6BG7gRKaOS9sI24=`. `channel` uses `https://codeberg.org/Sivecano/channel` at commit `4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446` with unpacked source hash `sha256-AIP5SO7p2Z8fYeLSoIliSya2fQALV1xkkYfIRdHY6TQ=`. Zig dependency hashes must be generated and fixed during the package-only phase before either derivation is accepted.
- The source design and research artifacts contain the phased rollout, detailed checklist, rollback strategy and upstream references that informed this specification.
- The local issue tracker lives under `.scratch/` and is versioned with the repository so implementation decisions, acceptance gates and follow-up work remain available to future maintainers.
