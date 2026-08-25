# Add Machi and River XKB sources

Status: ready-for-agent
Blocked by: 02

## Objective

Provide authoritative, event-driven River/Machi state for the Go status Module.

## Scope

- Add Machi Adapter that supervises exactly one `machictl -watch eDP-1` process.
- Decode complete NDJSON snapshots, validate output/schema and convert indices only in the renderer view.
- Treat malformed JSON, EOF and process exit as fatal.
- Pin `github.com/MatthiasKunnen/go-wayland/wayland`; do not use the archived original module.
- Generate and commit Go bindings from exact River 0.4.8 `river-input-management-v1.xml` and `river-xkb-config-v1.xml`.
- Record generator revision and XML provenance in generated headers.
- Implement XKB keyboard add/layout/done/remove lifecycle.
- Show `mixed` when active keyboards disagree.
- Treat missing River XKB global or Wayland disconnect as fatal.

## Acceptance Criteria

- Machi fixtures cover initial/updated/zero-count/malformed/wrong-output/EOF states.
- Human-facing workspace and panel indices are one-based while stored source state remains zero-based.
- XKB tests cover initial layout, switching, multiple equal keyboards, mixed keyboards and removal.
- Generated protocol bindings compile reproducibly from the pinned module set.
- Live acceptance instructions prove `us`/`ru` changes and Machi state updates in River.
- No river-classic protocol appears in source or generated artifacts.
- Full `yuri-alpha` toplevel build succeeds.

## Comments
