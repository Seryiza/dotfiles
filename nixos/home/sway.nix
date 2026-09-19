{ config, pkgs, nixpkgs-unstable, lib, ... }: {
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    systemd.enable = false;
    package = pkgs.symlinkJoin {
      name = "sway-without-session-entry";
      paths = [
        nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.sway
      ];
      postBuild = ''
        rm -f $out/share/wayland-sessions/sway.desktop
      '';
    };

    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      # needs qt5.qtwayland in systemPackages
      export QT_QPA_PLATFORM=wayland
      export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
      # Fix for some Java AWT applications (e.g. Android Studio),
      # use this if they aren't displayed properly:
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';

    extraConfig = ''
      titlebar_border_thickness 2
      titlebar_padding 6 3
    '';

    config = {
      startup = [
        { command = "uwsm finalize"; }
        { command = "brightnessctl set 80%"; }
      ];

      modifier = "Mod4";

      bindkeysToCode = true;

      fonts = {
        names = [ "Iosevka" ];
        size = 8.0;
      };

      focus.followMouse = false;

      keybindings =
        let modifier = config.wayland.windowManager.sway.config.modifier;
        in lib.mkOptionDefault {
          "${modifier}+Alt+h" = "workspace prev";
          "${modifier}+Alt+l" = "workspace next";
          "${modifier}+Return" = "exec alacritty";
          "${modifier}+Escape" = "exec swaylock -c 000000";
          "${modifier}+Shift+e" = lib.mkForce "exec uwsm stop";
          "${modifier}+u" = "kill";
          "${modifier}+n" = ''exec wmenu-run -i -b -l 10 -f "Iosevka 14"'';
          "${modifier}+Alt+n" = ''exec wmenu-run -i -b -l 10 -f "Iosevka 14"'';
          "${modifier}+Alt+m" = lib.mkForce "exec emacsclient -c";
          "${modifier}+Shift+b" = "exec run-work-browser";
          "${modifier}+Alt+space" = "sticky toggle";
          "${modifier}+e" = "exec swaymsg exec -- QT_QPA_PLATFORM=xcb Enpass";
          "Print" = ''exec grim -g "$(slurp)" - | wl-copy'';
          "Ctrl+Print" = ''exec grim -g "$(slurp)"'';
          "Shift+Print" = "exec grim - | wl-copy | drawing -c";
          "XF86MonBrightnessUp" =
            "exec increase-backlight && display-backlight";
          "XF86MonBrightnessDown" =
            "exec decrease-backlight && display-backlight";
          "XF86AudioPlay" = "exec playerctl play-pause";
          "XF86AudioRaiseVolume" =
            "exec increase-current-volume && display-current-volume";
          "XF86AudioLowerVolume" =
            "exec decrease-current-volume && display-current-volume";
          "XF86AudioMicMute" =
            "exec toggle-microphone-mute && display-current-microphone";
          "XF86HomePage" =
            "exec toggle-microphone-mute && display-current-microphone";
          "XF86AudioMute" = "exec toggle-audio-mute && display-current-volume";
          "${modifier}+Shift+m" =
            "exec toggle-audio-mute && display-current-volume";
        };

      window = {
        border = 2;
        titlebar = false;

        commands = [
          {
            command = "border none";
            criteria = { app_id = "dev.benz.walker"; };
          }

          {
            command = "floating enable";
            criteria = { app_id = "dev.benz.walker"; };
          }

          {
            command = "sticky enable";
            criteria = { title = "Picture-in-Picture"; };
          }

          {
            command = "floating enable";
            criteria = { title = "Picture-in-Picture"; };
          }

          {
            command = "resize set width 300 height 150";
            criteria = { title = "Picture-in-Picture"; };
          }

          {
            command = "move position 0 0";
            criteria = { title = "Picture-in-Picture"; };
          }

          # Emacs Launcher
          {
            command = "floating enable";
            criteria = {
              app_id = "emacs";
              title = "^sway-app-launcher$";
            };
          }

          {
            command = "resize set width 900 px height 420 px";
            criteria = {
              app_id = "emacs";
              title = "^sway-app-launcher$";
            };
          }

          {
            command = "move position center";
            criteria = {
              app_id = "emacs";
              title = "^sway-app-launcher$";
            };
          }

          {
            command = "border pixel 2";
            criteria = {
              app_id = "emacs";
              title = "^sway-app-launcher$";
            };
          }
        ];
      };

      colors = {
        focused = {
          background = "#323232";
          border = "#000000";
          childBorder = "#323232";
          indicator = "#323232";
          text = "#FFFFFF";
        };
        unfocused = {
          background = "#FFFFFF";
          border = "#000000";
          childBorder = "#929292";
          indicator = "#929292";
          text = "#444444";
        };
        focusedInactive = {
          background = "#929292";
          border = "#000000";
          childBorder = "#929292";
          indicator = "#929292";
          text = "#FFFFFF";
        };
      };

      gaps = {
        left = 0;
        right = 0;
        top = 0;
        bottom = 0;
        inner = 5;
        smartGaps = true;
        smartBorders = "on";
      };

      input = {
        "type:touchpad" = {
          dwt = "enabled";
          tap = "enabled";
          tap_button_map = "lrm";
          natural_scroll = "enabled";
          middle_emulation = "enabled";
        };
        "type:keyboard" = {
          xkb_layout = "us,ru";
          xkb_options = "grp:ctrl_space_toggle";
        };
      };

      bars = [ ];

      output = {
        eDP-1 = {
          mode = "2560x1600@240Hz";
          scale = "2";
        };

        "*" = {
          bg = "#C9C5C0 solid_color";
          subpixel = "none";
        };
      };
    };
  };
}
