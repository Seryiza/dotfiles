#!/usr/bin/env bash
set -euo pipefail

: "${RIVER:?}"
: "${MACHI:?}"
: "${WLR_RANDR:?}"
: "${ZELBAR:?}"
: "${FC_MATCH:?}"
: "${GRIM:?}"
: "${PYTHON:?}"
: "${TRACE_ASSERT:?}"

session_root=
river_pid=
client_pid=
river_log=

cleanup_session() {
  if [[ -n "${client_pid:-}" ]]; then
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
    client_pid=
  fi
  if [[ -n "${river_pid:-}" ]]; then
    kill "$river_pid" 2>/dev/null || true
    wait "$river_pid" 2>/dev/null || true
    river_pid=
  fi
  if [[ -n "${session_root:-}" ]]; then
    rm -rf "$session_root"
    session_root=
  fi
}
trap cleanup_session EXIT

start_session() {
  cleanup_session
  session_root=$(mktemp -d)
  river_log="$session_root/river.log"
  export XDG_RUNTIME_DIR="$session_root/runtime"
  mkdir "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  unset WAYLAND_DISPLAY

  WLR_BACKENDS=headless \
    WLR_RENDERER=pixman \
    WLR_HEADLESS_OUTPUTS=1 \
    WLR_LIBINPUT_NO_DEVICES=1 \
    "$RIVER" -no-xwayland -c "exec $MACHI" >"$river_log" 2>&1 &
  river_pid=$!

  local socket=
  for _ in $(seq 1 200); do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -1)
    [[ -n "$socket" ]] && break
    sleep 0.02
  done
  if [[ -z "$socket" ]]; then
    cat "$river_log" >&2
    echo "River did not create a Wayland socket" >&2
    return 1
  fi
  export WAYLAND_DISPLAY="$socket"
  OUTPUT=$("$WLR_RANDR" --json | jq -r '.[0].name')
}

ZELBAR_FIXED_ARGS=(
  -L 1
  -g 0:20
  -fn "DejaVu Sans"
  -B 0x112233ff
  -F 0xffffffff
  -bs 1:1:1:1
  -bc 0xff0000ff
)

run_zelbar() {
  exec "$ZELBAR" -o "$OUTPUT" "${ZELBAR_FIXED_ARGS[@]}"
}

wait_for_trace() {
  local trace=$1
  local pattern=$2
  for _ in $(seq 1 200); do
    grep -qE "$pattern" "$trace" && return 0
    sleep 0.02
  done
  echo "Timed out waiting for trace pattern: $pattern" >&2
  cat "$trace" >&2
  cat "$river_log" >&2
  return 1
}

run_initial() {
  local scale=$1
  local mode="initial-$scale"
  local trace
  start_session
  trace="$session_root/$mode.log"
  "$WLR_RANDR" --output "$OUTPUT" --custom-mode 800x600 --scale "$scale"
  sleep 0.1

  { printf '%s\n' "$mode"; sleep 5; } | \
    WAYLAND_DEBUG=client run_zelbar >/dev/null 2>"$trace" &
  client_pid=$!
  if [[ $scale -eq 1 ]]; then
    wait_for_trace "$trace" 'damage_buffer\(0, 0, 800, 20\)'
  else
    wait_for_trace "$trace" 'damage_buffer\(0, 0, 800, 40\)'
  fi

  "$PYTHON" "$TRACE_ASSERT" "$mode" "$trace"
  cleanup_session
}

run_transition() {
  local trace
  start_session
  trace="$session_root/transition.log"
  "$WLR_RANDR" --output "$OUTPUT" --custom-mode 800x600 --scale 1
  sleep 0.1

  { printf 'HiDPI\n'; sleep 5; } | \
    WAYLAND_DEBUG=client run_zelbar >/dev/null 2>"$trace" &
  client_pid=$!

  wait_for_trace "$trace" 'damage_buffer\(0, 0, 800, 20\)'
  "$GRIM" -o "$OUTPUT" "$session_root/scale1-before.png"

  "$WLR_RANDR" --output "$OUTPUT" --scale 2
  wait_for_trace "$trace" 'create_buffer.*800, 40, 3200'
  wait_for_trace "$trace" 'damage_buffer\(0, 0, 800, 40\)'
  sleep 0.1
  "$GRIM" -o "$OUTPUT" "$session_root/scale2.png"

  local before_scale1
  before_scale1=$(grep -c 'set_buffer_scale(1)' "$trace")
  "$WLR_RANDR" --output "$OUTPUT" --scale 1
  for _ in $(seq 1 200); do
    [[ $(grep -c 'set_buffer_scale(1)' "$trace") -gt $before_scale1 ]] && break
    sleep 0.02
  done
  [[ $(grep -c 'set_buffer_scale(1)' "$trace") -gt $before_scale1 ]]
  sleep 0.1
  "$GRIM" -o "$OUTPUT" "$session_root/scale1-after.png"

  "$PYTHON" "$TRACE_ASSERT" transition "$trace"
  "$PYTHON" "$TRACE_ASSERT" pixels \
    "$session_root/scale1-before.png" \
    "$session_root/scale2.png" \
    "$session_root/scale1-after.png"
  cleanup_session
}

font_px_1=$("$FC_MATCH" -f '%{pixelsize}\n' 'DejaVu Sans:scale=1' | head -1)
font_px_2=$("$FC_MATCH" -f '%{pixelsize}\n' 'DejaVu Sans:scale=2' | head -1)
"$PYTHON" - "$font_px_1" "$font_px_2" <<'PY'
import math
import sys

scale1_pixels, scale2_pixels = map(float, sys.argv[1:])
if not math.isclose(scale2_pixels, scale1_pixels * 2, rel_tol=0.0, abs_tol=0.01):
    raise SystemExit(
        f"Fontconfig scale did not double raster size: {scale1_pixels} -> {scale2_pixels}"
    )
print(f"PASS font scale: {scale1_pixels} -> {scale2_pixels} physical pixels")
PY

run_initial 1
run_initial 2
run_transition
