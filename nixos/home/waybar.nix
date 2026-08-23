{
  config,
  lib,
  pkgs,
  waybar,
  ...
}:
let
  barHeight = 20;
  waybarPackage = waybar.packages.${pkgs.stdenv.hostPlatform.system}.default;
  jsonFormat = pkgs.formats.json { };

  genericModulesBeforeLanguage = [
    "custom/org_timeblock"
    "custom/org_clock"
    "privacy"
    "wireplumber"
    "network"
    "custom/wireguard"
  ];
  genericModulesAfterLanguage = [
    "battery"
    "clock"
    "tray"
  ];
  genericModules = genericModulesBeforeLanguage ++ genericModulesAfterLanguage;

  commonModuleSettings = {
    "custom/org_timeblock" = {
      align = 0.0;
      exec = "${config.home.homeDirectory}/.local/bin/waybar-org-timeblock";
      interval = 15;
      format = "{text}";
      max-length = 60;
      escape = true;
      hide-empty-text = true;
    };

    "custom/org_clock" = {
      align = 0.0;
      exec = "${config.home.homeDirectory}/.local/bin/waybar-org-current-clock";
      interval = 15;
      format = "{text}";
      max-length = 60;
      escape = true;
      hide-empty-text = true;
    };

    "custom/wireguard" = {
      align = 0.0;
      format = "{text}";
      exec = "${config.home.homeDirectory}/.local/bin/waybar-wireguard short";
      interval = 15;
      return-type = "json";
    };

    privacy = {
      icon-size = 10;
      icon-spacing = 0;
    };

    tray = {
      orientation = "horizontal";
      spacing = 4;
      expand = false;
    };

    battery = {
      align = 0.0;
      format = "{capacity}% battery";
      format-full = "";
    };

    clock = {
      align = 0.0;
      interval = 60;
      format = "{:%d %b %H:%M}";
      tooltip = true;
      tooltip-format = "{:%A, %d %B %Y}\n\n{tz_list}\n\n<tt><small>{calendar}</small></tt>";
      timezone-tooltip-format = "{:%Z: %H:%M}";
      timezones = [
        "Asia/Bishkek"
        "Europe/Copenhagen"
        "Asia/Sakhalin"
        "Europe/Moscow"
        "Etc/UTC"
      ];

      calendar = {
        mode = "month";
        weeks-pos = "right";
        on-scroll = 1;
        format = {
          months = "<span color='#ffead3'><b>{}</b></span>";
          days = "<span color='#ecc6d9'><b>{}</b></span>";
          weeks = "<span color='#99ffdd'><b>W{}</b></span>";
          weekdays = "<span color='#ffcc66'><b>{}</b></span>";
          today = "<span color='#ff6699'><b><u>{}</u></b></span>";
        };
      };

      actions = {
        on-click = "shift_reset";
        on-click-right = "mode";
        on-click-forward = "tz_up";
        on-click-backward = "tz_down";
        on-scroll-up = "shift_up";
        on-scroll-down = "shift_down";
      };
    };

    network = {
      align = 0.0;
      # A five-entry icon table maps signal strength to 20-point buckets.
      # Render text only for the 0..19% bucket and hide stronger signals.
      format = "";
      format-wifi = "{icon}";
      format-icons = [
        "<20% wlan"
        ""
        ""
        ""
        ""
      ];
      format-ethernet = "";
      format-linked = "{ifname} (No IP)";
      format-disconnected = "Disconnected";
      format-disabled = "Wi-Fi disabled";
      tooltip-format-wifi = ''
        {essid} ({signalStrength}%)
        {ifname}: {ipaddr}/{cidr}'';
    };

    wireplumber = {
      align = 0.0;
      format = "{volume}% {node_name}{format_source}";
      format-muted = "MUTED {node_name}{format_source}";
      format-source = " +MIC";
      format-source-muted = "";
      tooltip-format = "{node_name}: {volume}%{format_source}";
    };
  };

  topBar = commonModuleSettings // {
    name = "top";
    layer = "top";
    position = "top";
    height = barHeight;
    spacing = 0;
    modules-left = [ ];
    modules-center = [ ];
    modules-right = genericModules;
  };

  mangoProfile = jsonFormat.generate "waybar-mango.json" [
    (
      topBar
      // {
        modules-left = [ "mango/window" ];
        modules-right = genericModulesBeforeLanguage ++ [ "mango/language" ] ++ genericModulesAfterLanguage;

        "mango/taskbar" = {
          format = "{title}";
          justify = "left";
          truncate = true;
          # Mango app IDs are exact; inspect them with `mmsg get all-clients`.
          app-labels = {
            Alacritty = "A";
            Emacs = "E";
            emacs = "E";
            firefox = "F";
            "org.telegram.desktop" = "T";
          };
          app-label-width = 16;
          tooltip = true;
          tooltip-format = "{title}";
          on-click = "activate";
          on-click-middle = "close";
          on-click-right = "minimize";
        };

        "sway/language" = {
          align = 0.0;
        };

        "mango/language" = {
          align = 0.0;
          format = "{short}";
        };

        "mango/layout" = {
          format = "{}";
          format-S = "Scroller";
          format-T = "Tile";
          format-M = "Monocle";
        };
      }
    )
    {
      name = "bottom";
      layer = "top";
      position = "bottom";
      height = barHeight;
      spacing = 0;
      modules-left = [ "mango/workspaces" ];
      modules-center = [ ];
      modules-right = [ ];

      "mango/workspaces" = {
        orientation = "horizontal";
        homogeneous = true;
        height = barHeight;
        format = "{icon}";
        hide-empty = false;
        on-click = "activate";
        on-click-right = "toggle";
        overview-label = "OVERVIEW";
      };
    }
  ];
  genericProfile = jsonFormat.generate "waybar-generic.json" [ topBar ];

  profileBySessionIdentity = {
    mango = "mango";
    river = "generic";
    sway = "generic";
  };
  profileCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      identity: profile: "${identity}) profile=${profile} ;;"
    ) profileBySessionIdentity
  );

  profileLauncher = pkgs.writeShellScript "waybar-session-profile" ''
    case "$1" in
      ${profileCases}
      *)
        echo "Unsupported Waybar session identity: $1" >&2
        exit 64
        ;;
    esac

    exec ${waybarPackage}/bin/waybar \
      --config ${config.xdg.configHome}/waybar/"$profile".json \
      --style ${config.xdg.configHome}/waybar/style.css
  '';

  waybarUnit =
    pkgs.writeTextFile {
      name = "waybar-template-unit";
      destination = "/waybar@.service";
      text = lib.generators.toINI { } {
        Unit = {
          Description = "Waybar for the %I UWSM session";
          Documentation = "https://github.com/Alexays/Waybar/wiki";
          After = "wayland-session@%i.target graphical-session.target";
          BindsTo = "wayland-session@%i.target";
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "exec";
          ExecStart = "${profileLauncher} %i";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
          KillMode = "mixed";
          Restart = "on-failure";
          Slice = "app-graphical.slice";
        };
        Install.WantedBy = "wayland-session@%i.target";
      };
    }
    + "/waybar@.service";

  sessionIdentities = builtins.attrNames profileBySessionIdentity;
  instanceLinks = builtins.listToAttrs (
    map (identity: {
      name = "systemd/user/wayland-session@${identity}.target.wants/waybar@${identity}.service";
      value.source = waybarUnit;
    }) sessionIdentities
  );
in
{
  programs.waybar = {
    enable = true;
    package = waybarPackage;
    systemd.enable = false;
    style = builtins.readFile ./waybar.css;
  };

  xdg.configFile = {
    "waybar/mango.json".source = mangoProfile;
    "waybar/generic.json".source = genericProfile;
    "systemd/user/waybar@.service".source = waybarUnit;
  }
  // instanceLinks;
}
