{ config, pkgs, ... }:
let
  chromeExecutable = pkgs.lib.getExe' pkgs.google-chrome "google-chrome-stable";
in {
  imports = [
    ./home/sway.nix
    ./home/mako.nix
    ./home/packages.nix
    ./home/alacritty.nix
    ./home/waybar.nix
    ./home/email.nix
    ./home/xremap.nix
    ./home/emacs.nix
  ];

  wayland.windowManager.mango = {
    enable = true;
    settings = {
      monitorrule = "name:^eDP-1$,width:2560,height:1600,refresh:240,x:0,y:0,scale:2";
      bind = [
        "SUPER,Return,spawn,alacritty"
        "SUPER,n,spawn,wmenu-run -i -b -l 10 -f 'Iosevka 14'"
        "SUPER,q,killclient"
        "SUPER+SHIFT,e,quit"
        "SUPER,r,reload_config"
      ];
    };
  };

  xsession.enable = true;

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    WLR_DRM_NO_ATOMIC = "1";
    GRIM_DEFAULT_DIR = "$HOME/Pictures/Screenshots";
    SUDO_EDITOR = "emacsclient -c -a emacs";
    BROWSER = "firefox";
    CHROME_EXECUTABLE = chromeExecutable;
  };

  home.sessionVariables.LOCALES_ARCHIVE =
    "${pkgs.glibcLocales}/lib/locale/locale-archive";

  home.sessionPath =
    [ "$HOME/.local/bin" "$HOME/go/bin" "$HOME/.cache/npm/global/bin" ];

  gtk = {
    enable = true;
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
  };
  xdg.enable = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/ftp" = [ "firefox.desktop" ];
      "text/plain" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/markdown" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-shellscript" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-yaml" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-toml" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-python" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-c" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-c++" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-go" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-rust" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-java" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-kotlin" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-clojure" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-lua" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-php" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-ruby" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-perl" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-sql" = [ "emacsclient.desktop" "emacs.desktop" ];
      "text/x-makefile" = [ "emacsclient.desktop" "emacs.desktop" ];
      "application/json" = [ "emacsclient.desktop" "emacs.desktop" ];
      "application/xml" = [ "emacsclient.desktop" "emacs.desktop" ];
      "image/jpeg" = [ "org.gnome.Loupe.desktop" ];
      "image/png" = [ "org.gnome.Loupe.desktop" ];
      "image/gif" = [ "org.gnome.Loupe.desktop" ];
      "image/webp" = [ "org.gnome.Loupe.desktop" ];
      "image/tiff" = [ "org.gnome.Loupe.desktop" ];
      "image/x-tga" = [ "org.gnome.Loupe.desktop" ];
      "image/vnd-ms.dds" = [ "org.gnome.Loupe.desktop" ];
      "image/x-dds" = [ "org.gnome.Loupe.desktop" ];
      "image/bmp" = [ "org.gnome.Loupe.desktop" ];
      "image/vnd.microsoft.icon" = [ "org.gnome.Loupe.desktop" ];
      "image/vnd.radiance" = [ "org.gnome.Loupe.desktop" ];
      "image/x-exr" = [ "org.gnome.Loupe.desktop" ];
      "image/x-portable-bitmap" = [ "org.gnome.Loupe.desktop" ];
      "image/x-portable-graymap" = [ "org.gnome.Loupe.desktop" ];
      "image/x-portable-pixmap" = [ "org.gnome.Loupe.desktop" ];
      "image/x-portable-anymap" = [ "org.gnome.Loupe.desktop" ];
      "image/x-qoi" = [ "org.gnome.Loupe.desktop" ];
      "image/qoi" = [ "org.gnome.Loupe.desktop" ];
      "image/svg+xml" = [ "org.gnome.Loupe.desktop" ];
      "image/svg+xml-compressed" = [ "org.gnome.Loupe.desktop" ];
      "image/avif" = [ "org.gnome.Loupe.desktop" ];
      "image/heic" = [ "org.gnome.Loupe.desktop" ];
      "image/jxl" = [ "org.gnome.Loupe.desktop" ];
    };
  };

  home.file = {
    ".emacs.d".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/code/my-dev-env/dotfiles/emacs";

    ".local/bin/waybar-org-timeblock" = {
      source = ../scripts/waybar-org-timeblock;
      executable = true;
      force = true;
    };

    ".local/bin/waybar-org-current-clock" = {
      source = ../scripts/waybar-org-current-clock;
      executable = true;
      force = true;
    };

    ".local/bin/sway-smart-focus" = {
      source = ../scripts/sway-smart-focus;
      executable = true;
      force = true;
    };

    ".local/bin/sway-smart-close" = {
      source = ../scripts/sway-smart-close;
      executable = true;
      force = true;
    };

    ".local/bin/sway-smart-open" = {
      source = ../scripts/sway-smart-open;
      executable = true;
      force = true;
    };

    # ".npmrc".text = ''
    #   registry=https://registry.npmjs.org/
    #   prefix=${config.home.homeDirectory}/.cache/npm/global
    # '';
  };

  home.pointerCursor = {
    package = pkgs.rose-pine-cursor;
    name = "BreezeX-RosePineDawn-Linux";
    size = 35;
    gtk.enable = true;
    sway.enable = true;
    x11 = { enable = true; };
  };

  programs.password-store = {
    enable = true;
    package = pkgs.pass.withExtensions (exts: [ exts.pass-otp ]);
    settings = { PASSWORD_STORE_DIR = "$HOME/.password-store/"; };
  };

  programs.neovim = {
    enable = true;
    withPython3 = true;
    withRuby = true;
    plugins = [ pkgs.vimPlugins.packer-nvim ];
  };

  programs.firefox = {
    enable = true;
    configPath = ".mozilla/firefox";
    policies = {
      AppAutoUpdate = false;
      DisableAppUpdate = true;
      DisablePocket = true;
      DisableTelemetry = true;
      NoDefaultBookmarks = true;
      DefaultDownloadDirectory = "\${home}/Downloads";
    };

    profiles = {
      default = {
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          violentmonkey
        ];
        search = { engines = { }; };
      };
    };
  };

  programs.mpv = { enable = true; };

  programs.bash = {
    enable = true;
    initExtra = ''
      export CHROME_EXECUTABLE="${chromeExecutable}"
    '';
    bashrcExtra = builtins.readFile ../dotfiles/bashrc;
  };

  programs.gpg = { enable = true; };

  services.gpg-agent = {
    enable = true;
    enableBashIntegration = true;
    pinentry.package = pkgs.pinentry-qt;
    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;
  };

  programs.git = {
    enable = true;
    ignores = [ ".direnv" ".envrc" "/.agent-shell" ];
    settings = {
      user = {
        email = "git@seryiza.xyz";
        name = "Sergey Zaborovsky";
        signingkey = "D551D39D7C487647";
      };

      commit = { gpgsign = true; };
      tag = { gpgSign = true; };
      core = { };
      interactive = { };
      delta = {
        features = "decorations light";
        true-color = "always";
      };
      init = { defaultBranch = "master"; };
      push = { autoSetupRemote = "true"; };
    };
  };

  services.playerctld.enable = true;

  services.syncthing.enable = true;

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  services.activitywatch = {
    enable = true;
    watchers = {
      aw-watcher-window-wayland = { package = pkgs.aw-watcher-window-wayland; };
    };
  };

  systemd.user.services."activitywatch-watcher-aw-watcher-window-wayland" = {
    # On login this unit can start before sway exposes a Wayland socket.
    # Retrying prevents the watcher from staying dead until manual restart.
    Unit.StartLimitIntervalSec = 0;
    Service = {
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  home.stateVersion = "23.11";
}
