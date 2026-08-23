{
  lib,
  pkgs,
  homeGeneration,
  toplevel,
  soteria,
  configuredPackages,
}:
let
  configuredPackagePaths = pkgs.writeText "configured-package-paths" (
    lib.concatMapStringsSep "\n" toString configuredPackages
  );
in
pkgs.runCommand "soteria-session-agent-check"
  {
    nativeBuildInputs = [
      pkgs.man-db
      pkgs.python3
      pkgs.systemd
    ];
  }
  ''
    home_files=${homeGeneration}/home-files
    unit=${toplevel}/etc/systemd/user/polkit-soteria.service

    test -x ${toplevel}/sw/bin/soteria
    test "$(readlink -f ${toplevel}/sw/bin/soteria)" = "${lib.getExe soteria}"
    test -f "$unit"
    test -L ${toplevel}/etc/systemd/user/graphical-session.target.wants/polkit-soteria.service
    grep -F 'BindsTo=graphical-session.target' "$unit"
    grep -F 'After=graphical-session.target' "$unit"
    grep -F "ExecStart=${lib.getExe soteria}" "$unit"

    export CONFIGURED_PACKAGE_PATHS=${configuredPackagePaths}
    export HOME_FILES="$home_files"
    export INTENDED_UNIT="$unit"
    export TOPLEVEL=${toplevel}
    ${pkgs.python3}/bin/python <<'PY'
    import os
    import re
    from pathlib import Path

    package_paths = Path(os.environ["CONFIGURED_PACKAGE_PATHS"]).read_text().splitlines()
    activation_roots = []
    for package_path in package_paths:
        package = Path(package_path)
        activation_roots.extend(
            package / relative
            for relative in (
                "etc/xdg/autostart",
                "share/xdg/autostart",
                "lib/systemd/user",
                "share/systemd/user",
            )
        )
    activation_roots.extend(
        [
            Path(os.environ["HOME_FILES"]) / ".config/autostart",
            Path(os.environ["HOME_FILES"]) / ".config/systemd/user",
            Path(os.environ["TOPLEVEL"]) / "etc/systemd/user",
            Path(os.environ["TOPLEVEL"]) / "sw/etc/xdg/autostart",
            Path(os.environ["TOPLEVEL"]) / "sw/share/xdg/autostart",
        ]
    )

    competitor_reference = re.compile(
        r"(?:polkit[_-]gnome|polkit-gnome-authentication-agent|"
        r"lxqt-policykit|lxpolkit|mate-polkit|polkit-mate-authentication-agent|"
        r"polkit-kde-agent|hyprpolkitagent|pantheon-agent-polkit|"
        r"lomiri-polkit-agent)",
        re.IGNORECASE,
    )
    soteria_reference = re.compile(r"(?:polkit-soteria|/soteria(?:\s|$))", re.IGNORECASE)
    intended_unit = Path(os.environ["INTENDED_UNIT"]).resolve()
    soteria_activations = set()
    competitor_activations = set()
    for root in activation_roots:
        if not root.exists():
            continue
        for candidate in root.rglob("*"):
            if not candidate.is_file():
                continue
            try:
                text = candidate.read_text(errors="replace")
            except OSError:
                continue
            evidence = f"{candidate}\n{text}"
            resolved_candidate = candidate.resolve()
            if soteria_reference.search(evidence):
                soteria_activations.add(resolved_candidate)
            if competitor_reference.search(evidence):
                competitor_activations.add(resolved_candidate)

    assert soteria_activations == {intended_unit}, (
        "expected exactly the generated Soteria unit as an activation path, found: "
        + ", ".join(map(str, sorted(soteria_activations)))
    )
    assert not competitor_activations, (
        "competing graphical polkit activation paths found: "
        + ", ".join(map(str, sorted(competitor_activations)))
    )
    PY

    mkdir -p "$TMPDIR/runtime"
    MANPATH=${toplevel}/sw/share/man \
      XDG_RUNTIME_DIR="$TMPDIR/runtime" \
      SYSTEMD_UNIT_PATH=${toplevel}/etc/systemd/user \
      ${pkgs.systemd}/bin/systemd-analyze --user verify \
        "$unit" \
        ${toplevel}/etc/systemd/user/graphical-session.target

    touch "$out"
  ''
