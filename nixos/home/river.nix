let
  riverInitFor =
    pkgs:
    pkgs.writeShellApplication {
      name = "river-init";
      runtimeInputs = with pkgs; [
        channel
        coreutils
        machi
        uwsm
        wlr-randr
      ];
      text = builtins.readFile ../../scripts/river-init;
    };

  riverPackageFor =
    pkgs:
    pkgs.symlinkJoin {
      name = "river-with-session-policy";
      paths = [ pkgs.river ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm -f $out/share/wayland-sessions/river.desktop
        wrapProgram $out/bin/river \
          --add-flags "-c ${riverInitFor pkgs}/bin/river-init"
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
      powerSaver = pkgs.writeShellApplication {
        name = "river-power-saver";
        text = ''
          ${pkgs.tlp-pd}/bin/tlpctl power-saver
          ${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --mode 2560x1600@60Hz
        '';
      };
      powerBalanced = pkgs.writeShellApplication {
        name = "river-power-balanced";
        text = ''
          ${pkgs.tlp-pd}/bin/tlpctl balanced
          ${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --mode 2560x1600@240Hz
        '';
      };
      enpassX11 = pkgs.writeShellScript "run-enpass-x11" ''
        exec env QT_QPA_PLATFORM=xcb Enpass
      '';
      machiConfig = builtins.replaceStrings
        [
          "@cursorTheme@"
          "@cursorSize@"
          "@enpassX11@"
          "@swaylock@"
          "@uwsm@"
          "@wmenu@"
          "@powerSaver@"
          "@powerBalanced@"
        ]
        [
          config.home.pointerCursor.name
          (toString config.home.pointerCursor.size)
          (toString enpassX11)
          (toString pkgs.swaylock)
          (toString pkgs.uwsm)
          (toString pkgs.wmenu)
          (toString powerSaver)
          (toString powerBalanced)
        ]
        (builtins.readFile ../../dotfiles/machi.ini);
    in
    {
      home.packages = [
        powerSaver
        powerBalanced
        pkgs.machi
        pkgs.channel
        pkgs.wlr-randr
      ];

      xdg.configFile."machi/machi.ini".text = machiConfig;

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
