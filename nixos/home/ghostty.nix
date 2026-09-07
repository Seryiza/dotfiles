{ pkgs, ... }: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      font-family = "Iosevka";
      font-size = 13;
      theme = "Alabaster";
    };
  };
}
