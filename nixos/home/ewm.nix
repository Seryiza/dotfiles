{ ewm }:
{
  nixosModule =
    { config, pkgs, ... }:
    let
      ewmPackage = (pkgs.callPackage "${ewm}/nix/default.nix" {
        emacsPackage = pkgs.emacs-pgtk;
      }).overrideAttrs (old: {
        packageRequires = map (dependency:
          if dependency.pname == "ewm-core" then
            dependency.overrideAttrs (core: {
              patches = (core.patches or [ ]) ++ [ ../pkgs/ewm-preserve-xkb-layout.patch ];
              doCheck = true;
              cargoTestFlags = [ "--test" "input_hotpath_integration" ];
              # The compositor's capture/intercept state is process-global.
              checkFlags = [ "--test-threads=1" ];
            })
          else dependency
        ) old.packageRequires;
      });
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
