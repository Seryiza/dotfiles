{
  pkgs,
  zelbar,
  river-zelbar-status,
}:
assert river-zelbar-status.pname == "river-zelbar-status";
assert river-zelbar-status.doCheck;
pkgs.runCommand "zelbar-runtime-check"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.emacs-pgtk pkgs.gnugrep ];
  }
  ''
    status_src=${river-zelbar-status.src}
    renderer_src="$status_src/internal/renderer"
    emacs_src=${../../dotfiles/emacs}

    test -x ${river-zelbar-status}/bin/river-zelbar-status
    ! grep -E 'tlpctl|nmcli|wireGuardDefault' "$status_src/cmd/river-zelbar-status/main.go"
    test "$(${zelbar}/bin/zelbar -version 2>&1)" = 1.2.0
    runtime="$(mktemp -d)"
    trap 'rm -rf "$runtime"' EXIT
    XDG_RUNTIME_DIR="$runtime" \
      ${pkgs.emacs-pgtk}/bin/emacs --batch -Q \
      -l "$emacs_src/tests/sz-org-status-test.el" \
      -f ert-run-tests-batch-and-exit


    grep -F 'const MaxPacketBytes = 4096' "$renderer_src/packet_linux.go"
    grep -F 'unix.AF_UNIX, unix.SOCK_SEQPACKET|unix.SOCK_CLOEXEC' \
      "$renderer_src/packet_linux.go"
    test "$(grep -c 'unix.Send(fd, frame' "$renderer_src/packet_linux.go")" -eq 1
    ! grep -R -E \
      'os\.Pipe|io\.Pipe|unix\.Pipe|syscall\.Pipe|Pipe2|StdinPipe|StdoutPipe|SOCK_STREAM' \
      "$renderer_src"

    grep -F 'cmd.Stdin = child' "$renderer_src/zelbar_linux.go"
    grep -F 'cmd.Stdout = devNull' "$renderer_src/zelbar_linux.go"
    grep -F 'Pdeathsig: syscall.SIGTERM' "$renderer_src/zelbar_linux.go"
    grep -F 'terminateAndReap' "$renderer_src/zelbar_linux.go"

    packet_tests="$renderer_src/packet_linux_test.go"
    lifecycle_tests="$renderer_src/lifecycle_linux_test.go"
    grep -F 'TestSocketPairPreservesSeparateQueuedFrames' "$packet_tests"
    grep -F 'TestSendFrameAcceptsExactly4096Bytes' "$packet_tests"
    grep -F 'TestSendFrameDoesNotBlockBehindStalledRenderer' "$packet_tests"
    grep -F 'TestSendFrameRejects4097BytesBeforeSend' "$packet_tests"
    grep -F 'TestRendererExitIsReported' "$lifecycle_tests"
    grep -F 'TestSIGTERMTimeoutKillsAndReapsRenderer' "$lifecycle_tests"
    grep -F 'TestParentDeathSignalPreventsRendererOrphan' "$lifecycle_tests"

    touch "$out"
  ''
