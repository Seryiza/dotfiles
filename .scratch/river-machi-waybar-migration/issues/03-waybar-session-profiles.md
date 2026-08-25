# Split Waybar profiles and bind them to sessions

Status: ready-for-agent
Blocked by: 01

## Objective

Establish one lifecycle-aware Waybar launch path for Mango, River, and Sway before River becomes selectable.

## Scope

- Preserve the current Mango profile and create a generic-only profile shared by River and Sway.
- Keep Org timeblock, Org current clock, privacy, WirePlumber, network, WireGuard, battery, clock, and StatusNotifier tray modules in the generic profile.
- Exclude `mango/*`, river-classic `river/*`, Machi-state, and keyboard-language modules from the generic profile.
- Do not create an empty lower bar in the generic profile.
- Replace the generic Waybar user service with one `waybar@.service` template.
- Select the profile only from systemd instance identity `%i`; do not add a custom profile environment variable or infer identity from sockets.
- Bind Mango and Sway instances to their compositor-specific UWSM targets and prepare the River instance identity.
- Preserve existing UWSM template-unit activation guardrails.

## Acceptance Criteria

- Generated Mango and generic profiles parse and contain only their allowed modules.
- No custom profile marker or socket-based compositor detection exists.
- Generated units use Mango, River, and Sway identities and bind teardown to compositor-specific targets.
- Passing the generated Waybar and UWSM units explicitly to `systemd-analyze verify` reports no ordering cycle.
- The old generic Waybar service is disabled as a launch path.
- The complete `yuri-alpha` toplevel builds after every implementation commit.

## Comments
