# River + Machi + Zelbar

Status: ready-for-agent

## Problem Statement

В River 0.4.8 + Machi текущий generic Waybar сохраняет системный статус, но не показывает состояние Machi и раскладку River. Пользователь выбирает минимальную, текстовую и композируемую панель на базе Zelbar только для River-сессии.

Первая версия должна полностью заменить Waybar именно в River-сессии. Mango не переносится на Zelbar и продолжает использовать свой Waybar profile. Sway также сохраняет generic Waybar. Multi-output, tray, privacy, tooltips, popup calendar, изображения и mouse actions отложены.

Upstream Zelbar v1.2.0 является text renderer, а не host модулей. Его текущий stdin reader читает произвольные chunks размером до 4096 bytes и некорректно полагается на stream framing, поэтому надёжные границы кадров и lifecycle находятся за отдельным **Seam** в локальном status **Module**.

Первичная human acceptance на `yuri-alpha` провалилась: на `eDP-1` (2560×1600, output scale 2) Zelbar с logical geometry `0:20` создаёт 1× SHM buffer, который compositor растягивает до scale 2. Текст получается явно размытым. `-L 1` выбирает layer-shell layer и не задаёт display scale. В pinned upstream `src/Backend.zig` событие `wl_output.scale` оставлено с `// TODO: scale` и игнорируется. Этот renderer defect нельзя изолировать во внешнем status Adapter, поэтому прежний запрет patches официально заменён разрешением одного минимального локального HiDPI patch поверх того же pinned revision.

## Solution

Добавить River-only status **Module** `river-zelbar-status`, написанный на Go. Его внешний **Interface** — импорт Home Manager-модуля `nixos/home/zelbar.nix`; пользовательские source/module options в первой версии не вводятся. Output, layout, источники, интервалы, renderer flags и lifecycle фиксированы под текущую конфигурацию `yuri-alpha`.

Go **Implementation**:

- запускает Zelbar v1.2.0 с единственным локальным HiDPI patch поверх exact pinned source;
- передаёт renderer-у один полный frame на packet через Linux `AF_UNIX/SOCK_SEQPACKET` socketpair;
- запускает один `machictl -watch eDP-1` и валидирует Machi NDJSON;
- в процессе наблюдает `river-xkb-config-v1` через generated pure-Go Wayland bindings;
- опрашивает существующие Org/WireGuard scripts, `wpctl`, `nmcli`, battery sysfs и clock;
- хранит единый typed snapshot, coalesces updates и форматирует одну безопасную Zelbar строку;
- владеет дочерними процессами и при критическом отказе завершает весь process graph, чтобы systemd перезапустил его.

Zelbar рисует одну верхнюю panel surface на `eDP-1`. River Waybar autostart/profile path удаляется. Mango и Sway Waybar paths не меняются.

## Product Decisions

- Target session: только `wayland-session@river.target`.
- Output: только `eDP-1`; multi-output discovery отсутствует.
- Renderer: Zelbar v1.2.0, commit `b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932`.
- Renderer source: exact pinned upstream revision плюс ровно `nixos/pkgs/zelbar-hidpi.patch`; arbitrary patches, substitutions и source fork запрещены.
- Upstream policy: не создавать contribution, issue, comment и не связываться с upstream в рамках этой работы.
- Status Module language: Go.
- Interaction: read-only; Zelbar action markup не генерируется.
- Tray: out of scope; позднее возможен textual SNI Adapter с emoji/abbreviations.
- Privacy: out of scope.
- Position: top, full output width, 20 logical pixels.
- Theme: белый background, чёрный text, Iosevka primary font, Noto Color Emoji fallback.
- Waybar: River identity/link/case удаляются; Mango и Sway остаются.
- No manual River Waybar fallback после активации; rollback выполняется rebuild/предыдущей generation.

## Interface and Depth

Внешний **Interface** — импорт `./home/zelbar.nix`. Он гарантирует:

1. ровно один River Zelbar unit;
2. отсутствие River Waybar unit link;
3. один renderer и один authoritative Machi watcher;
4. фиксированный набор и порядок text sources;
5. bounded memory и bounded frame size;
6. session-scoped lifecycle без orphan processes;
7. renderer построен из pinned upstream revision с ровно одним проверяемым локальным HiDPI patch, без substitutions или fork.

Внутренние **Seams** нужны только там, где реально существуют два **Adapter**:

- source Adapter: production source и scripted test source;
- renderer Adapter: Zelbar packet renderer и recording renderer для tests;
- clock/command/filesystem Adapter: production dependency и deterministic test implementation.

Public plugin DSL, arbitrary command config и generic renderer selection не вводятся. Это сохраняет **Depth**, **Leverage** и **Locality**: callers не знают о protocol XML, polling, escaping, packets или process supervision.

