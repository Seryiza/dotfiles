{ pkgs, ... }: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      font-family = "Iosevka";
      font-feature = "-calt, -liga, -dlig";
      font-size = 13;
      theme = "Alabaster";
      window-padding-balance = true;
      window-padding-color = "extend";
      resize-overlay = "never";
      mouse-scroll-multiplier = "discrete:0.75";
      quit-after-last-window-closed = false;
    };
  };
}
