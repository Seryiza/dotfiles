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
}