## Rendered Layout

Формат первой версии:

```text
left:  W 2/4 · P 1/3 · split · 3w · Current window title
right: Org timeblock | Org clock | 52% audio +MIC | wlan | wg-work | ru | 87% battery | 23 Aug 21:35
```

Правила:

- Machi indices преобразуются из zero-based в human-facing `+1` только renderer view.
- `mode`, window count и title берутся из одного complete Machi snapshot.
- Empty title просто опускается.
- Empty optional fields и соседние separators опускаются.
- Healthy Ethernet/Wi-Fi скрываются, как в текущем visible Waybar policy.
- Wi-Fi `<20%` отображается как `wlan`; disconnected/disabled показываются текстом.
- Full battery скрывается; остальные состояния показывают capacity text.
- Clock показывает только `%d %b %H:%M`; calendar tooltip и timezone actions не переносятся.
- Audio показывает default sink volume или `MUTED`; `+MIC` означает, что default source не muted. Node name, tooltip и scroll control не переносятся.
- Org fields ограничены 60 grapheme clusters и скрываются при empty output.
- WireGuard использует только `.text` из текущего JSON output; tooltip не переносится.
- XKB показывает short layout name (`us`, `ru`). Если несколько keyboards сообщают разные layouts — `mixed`.

## Source Contracts

### Machi

- Command: exact package path to `machictl -watch eDP-1`.
- Contract: newline-delimited complete JSON snapshots.
- Only snapshots with `name == "eDP-1"` are accepted.
- Malformed JSON, schema mismatch, EOF or child exit are fatal.
- Queue: bounded latest-state-wins.

### River XKB

- Bind `river_xkb_config_v1` and handle `xkb_keyboard` objects.
- Generated Go bindings come from exact River 0.4.8 XML files:
  - `river-input-management-v1.xml`;
  - `river-xkb-config-v1.xml`.
- Handle initial `layout`, changes, `done` and `removed`.
- Wayland disconnect or unavailable required global is fatal.

### Org

- Reuse `scripts/waybar-org-timeblock` and `scripts/waybar-org-current-clock` unchanged.
- Poll every 15 seconds.
- Consume only the first output line; blank is expected empty state.
- Failure hides the value and logs a rate-limited warning.

### WireGuard

- Reuse `scripts/waybar-wireguard short` unchanged.
- Poll every 15 seconds.
- Parse JSON and consume only string `.text`.
- No active connection is an empty valid state.

### Audio

- Poll default sink and source using absolute `wpctl` argv every 2 seconds.
- Sink output becomes `NN% audio` or `MUTED`.
- Append `+MIC` when default source is not muted.
- Failure shows `audio?` and logs; it does not restart the whole Module.

### Network

- Poll NetworkManager using absolute `nmcli` argv every 15 seconds.
- Preserve visible current semantics: hide healthy connectivity; show low Wi-Fi, disconnected, linked-without-IP and disabled states.
- Failure shows `network?`.

### Battery

- Read `/sys/class/power_supply` every 60 seconds.
- Select the present battery deterministically; current hardware is expected to expose one battery.
- Hide full state; otherwise render integer capacity.
- Missing battery is empty, not fatal.

### Clock

- Render at startup and at minute boundaries using local timezone.
- Wall-clock changes trigger the next scheduled refresh; monotonic time controls polling/staleness.

## Renderer Contract: Pinned Minimal HiDPI Patch

A normal `producer | zelbar` pipeline is prohibited because a pipe is a byte stream and does not preserve writes as reads.

The renderer **Adapter** must:

1. create `socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC)`;
2. pass one endpoint as Zelbar stdin;
3. send exactly one complete UTF-8 frame per `send` call;
4. enforce `1 <= frame bytes <= 4096`, including final newline;
5. reject oversize frames before send;
6. retain the peer while Zelbar is alive;
7. send SIGTERM and reap Zelbar before closing the socket;
8. configure parent-death signaling for the child where supported;
9. direct Zelbar stdout to `/dev/null`, because v1 emits no actions.

`SOCK_SEQPACKET` preserves ordered record boundaries, so Zelbar's single `read(4096)` receives one complete in-limit frame and cannot coalesce two frames. On supervisor failure, systemd `KillMode=control-group` terminates Zelbar before restart, preventing the upstream `POLLHUP` busy loop from surviving.

Пакет применяет ровно `nixos/pkgs/zelbar-hidpi.patch` к commit `b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932`. Patch должен быть изолирован от stdin framing/status protocol и обеспечить всю HiDPI chain:

