{ ewm }:
{
  nixosModule =
    { config, pkgs, ... }:
    let
      ewmPackage = pkgs.callPackage "${ewm}/nix/default.nix" {
        emacsPackage = pkgs.emacs-pgtk;
      };
    in
    {
      imports = [ "${ewm}/nix/service.nix" ];

      # The pinned EWM recipe names the 0.3 ABI explicitly; 26.05 exposes
      # that ABI as the unversioned libdisplay-info package.
      nixpkgs.overlays = [
        (final: prev: { libdisplay-info_0_3 = prev.libdisplay-info; })
      ];

      programs.ewm = {
        enable = true;
        inherit ewmPackage;
        emacsPackage = config.home-manager.users.seryiza.programs.emacs.finalPackage;
      };

      services.gnome.gcr-ssh-agent.enable = false;
      environment.systemPackages = [ pkgs.xwayland-satellite ];

      # This takes precedence over the pinned module's config package only for
      # the ewm desktop.  Other sessions keep their existing portal routing.
      xdg.portal.config.ewm = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.Access" = [ "gtk" ];
        "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
      };
    };
}
