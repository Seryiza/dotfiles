{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
    extraPackages = epkgs: [
      epkgs.mu4e
      epkgs.vterm
      epkgs.melpaPackages.telega
    ];
  };

  services.emacs = {
    enable = true;
    client.enable = true;
    defaultEditor = true;
    startWithUserSession = "graphical";
  };
}
