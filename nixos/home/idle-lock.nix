{ pkgs, ... }:
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
