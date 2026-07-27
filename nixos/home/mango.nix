{ mango }:
let
  mangoPackageFor =
    pkgs:
    pkgs.symlinkJoin {
      name = "mango-without-plain-session";
      paths = [ mango.packages.${pkgs.stdenv.hostPlatform.system}.mango ];
      # UWSM links all packages' Wayland session entries into the display
      # manager's session directory. Remove Mango's plain `Exec=mango` entry so
      # sysc-greet cannot bypass the UWSM-managed session.
      postBuild = ''
        rm -f $out/share/wayland-sessions/mango.desktop
      '';
    };
in
{
  nixosModule =
    { pkgs, ... }:
    {
      imports = [ mango.nixosModules.mango ];

      programs.mango = {
        enable = true;
        addLoginEntry = false;
        package = mangoPackageFor pkgs;
      };

      programs.uwsm.waylandCompositors.mango = {
        prettyName = "Mango";
        comment = "Mango compositor managed by UWSM";
        binPath = "/run/current-system/sw/bin/mango";
      };
    };

  homeManagerModule =
    { config, pkgs, ... }:
    {
      imports = [ mango.hmModules.mango ];

      wayland.windowManager.mango = {
        enable = true;
        package = mangoPackageFor pkgs;
        settings = {
          exec-once = [
            "uwsm finalize"
            "brightnessctl set 80%"
          ];

          monitorrule = "name:^eDP-1$,width:2560,height:1600,refresh:240,x:0,y:0,scale:2";

          # Mango assigns layouts per tag. Make monocle the initial layout on every tag.
          tagrule = map (tag: "id:${toString tag},layout_name:monocle") (
            builtins.genList (index: index + 1) 9
          );
          circle_layout = "scroller,tile,monocle";

          # Keep Telegram's transient media viewer out of the scroller layout.
          # Match both fields so the main Telegram window remains tiled.
          windowrule = [
            ''isfloating:1,appid:^org\.telegram\.desktop$,title:^Media viewer$''
          ];

          # Scroller geometry and window-width presets.
          scroller_structs = 40;
          scroller_proportion_preset = "0.5,0.75,1.0";

          gappih = 6;
          gappiv = 6;
          gappoh = 6;
          gappov = 6;
          borderpx = 3;
          rootcolor = "0xffffffff";
          bordercolor = "0xd3d3d3ff";
          focuscolor = "0x000000ff";

          animations = 0;
          layer_animations = 0;

          cursor_theme = config.home.pointerCursor.name;
          cursor_size = config.home.pointerCursor.size;

          xkb_rules_layout = "us,ru";
          xkb_rules_options = "ctrl:nocaps,grp:ctrl_space_toggle";

          tap_to_click = 1;
          button_map = 0;
          trackpad_natural_scrolling = 1;
          disable_while_typing = 1;
          middle_button_emulation = 1;
          sloppyfocus = 0;
          focus_on_activate = 0;

          bind = [
            "SUPER,Return,spawn,alacritty"
            "SUPER,Escape,spawn,${pkgs.swaylock}/bin/swaylock -c 000000"
            "SUPER+SHIFT,e,spawn,uwsm stop"
            "SUPER,u,killclient"
            "SUPER,f,togglefullscreen,"
            "SUPER,Tab,toggleoverview"
            "SUPER+SHIFT,Tab,togglejump"
            "SUPER,bracketleft,switch_layout"
            "SUPER,j,focusstack,next"
            "SUPER,k,focusstack,prev"
            "SUPER+ALT,j,exchange_stack_client,next"
            "SUPER+ALT,k,exchange_stack_client,prev"
            "SUPER,l,viewtoright,0"
            "SUPER,h,viewtoleft,0"
            "SUPER+ALT,l,tagtoright,0"
            "SUPER+ALT,h,tagtoleft,0"
            "SUPER,n,spawn,wmenu-run -i -b -l 10 -f 'Iosevka 14'"
            "SUPER+ALT,n,spawn,wmenu-run -i -b -l 10 -f 'Iosevka 14'"
            "SUPER,m,spawn,emacsclient -c"
            "SUPER+ALT,m,spawn,emacsclient -c"
            "SUPER+SHIFT,b,spawn,run-work-browser"
            "SUPER,e,spawn,env QT_QPA_PLATFORM=xcb Enpass"
          ]
          ++ builtins.concatMap (tag: [
            "CTRL,${toString tag},view,${toString tag},0"
            "ALT,${toString tag},tag,${toString tag},0"
            "ALT+SHIFT,${toString tag},toggletag,${toString tag}"
          ]) (builtins.genList (index: index + 1) 9)
          ++ [
            ''NONE,Print,spawn_shell,grim -g "$(slurp)" - | wl-copy''
            ''CTRL,Print,spawn_shell,grim -g "$(slurp)"''
            "SHIFT,Print,spawn_shell,grim - | wl-copy | drawing -c"

            "NONE,XF86MonBrightnessUp,spawn_shell,increase-backlight && display-backlight"
            "NONE,XF86MonBrightnessDown,spawn_shell,descrease-backlight && display-backlight"
            "NONE,XF86AudioPlay,spawn,playerctl play-pause"
            "NONE,XF86AudioRaiseVolume,spawn_shell,increase-current-volume && display-current-volume"
            "NONE,XF86AudioLowerVolume,spawn_shell,decrease-current-volume && display-current-volume"
            "NONE,XF86AudioMicMute,spawn_shell,toggle-microphone-mute && display-current-microphone"
            "NONE,XF86HomePage,spawn_shell,toggle-microphone-mute && display-current-microphone"
            "NONE,XF86AudioMute,spawn_shell,toggle-audio-mute && display-current-volume"
            "SUPER+SHIFT,m,spawn_shell,toggle-audio-mute && display-current-volume"

            "SUPER,r,switch_proportion_preset"
            "SUPER+ALT,r,reload_config"
          ];
        };
      };
    };
}