1. принять initial и последующие `wl_output.scale` events;
2. сохранить bar geometry в logical units (`0:20`);
3. вызвать `wl_surface.set_buffer_scale` до соответствующего surface commit;
4. выделить SHM buffer размером `logical_width * scale` × `logical_height * scale` physical pixels;
5. rasterize fonts, text и decorations в том же physical scale;
6. damage/attach/commit согласованно описывают новый physical buffer;
7. при scale change пересоздать rendering resources и commit-нуть новый buffer без clipping.

Проверки должны доказать exact revision, exact patch allowlist и отсутствие `postPatch`, substitutions, дополнительных patches, fork или других source edits. Если это требует крупной переработки renderer architecture, implementation останавливается и предлагает replacement renderer вместо локального fork.

## Text Safety

Only the formatter may emit Zelbar markup. Dynamic source text is data, never markup.

Before formatting:

- reject invalid UTF-8;
- replace CR/LF/TAB/NUL and control characters with spaces or remove them;
- replace `%`, `{` and `}` with safe full-width equivalents;
- normalize repeated whitespace;
- truncate by grapheme cluster and then by final UTF-8 byte budget;
- never evaluate text through `sh -c`;
- use fixed argv and absolute Nix-store paths for commands.

Frame generation must always end in a text block and a newline. Fuzz/property tests cover titles containing Cyrillic, emoji, combining marks, RTL, `%{`, trailing `%`, braces and oversized input.

## Lifecycle and systemd

Generated user unit: `zelbar-river.service`.

Required relationships:

```ini
After=wayland-session@river.target graphical-session.target
BindsTo=wayland-session@river.target
ConditionEnvironment=WAYLAND_DISPLAY
Restart=on-failure
RestartSec=2
KillMode=control-group
TimeoutStopSec=3
```

Normal target stop must not restart the unit. Critical child failure causes status Module exit nonzero and one complete graph restart. Optional polling-source failures degrade only their field.

The status Module must never call `uwsm finalize`, start Machi, or own River input policy. Those remain in `nixos/home/river.nix`.

## Repository Changes

### New files

- `nixos/pkgs/zelbar.nix` — exact pinned upstream package with an explicit one-patch allowlist.
- `nixos/pkgs/zelbar-hidpi.patch` — minimal output-scale/buffer-scale/physical-rendering fix.
- `nixos/pkgs/river-zelbar-status/default.nix` — `buildGoModule` package.
- `nixos/pkgs/river-zelbar-status/go.mod` / `go.sum`.
- `nixos/pkgs/river-zelbar-status/cmd/river-zelbar-status/main.go`.
- `nixos/pkgs/river-zelbar-status/internal/...` — engine, sources, renderer, supervisor and tests.
- `nixos/pkgs/river-zelbar-status/internal/riverxkb/...` — generated protocol bindings and provenance.
- `nixos/home/zelbar.nix` — package, launcher, systemd unit and River target link.
- `nixos/tests/zelbar-session.nix` — evaluated Home Manager/systemd integration check.
- `nixos/tests/zelbar-runtime.nix` — Go/package transport and fixture checks.

### Modified files

- `flake.nix` — add `zelbar` and `river-zelbar-status` to the existing narrow overlay, packages and checks.
- `nixos/home.nix` — import `./home/zelbar.nix`; add Noto Color Emoji to the effective font environment if required by the module.
- `nixos/home/waybar.nix` — remove `river` from `profileBySessionIdentity`; do not generate a River launcher case or River target link.
- `nixos/tests/waybar-session-profiles.nix` — assert only Mango/Sway Waybar links and absence of River Waybar path.
- `nixos/tests/river-session-policy.nix` — assert exactly one River bar owner and correct target lifecycle.

### Unchanged files

- `nixos/home/river.nix`.
- `nixos/home/mango.nix`.
- `nixos/home/waybar.css`.
- Existing Org/WireGuard scripts.
- Mango and Sway Waybar profiles and links.

## Packaging Decisions

- Zelbar source: SourceHut exact commit, fixed source hash.
- Build Zelbar with `zig_0_15`, Wayland, wayland-protocols, fcft, pixman and pkg-config.
- Materialize Zig dependencies with Nix's Zig dependency fetch mechanism; builds must not access the network.
- Go Module is locally owned and built with `buildGoModule` and fixed `vendorHash`.
- Use maintained `github.com/MatthiasKunnen/go-wayland/wayland` fork pinned in `go.mod`; the original repository is archived.
- Commit generated River bindings; record XML source path/tag and generator revision in a generated-file header.
- `zelbar-machi` is not a dependency and no code is copied from it; its repository lacks an explicit license and its lifecycle is insufficient for this design.

## User Stories

