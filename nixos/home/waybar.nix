{
  config,
  pkgs,
  waybar-src,
  ...
}:
{
  programs.waybar = {
    enable = true;
    package = pkgs.waybar.overrideAttrs (old: {
      src = waybar-src;
      mesonFlags = old.mesonFlags ++ [
        "-Dmango=true"
        "-Dwwan=disabled"
        "-Dcava=disabled"
      ];
    });
    systemd.enable = true;
    systemd.targets = [ "graphical-session.target" ];

    settings = [
      {
        name = "top";
        layer = "top";
        position = "top";
        height = 20;
        spacing = 0;
        modules-left = [
          "sway/window"
          "mango/window"
        ];
        modules-center = [ ];
        modules-right = [
          "privacy"
          "wireplumber"
          "network"
          "custom/wireguard"
          "sway/language"
          "mango/language"
          "battery"
          "clock"
          "tray"
        ];

        "custom/wireguard" = {
          format = "{text}";
          exec = "${config.home.homeDirectory}/.local/bin/waybar-wireguard.sh short";
          interval = 15;
          return-type = "json";
        };
        "sway/workspaces" = {
          disable-scroll = true;
        };

        "mango/window" = {
          format = "{}";
          icon-size = 20;
          max-length = 80;
        };

        "mango/language" = {
          format = "{short}";
        };

        "privacy" = {
          icon-size = 12;
          icon-spacing = 0;
        };
        "battery" = {
          format = "{capacity}% battery";
          format-full = "";
        };
        "clock" = {
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
        "network" = {
          # Waybar does not expose arbitrary numeric format conditions for
          # signalStrength. A five-entry format-icons table maps to 20-point
          # buckets, so only the 0..19% bucket renders text; empty buckets hide
          # the module.
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
        "wireplumber" = {
          format = "{volume}% {node_name}{format_source}";
          format-muted = "MUTED {node_name}{format_source}";
          format-source = " +MIC";
          format-source-muted = "";
          tooltip-format = "{node_name}: {volume}%{format_source}";
        };
      }

      {
        name = "bottom";
        layer = "top";
        position = "bottom";
        height = 20;
        spacing = 0;
        modules-left = [
          "sway/mode"
          "sway/scratchpad"
          "custom/org_timeblock"
          "custom/org_clock"
        ];
        modules-center = [ ];
        modules-right = [
          "mango/layout"
          "sway/workspaces"
          "mango/workspaces"
        ];

        "mango/layout" = {
          format = "{}";
          format-S = "Scroller";
          format-T = "Tile";
        };

        "mango/workspaces" = {
          format = "{icon}";
          hide-empty = false;
          on-click = "activate";
          on-click-right = "toggle";
          overview-label = "OVERVIEW";
        };

        "custom/org_timeblock" = {
          exec = "${config.home.homeDirectory}/.local/bin/waybar-org-timeblock";
          interval = 15;
          format = "{text}";
          max-length = 60;
          escape = true;
          hide-empty-text = true;
        };

        "custom/org_clock" = {
          exec = "${config.home.homeDirectory}/.local/bin/waybar-org-current-clock";
          interval = 15;
          format = "{text}";
          max-length = 60;
          escape = true;
          hide-empty-text = true;
        };
      }
    ];

    style = builtins.readFile ./waybar.css;
  };
}
