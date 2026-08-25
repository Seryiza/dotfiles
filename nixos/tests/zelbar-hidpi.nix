{
  pkgs,
  zelbar,
  river,
  machi,
}:
pkgs.runCommand "zelbar-hidpi-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];

    FONTCONFIG_FILE = pkgs.makeFontsConf {
      fontDirectories = [ pkgs.dejavu_fonts ];
    };

    RIVER = "${river}/bin/river";
    MACHI = "${machi}/bin/machi";
    WLR_RANDR = "${pkgs.wlr-randr}/bin/wlr-randr";
    ZELBAR = "${zelbar}/bin/zelbar";
    FC_MATCH = "${pkgs.fontconfig}/bin/fc-match";
    GRIM = "${pkgs.grim}/bin/grim";
    PYTHON = "${pkgs.python3.withPackages (python: [ python.pillow ])}/bin/python3";
    TRACE_ASSERT = ./zelbar-hidpi-trace.py;
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$XDG_CONFIG_HOME"

    bash ${./zelbar-hidpi.sh}
    touch "$out"
  ''
