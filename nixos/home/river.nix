let
  riverInitFor =
    pkgs:
    pkgs.writeShellScript "river-init" ''
      set -eu

      ${pkgs.machi}/bin/machi &
      machi_pid=$!
      ${pkgs.channel}/bin/channel &
      channel_pid=$!

      cleanup() {
        kill "$machi_pid" "$channel_pid" 2>/dev/null || true
      }
      trap cleanup EXIT HUP INT TERM

      ${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --mode 2560x1600@240Hz --pos 0,0 --scale 2

      # Give both policy processes a chance to bind River's globals and reject
      # invalid configuration before declaring the UWSM session ready.
      sleep 0.1
      kill -0 "$machi_pid" "$channel_pid"
      ${pkgs.uwsm}/bin/uwsm finalize

      trap - EXIT HUP INT TERM
    '';

  riverPackageFor =
    pkgs:
    pkgs.symlinkJoin {
      name = "river-with-session-policy";
      paths = [ pkgs.river ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm -f $out/share/wayland-sessions/river.desktop
        wrapProgram $out/bin/river \
          --add-flags "-c ${riverInitFor pkgs}"
      '';
    };
in
{
  nixosModule = { pkgs, ... }: {
    environment.systemPackages = [ (riverPackageFor pkgs) ];

    programs.uwsm.waylandCompositors.river = {
      prettyName = "River";
      comment = "River compositor managed by UWSM";
      binPath = "/run/current-system/sw/bin/river";
    };
  };

  homeManagerModule =
    { config, pkgs, ... }:
    let
      enpassX11 = pkgs.writeShellScript "run-enpass-x11" ''
        exec env QT_QPA_PLATFORM=xcb Enpass
      '';
      microphoneHomePage = pkgs.writeShellScript "toggle-river-microphone" ''
        toggle-microphone-mute && display-current-microphone
      '';
    in
    {
      home.packages = [
        pkgs.machi
        pkgs.channel
        pkgs.wlr-randr
      ];

      xdg.configFile."machi/machi.ini".text = ''
        [geometry]
        gap-size=20
        border-width=2

        [cursor]
        theme=${config.home.pointerCursor.name}
        size=${toString config.home.pointerCursor.size}

        [colors]
        background=ffffff
        focused-border=000000
        unfocused-border=d3d3d3

        [keybindings.wm]
        reload-config=super+ctrl+shift+r

        [keybindings.workspace]
        cycle-next=super+comma
        cycle-prev=super+period
        add-next=super+ctrl+comma
        add-prev=super+ctrl+period

        [keybindings.panel]
        cycle-next=super+l
        cycle-prev=super+h
        add-next=super+alt+l
        add-prev=super+alt+h
        move-to-next-workspace=super+shift+comma
        move-to-prev-workspace=super+shift+period
        move-to-next-new-workspace=super+ctrl+shift+comma
        move-to-prev-new-workspace=super+ctrl+shift+period
        toggle-split-view=super+s

        [keybindings.window]
        cycle-next=super+k
        cycle-prev=super+j
        move-next=super+shift+k
        move-prev=super+shift+j
        split-toggle=super+tab
        split-swap=super+shift+tab
        move-to-next-panel=super+shift+l
        move-to-prev-panel=super+shift+h
        move-to-next-new-panel=super+ctrl+shift+l
        move-to-prev-new-panel=super+ctrl+shift+h
        toggle-fullscreen=super+f
        close=super+u

        [keybindings.spawn]
        alacritty=super+return
        ${pkgs.swaylock}/bin/swaylock -c 000000=super+escape
        ${pkgs.uwsm}/bin/uwsm stop=super+shift+e
        ${pkgs.wmenu}/bin/wmenu-run -i -b -l 10 -f 'Iosevka 14'=super+n
        emacsclient -c=super+m
        firefox=super+b
        run-work-browser=super+shift+b
        ${enpassX11}=super+e
        grim -g "$(slurp)" - | wl-copy=print
        grim -g "$(slurp)"=ctrl+print
        grim - | wl-copy | drawing -c=shift+print
        increase-backlight && display-backlight=XF86MonBrightnessUp
        decrease-backlight && display-backlight=XF86MonBrightnessDown
        playerctl play-pause=XF86AudioPlay
        increase-current-volume && display-current-volume=XF86AudioRaiseVolume
        decrease-current-volume && display-current-volume=XF86AudioLowerVolume
        toggle-microphone-mute && display-current-microphone=XF86AudioMicMute
        ${microphoneHomePage}=XF86HomePage
        toggle-audio-mute && display-current-volume=XF86AudioMute
        toggle-audio-mute && display-current-volume=super+shift+m
      '';

      xdg.configFile."xkb/rules/evdev".source = ../xkb/rules/evdev;
      xdg.configFile."xkb/types/custom".source = ../xkb/types/custom;
      xdg.configFile."xkb/symbols/custom".source = ../xkb/symbols/custom;

      xdg.configFile."river/config.rh".text = ''
        input {
            profiles {
                keyboard {
                    keyboard {
                        layout us,ru
                        options grp:ctrl_space_toggle,custom:types,custom:positional-latin-shortcuts
                    }
                }

                touchpad {
                    libinput {
                        tap_to_click true
                        tap_button_map lrm
                        natural_scroll true
                        disable_while_typing true
                        middle_mouse_emulation true
                    }
                }
            }

            rules [
                type, keyboard, keyboard
                name, *Touchpad, touchpad
            ]
        }
      '';
    };
}
