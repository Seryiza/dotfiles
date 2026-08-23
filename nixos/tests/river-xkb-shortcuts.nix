{ pkgs, homeGeneration, ... }:
pkgs.runCommand "river-xkb-shortcuts-check"
  {
    nativeBuildInputs = [
      pkgs.libxkbcommon
      pkgs.pkg-config
      pkgs.stdenv.cc
    ];
  }
  ''
    export XDG_CONFIG_HOME=${homeGeneration}/home-files/.config

    cc ${./river-xkb-shortcuts.c} \
      $(${pkgs.pkg-config}/bin/pkg-config --cflags --libs xkbcommon) \
      -o river-xkb-shortcuts
    ./river-xkb-shortcuts

    touch "$out"
  ''
