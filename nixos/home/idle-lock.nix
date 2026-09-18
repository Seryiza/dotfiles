{ lib, pkgs, ... }:
let
  lockCommand = "${pkgs.swaylock}/bin/swaylock -fF -c 000000";
in
{
  programs.swaylock.enable = true;

  services.swayidle = {
    enable = true;

    events = {
      "before-sleep" = lockCommand;
    };

    timeouts = [
      {
        timeout = 600;
        command = lockCommand;
      }
      {
        timeout = 630;
        command = "${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
    ];
  };

  systemd.user.services.swayidle.Unit.ConditionEnvironment = lib.mkForce [
    "WAYLAND_DISPLAY"
    "!XDG_CURRENT_DESKTOP=ewm"
  ];

  systemd.user.services.swayidle-ewm = {
    Unit = {
      Description = "Idle manager for the EWM session";
      Documentation = "man:swayidle(1)";
      ConditionEnvironment = [
        "WAYLAND_DISPLAY"
        "XDG_CURRENT_DESKTOP=ewm"
      ];
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      Restart = "always";
      Environment = [ "PATH=${lib.makeBinPath [ pkgs.bash ]}" ];
      ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 600 ${lib.escapeShellArg lockCommand} before-sleep ${lib.escapeShellArg lockCommand}";
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.wayland-pipewire-idle-inhibit = {
    Unit = {
      Description = "Inhibit Wayland idle while media is playing";
      Documentation = "https://github.com/rafaelrc7/wayland-pipewire-idle-inhibit";
      After = [
        "graphical-session.target"
        "pipewire.service"
      ];
      Wants = [ "pipewire.service" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${pkgs.wayland-pipewire-idle-inhibit}/bin/wayland-pipewire-idle-inhibit --wayland --media-minimum-duration 5";
      Restart = "always";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
