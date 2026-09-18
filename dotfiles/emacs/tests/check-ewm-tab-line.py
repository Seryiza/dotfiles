"""Run the native tab-line crash regression on a disposable Xvfb display.

Requires Emacs, Xvfb, and EWM_TEST_SOURCE pointing to pinned EWM lisp sources.
"""

import os
from pathlib import Path
import subprocess
import sys

server = subprocess.Popen(
    ["Xvfb", "-displayfd", "1", "-screen", "0", "1280x800x24", "-nolisten", "tcp"],
    stdout=subprocess.PIPE, text=True)
try:
    display = server.stdout.readline().strip()
    assert display.isdecimal(), "Xvfb did not allocate an isolated display"
    env = dict(os.environ, DISPLAY=":" + display, GDK_BACKEND="x11", NO_AT_BRIDGE="1")
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(
        ["emacs", "-Q", "--load", str(Path(__file__).with_name("sz-ewm-test.el")),
         "--eval", '(progn (unless (display-graphic-p) (kill-emacs 2)) '
         '(let ((noninteractive t)) (ert-run-tests-batch-and-exit '
         '"sz/ewm-tab-line-truncated-isolate-native-redisplay")))'],
        env=env, timeout=45)
    print(f"Native tab-line regression: exit {result.returncode}")
    sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
finally:
    server.terminate()
    server.wait(timeout=5)
