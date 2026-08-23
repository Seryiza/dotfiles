{ pkgs, river }:
pkgs.runCommand "river-decoration-globals-check"
  {
    nativeBuildInputs = [ pkgs.wayland-utils ];
  }
  ''
    set -eu

    runtime_dir="$TMPDIR/runtime"
    river_log="$TMPDIR/river.log"
    wayland_info="$TMPDIR/wayland-info.log"
    mkdir -m 700 "$runtime_dir"

    cleanup() {
      status=$?
      trap - EXIT HUP INT TERM
      if test -n "''${river_pid:-}"; then
        kill "$river_pid" 2>/dev/null || true
        wait "$river_pid" 2>/dev/null || true
      fi
      if test "$status" -ne 0; then
        echo "--- river log ---" >&2
        cat "$river_log" >&2 || true
        echo "--- wayland-info ---" >&2
        cat "$wayland_info" >&2 || true
      fi
      exit "$status"
    }
    trap cleanup EXIT HUP INT TERM

    XDG_RUNTIME_DIR="$runtime_dir" \
      WLR_BACKENDS=headless \
      WLR_RENDERER=pixman \
      WLR_HEADLESS_OUTPUTS=1 \
      ${river}/bin/river -no-xwayland -c true >"$river_log" 2>&1 &
    river_pid=$!

    socket=
    for _ in $(seq 1 200); do
      socket=$(find "$runtime_dir" -maxdepth 1 -type s -name 'wayland-*' -print -quit)
      if test -n "$socket"; then
        break
      fi
      if ! kill -0 "$river_pid" 2>/dev/null; then
        echo "River exited before creating a Wayland socket" >&2
        exit 1
      fi
      sleep 0.05
    done
    if test -z "$socket"; then
      echo "Timed out waiting for River's Wayland socket" >&2
      exit 1
    fi

    XDG_RUNTIME_DIR="$runtime_dir" \
      WAYLAND_DISPLAY="''${socket##*/}" \
      wayland-info >"$wayland_info"

    grep -E "interface: 'org_kde_kwin_server_decoration_manager',[[:space:]]+version:[[:space:]]+1(,|$)" "$wayland_info"
    grep -E "interface: 'zxdg_decoration_manager_v1',[[:space:]]+version:[[:space:]]+1(,|$)" "$wayland_info"

    touch "$out"
  ''
