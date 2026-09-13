{ config, pkgs, ... }:

{
  home.file.".emacs.d".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/code/my-dev-env/dotfiles/emacs";

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

  systemd.user.services.emacs.Service = {
    Slice = "app-graphical.slice";
    ExecStop =
      "${pkgs.emacs-pgtk}/bin/emacsclient --eval '(kill-emacs)'";
  };
}
