# Build the Go status core

Status: ready-for-agent
Blocked by: none

## Objective

Create the deep Go status Module that owns typed state, formatting, pinned-Zelbar transport and process lifecycle. Renderer HiDPI source changes are isolated to issue 08 and must not alter this transport seam.

## Scope

- Add `nixos/pkgs/river-zelbar-status/` with `go.mod`, `go.sum`, `buildGoModule` packaging and fixed `vendorHash`.
- Implement one status engine with internal Source and Renderer seams; do not expose a plugin DSL.
- Implement `AF_UNIX/SOCK_SEQPACKET` renderer Adapter:
  - one frame per send;
  - maximum 4096 bytes including newline;
  - receiver passed as Zelbar stdin;
  - ordered SIGTERM/reap before socket close;
  - parent-death signaling where supported.
- Implement bounded latest-state coalescing.
- Implement centralized Zelbar formatter and sanitizer for controls, `%`, braces, Unicode and byte limits.
- Implement child supervision and fatal/nonfatal error classes.
- Keep v1 read-only and direct Zelbar stdout to `/dev/null`.
- Use fixed argv; never use `sh -c` for source data.

## Acceptance Criteria

- Unit tests cover snapshot reduction, omission/separators, sanitizer, Unicode, markup injection and byte limits.
- Packet tests prove separate queued frames remain separate, exactly 4096 bytes works and 4097 bytes is rejected before send.
- Lifecycle tests cover renderer exit, supervisor exit, producer exit, SIGTERM timeout and orphan prevention.
- Optional-source errors can degrade a field without leaking goroutines or restarting the whole graph.
- `go test ./...` and race-enabled tests pass where Nix supports them.
- Package builds offline with fixed `vendorHash`.
- Full `yuri-alpha` toplevel build succeeds.

## Comments
