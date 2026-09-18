{ config, osConfig, pkgs, ... }:

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
      osConfig.programs.ewm.ewmPackage
    ];
  };

  services.emacs = {
    enable = true;
    package = config.programs.emacs.finalPackage;
    client.enable = false;
    defaultEditor = false;
    socketActivation.enable = false;
    startWithUserSession = "graphical";
  };

  systemd.user.services.emacs.Unit.ConditionEnvironment = "!XDG_CURRENT_DESKTOP=ewm";

  home.sessionVariables = {
    EDITOR = "${config.programs.emacs.finalPackage}/bin/emacsclient --reuse-frame";
    VISUAL = "${config.programs.emacs.finalPackage}/bin/emacsclient --reuse-frame";
    SUDO_EDITOR = "${config.programs.emacs.finalPackage}/bin/emacsclient --reuse-frame";
  };

  xdg.desktopEntries = {
    # Shadow Home Manager's profile entry: this desktop ID is for MIME files,
    # not a no-file menu action.
    emacsclient = {
      name = "Emacs Client";
      exec = "${config.programs.emacs.finalPackage}/bin/emacsclient --reuse-frame %F";
      icon = "emacs";
      noDisplay = true;
    };

    emacs-client-frame = {
      name = "New Emacs Client Frame";
      comment = "Create an Emacs client frame";
      exec = "${config.programs.emacs.finalPackage}/bin/emacsclient -c";
      icon = "emacs";
      categories = [ "Development" "TextEditor" ];
    };

    emacs-ewm-workspace = {
      name = "New EWM Workspace";
      comment = "Create a native EWM workspace";
      exec = "${config.programs.emacs.finalPackage}/bin/emacsclient --eval \"(ewm-frame-new)\"";
      icon = "emacs";
      categories = [ "Development" "TextEditor" ];
    };

    emacs = {
      name = "Emacs — Separate Process";
      comment = "Start a separate Emacs process";
      exec = "${config.programs.emacs.finalPackage}/bin/emacs";
      icon = "emacs";
      categories = [ "Development" "TextEditor" ];
    };
  };

  systemd.user.services.emacs.Service = {
    Slice = "app-graphical.slice";
    ExecStop =
      "${config.programs.emacs.finalPackage}/bin/emacsclient --eval '(kill-emacs)'";
  };
}
