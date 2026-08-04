{
  config,
  pkgs,
  waybar-src,
  ...
}:
let
  barHeight = 20;
in
{
  programs.waybar = {
    enable = true;
    package =
      (pkgs.waybar.override {
        cavaSupport = false;
      }).overrideAttrs
        (old: {
          src = waybar-src;
          nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.xvfb-run ];
          patches = (old.patches or [ ]) ++ [
            ./waybar-mango-taskbar.patch
            ./waybar-mango-workspaces.patch
            ./waybar-mango-tests.patch
            ./waybar-mango-taskbar-widget-tests.patch
            ./waybar-module-halign.patch
            ./waybar-tray-orientation.patch
          ];
          mesonFlags = old.mesonFlags ++ [
            "-Dmango=true"
            "-Dwwan=disabled"
          ];
        });
    systemd.enable = true;
    systemd.targets = [ "graphical-session.target" ];

    settings = [
      {
        name = "right";
        layer = "top";
        position = "right";
        width = 250;
        spacing = 0;
        modules-right-halign = "fill";
        modules-left = [
          "mango/workspaces"
          "mango/taskbar"
        ];
        modules-center = [ ];
        modules-right = [
          "custom/org_timeblock"
          "custom/org_clock"
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

        "privacy" = {
          icon-size = 12;
          icon-spacing = 0;
        };
        "tray" = {
          orientation = "horizontal";
          spacing = 4;
          expand = false;
        };
        "battery" = {
          align = 0.0;
          format = "{capacity}% battery";
          format-full = "";
        };
        "clock" = {
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
        "network" = {
          align = 0.0;
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
          align = 0.0;
          format = "{volume}% {node_name}{format_source}";
          format-muted = "MUTED {node_name}{format_source}";
          format-source = " +MIC";
          format-source-muted = "";
          tooltip-format = "{node_name}: {volume}%{format_source}";
        };

      }

      # {
      #   name = "top";
      #   layer = "top";
      #   position = "top";
      #   height = barHeight;
      #   spacing = 0;
      #   modules-left = [
      #     "privacy"
      #     "wireplumber"
      #     "network"
      #     "custom/wireguard"
      #     "sway/language"
      #     "mango/language"
      #     "battery"
      #     "clock"
      #     "tray"
      #   ];
      #   modules-center = [ ];
      #   modules-right = [ "mango/layout" ];

      #   "custom/wireguard" = {
      #     format = "{text}";
      #     exec = "${config.home.homeDirectory}/.local/bin/waybar-wireguard short";
      #     interval = 15;
      #     return-type = "json";
      #   };

      #   "mango/language" = {
      #     format = "{short}";
      #   };

      #   "mango/layout" = {
      #     format = "{}";
      #     format-S = "Scroller";
      #     format-T = "Tile";
      #     format-M = "Monocle";
      #   };

      #   "privacy" = {
      #     icon-size = 12;
      #     icon-spacing = 0;
      #   };
      #   "battery" = {
      #     format = "{capacity}% battery";
      #     format-full = "";
      #   };
      #   "clock" = {
      #     interval = 60;
      #     format = "{:%d %b %H:%M}";
      #     tooltip = true;
      #     tooltip-format = "{:%A, %d %B %Y}\n\n{tz_list}\n\n<tt><small>{calendar}</small></tt>";
      #     timezone-tooltip-format = "{:%Z: %H:%M}";
      #     timezones = [
      #       "Asia/Bishkek"
      #       "Europe/Copenhagen"
      #       "Asia/Sakhalin"
      #       "Europe/Moscow"
      #       "Etc/UTC"
      #     ];

      #     calendar = {
      #       mode = "month";
      #       weeks-pos = "right";
      #       on-scroll = 1;
      #       format = {
      #         months = "<span color='#ffead3'><b>{}</b></span>";
      #         days = "<span color='#ecc6d9'><b>{}</b></span>";
      #         weeks = "<span color='#99ffdd'><b>W{}</b></span>";
      #         weekdays = "<span color='#ffcc66'><b>{}</b></span>";
      #         today = "<span color='#ff6699'><b><u>{}</u></b></span>";
      #       };
      #     };

      #     actions = {
      #       on-click = "shift_reset";
      #       on-click-right = "mode";
      #       on-click-forward = "tz_up";
      #       on-click-backward = "tz_down";
      #       on-scroll-up = "shift_up";
      #       on-scroll-down = "shift_down";
      #     };
      #   };
      #   "network" = {
      #     # Waybar does not expose arbitrary numeric format conditions for
      #     # signalStrength. A five-entry format-icons table maps to 20-point
      #     # buckets, so only the 0..19% bucket renders text; empty buckets hide
      #     # the module.
      #     format = "";
      #     format-wifi = "{icon}";
      #     format-icons = [
      #       "<20% wlan"
      #       ""
      #       ""
      #       ""
      #       ""
      #     ];
      #     format-ethernet = "";
      #     format-linked = "{ifname} (No IP)";
      #     format-disconnected = "Disconnected";
      #     format-disabled = "Wi-Fi disabled";
      #     tooltip-format-wifi = ''
      #       {essid} ({signalStrength}%)
      #       {ifname}: {ipaddr}/{cidr}'';
      #   };
      #   "wireplumber" = {
      #     format = "{volume}% {node_name}{format_source}";
      #     format-muted = "MUTED {node_name}{format_source}";
      #     format-source = " +MIC";
      #     format-source-muted = "";
      #     tooltip-format = "{node_name}: {volume}%{format_source}";
      #   };
      # }
    ];

    style = builtins.readFile ./waybar.css;
  };
}
