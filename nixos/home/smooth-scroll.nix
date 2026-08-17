{ lib, pkgs, ... }:
{
  xdg.configFile."smooth-scroll/smooth-scroll.toml".source = ./smooth-scroll.toml;

  systemd.user.services.smooth-scroll = {
    Unit = {
      Description = "Smooth Scroll daemon";
      Documentation = "https://github.com/Wayne6530/smooth-scroll-linux";
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.smooth-scroll-linux} -c %h/.config/smooth-scroll/smooth-scroll.toml";
      Restart = "on-failure";
      RestartSec = 5;
      # Upstream v1.4.0 handles SIGINT, but not systemd's default SIGTERM.
      KillSignal = "SIGINT";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
