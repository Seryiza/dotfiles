{
  pkgs,
  nixpkgs-unstable,
  ...
}@inputs:
let
  system = pkgs.stdenv.hostPlatform.system;
  unstable-pkgs = import nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
  llm-agents-pkgs = inputs.llm-agents.packages.${system};
  glamoroustoolkit-vm = unstable-pkgs.glamoroustoolkit.overrideAttrs (_: rec {
    version = "1.1.67";
    src = unstable-pkgs.fetchzip {
      url = "https://github.com/feenkcom/gtoolkit-vm/releases/download/v${version}/GlamorousToolkit-x86_64-unknown-linux-gnu.zip";
      stripRoot = false;
      hash = "sha256-5vHOPJ0EZ0+G/849FCS5HLzq47CCD4eMpPh67n/698A=";
    };
  });
  glamoroustoolkit = pkgs.buildEnv {
    name = "glamoroustoolkit";
    paths = [ glamoroustoolkit-vm ];
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };
in
{
  home.packages = [
    pkgs.httpie
    pkgs.gnumake
    pkgs.smooth-scroll-linux
    pkgs.sops

    (pkgs.iosevka-bin.override { variant = "SGr-Iosevka"; })
    (pkgs.iosevka-bin.override { variant = "SGr-IosevkaSlab"; })
    pkgs.go-font

    pkgs.yaru-theme
    pkgs.libcanberra-gtk3
    pkgs.steam-run

    llm-agents-pkgs.claude-code
    llm-agents-pkgs.claude-agent-acp
    llm-agents-pkgs.codex
    llm-agents-pkgs.codex-acp
    llm-agents-pkgs.pi
    inputs.omp.packages.${system}.omp
    llm-agents-pkgs.qmd
    llm-agents-pkgs.spec-kit

    (pkgs.google-cloud-sdk.withExtraComponents [
      pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])

    pkgs.google-chrome
    pkgs.kubectl
    pkgs.dropbox
    pkgs.bun
    pkgs.mission-center
    unstable-pkgs.telegram-desktop
    glamoroustoolkit
    # unstable because of https://github.com/NixOS/nixpkgs/issues/500724
    unstable-pkgs.enpass
    pkgs.postgresql_17
    pkgs.onlyoffice-desktopeditors
    pkgs.gh
    pkgs.evince
    pkgs.inkscape
    pkgs.comfortaa
    pkgs.less
    pkgs.pciutils
    pkgs.clinfo
    pkgs.vulkan-tools
    pkgs.dbeaver-bin
    pkgs.gparted
    pkgs.p7zip
    pkgs.unrar
    pkgs.hyprpicker
    pkgs.gimp
    pkgs.wireguard-tools
    pkgs.python3
    pkgs.python312Packages.pip
    pkgs.wf-recorder
    pkgs.ffmpeg-full
    pkgs.video-trimmer
    pkgs.libvterm
    pkgs.cmake
    pkgs.libtool
    pkgs.polylith
    pkgs.cifs-utils
    pkgs.celluloid
    pkgs.terraform
    pkgs.uxn
    pkgs.leiningen
    pkgs.act
    pkgs.appimage-run
    pkgs.lsb-release
    pkgs.dmidecode
    pkgs.jq
    pkgs.qbittorrent
    pkgs.rclone
    pkgs.wl-clipboard
    pkgs.wmenu
    pkgs.grim
    pkgs.slurp
    pkgs.silver-searcher
    unstable-pkgs.clj-kondo
    unstable-pkgs.cljfmt
    pkgs.ntfs3g
    pkgs.libnotify
    pkgs.iw
    pkgs.brightnessctl
    pkgs.drawing
    pkgs.thunar
    pkgs.nemo-with-extensions
    pkgs.clojure-lsp
    pkgs.lua-language-server
    pkgs.nil
    pkgs.ripgrep
    pkgs.jdk
    pkgs.zprint
    pkgs.geckodriver
    pkgs.amberol
    pkgs.gcc
    pkgs.nodejs
    pkgs.unzip
    pkgs.clojure
    pkgs.babashka
    pkgs.emacs-lsp-booster
    inputs.zed.packages.${system}.default
    pkgs.htop
    pkgs.rocmPackages.rocminfo
    pkgs.rocmPackages.rocm-smi
    pkgs.evtest
    pkgs.chntpw
    pkgs.nixfmt
    inputs.zen-browser.packages.${system}.default
    inputs.rep.packages.${system}.default
    pkgs.wev
    pkgs.xarchiver
    pkgs.lsof
    pkgs.file
    pkgs.openssl
    pkgs.qrencode
    pkgs.xray
    pkgs.k9s
    pkgs.vtsls
    pkgs.typescript-language-server
    pkgs.devd
    pkgs.gnome-calendar
    pkgs.php
    pkgs.bbin
    pkgs.go
    pkgs.scrcpy
    pkgs.android-tools
    pkgs.libdecor
    pkgs.loupe
    pkgs.nautilus
    pkgs.exercism
    unstable-pkgs.ollama
    unstable-pkgs.llama-cpp
    pkgs.gnome-font-viewer
    pkgs.pnpm
    pkgs.epiphany
    pkgs.chez
    pkgs.cambalache
    pkgs.postman
    pkgs.insomnia
    pkgs.baobab
    pkgs.uv
  ];
}
