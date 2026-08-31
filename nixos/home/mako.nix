{ pkgs, ... }:
let
  volumeSound = "${pkgs.yaru-theme}/share/sounds/Yaru/stereo/audio-volume-change.oga";
  patchedMako = pkgs.mako.overrideAttrs (oldAttrs: {
    # Remove when https://github.com/emersion/mako/issues/655 is fixed upstream.
    patches = (oldAttrs.patches or [ ]) ++ [
      ../pkgs/mako-retry-busy-buffer.patch
    ];
  });
in
{
  services.mako = {
    enable = true;
    package = patchedMako;
    settings = {
      icons = false;
      "background-color" = "#000000";
      "text-color" = "#ffffff";
      "border-size" = 0;
      layer = "overlay";

      "app-name=ya-vol" = {
        history = 0;
        anchor = "top-center";
        group-by = "app-name";
        format = "<b>%s</b>%b";
        "on-notify" =
          "exec ${pkgs.libcanberra-gtk3}/bin/canberra-gtk-play --cache-control=volatile --file=${volumeSound}";
      };

      "app-name=ya-backlight" = {
        history = 0;
        anchor = "top-center";
        group-by = "app-name";
        format = "<b>%s</b>%b";
      };
    };
  };
}
