{ lib, pkgs, ... }:
let
  riverZelbarLauncher = pkgs.writeShellScript "river-zelbar-launcher" ''
    exec ${lib.getExe pkgs.river-zelbar-status} \
      --zelbar ${lib.getExe pkgs.zelbar} \
      --machictl ${lib.getExe' pkgs.machi "machictl"}
  '';

  riverZelbarUnit =
    pkgs.writeTextFile {
      name = "zelbar-river-unit";
      destination = "/zelbar-river.service";
      text = lib.generators.toINI { } {
        Unit = {
          Description = "Zelbar status panel for the River UWSM session";
          After = "wayland-session@river.target graphical-session.target";
          BindsTo = "wayland-session@river.target";
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "exec";
          ExecStart = riverZelbarLauncher;
          Restart = "on-failure";
          RestartSec = 2;
          KillMode = "control-group";
          TimeoutStopSec = 3;
          Slice = "app-graphical.slice";
        };
        Install.WantedBy = "wayland-session@river.target";
      };
    }
    + "/zelbar-river.service";
in
{
  home.packages = [
    pkgs.zelbar
    pkgs.river-zelbar-status
    (pkgs.iosevka-bin.override { variant = "SGr-Iosevka"; })
    pkgs.noto-fonts-color-emoji
  ];

  xdg.configFile = {
    "systemd/user/zelbar-river.service".source = riverZelbarUnit;
    "systemd/user/wayland-session@river.target.wants/zelbar-river.service".source = riverZelbarUnit;
  };
}