1. As a River user, I want one minimal top bar so compositor state and daily text status are visible.
2. As a River user, I want Machi workspace, panel, mode, window count and title from one authoritative snapshot.
3. As a River user, I want the active `us`/`ru` layout visible.
4. As a user, I want Org timeblock and current clock text preserved.
5. As a user, I want connected WireGuard names visible.
6. As a user, I want textual volume/mute, exceptional network state, battery and clock visible.
7. As a configuration owner, I want the pinned Zelbar revision changed only by one auditable local HiDPI patch.
8. As a configuration owner, I want status source failures bounded and diagnosable through the journal.
9. As a configuration owner, I want no River Waybar process or duplicate panel.
10. As a Mango/Sway user, I want their existing Waybar behavior unchanged.
11. As a user, I want logout and compositor failure to leave no stale Zelbar/status processes.
12. As a configuration owner, I want each implementation commit to build the complete `yuri-alpha` toplevel.

## Acceptance Criteria

### Automated

- Exact pinned Zelbar plus the allowlisted local HiDPI patch and the Go status package build offline in the Nix sandbox.
- A differential scale 1/2 regression harness proves buffer scale 1 uses `W×20`, scale 2 uses `2W×40`, and scale changes update `wl_surface` buffer scale before commit.
- `zelbar -version` reports 1.2.0.
- Go tests and race-enabled tests pass where supported.
- Generated XKB bindings compile from the pinned module set.
- Packet tests prove two queued frames produce two reads, 4096 bytes succeeds, 4097 is rejected before send.
- Lifecycle tests prove essential child exit kills/reaps siblings and leaves no spin/orphan.
- Formatter tests cover malformed Machi JSON, Unicode, controls, markup injection and byte bounds.
- Adapter fixtures cover every source's valid, empty and failing state.
- Home generation contains `zelbar-river.service` linked only from the River target.
- Home generation has no `waybar@river.service` link or River launcher case.
- Mango/Sway Waybar links and profiles remain unchanged.
- `systemd-analyze --user verify` passes.
- Full `yuri-alpha` toplevel build and `nix flake check` pass.

### Human runtime

- Real River login shows one top Zelbar surface at eDP-1 scale 2 with a physical 2× buffer while preserving 20 logical pixels.
- Scale 1/2 visual comparison confirms sharp text, stable top positioning and no clipping.
- Machi navigation/title and XKB switches update promptly.
- Org, WireGuard, audio, network, battery and minute clock match expected text semantics.
- Empty optional fields do not leave duplicate separators.
- Long Cyrillic/emoji titles do not crash or inject markup.
- Restarting Machi or killing the status Module results in a bounded clean restart without high CPU.
- `uwsm stop`, logout and subsequent login leave no stale processes.
- Mango and Sway sessions still launch their existing Waybar setup.

## Rollback

- Before switching, keep the previous NixOS generation available.
- If River bar acceptance fails, rebuild without `./home/zelbar.nix` and restore `river` in Waybar identity mapping, or boot the previous generation.
- Mango and Sway remain independent graphical fallbacks throughout.
- Rollback uses the previous NixOS generation; it does not mutate or bypass the allowlisted renderer patch.

## Out of Scope

- Mango state or Mango Zelbar unit.
- Sway state migration.
- Multi-output discovery/hotplug.
- SNI tray, textual tray and application abbreviation mapping.
- Privacy/PipeWire capture indicator and GeoClue.
- Tooltips, images, popups, calendar UI and timezone cycling.
- Mouse buttons, scroll, click actions or Machi controls.
- WirePlumber node names, source volume details or interactive volume control.
- Generic source/plugin DSL or selectable renderers.
- River-classic status/control protocols.
- Any upstream contribution, issue, comment, contact or patch submission to River or Zelbar upstream.

## Open Technical Gates

There are no unresolved product questions after the user's answers. These implementation facts are verification gates, not design choices:

1. Generate and fix SourceHut source hash, Zig dependency hash and Go `vendorHash`.
2. Confirm the pinned locally patched Zelbar commits a 2× physical buffer, renders sharply and receives pointer-free input correctly at eDP-1 scale 2.
3. Run generated Go XKB client against a live River registry and verify initial/change/remove events.
4. Confirm current hardware battery sysfs name and exact `nmcli`/`wpctl` output fixtures during implementation.
5. Confirm the complete line fits the 4096-byte frame budget under worst-case sanitized title and Org values.

## Implementation Plan

See `.scratch/river-machi-zelbar/issues/01-package-unmodified-zelbar.md` through `08-fix-zelbar-hidpi-and-reaccept.md`. Issue 07 records the failed initial human acceptance; issue 08 owns the local HiDPI patch, automated regression coverage and repeated acceptance. Dependencies are recorded in each issue.

## Further Notes

- This feature's specification and issue plan are committed with the implementation; unrelated `.scratch/` efforts remain outside this change.
- No upstream contact or contribution is part of this plan.
- The original no-patch decision was intentionally reopened only after the real scale-2 acceptance exposed a renderer defect outside the status Module seam.

## Comments
