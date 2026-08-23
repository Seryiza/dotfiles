{
  description = "Seryiza's NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = { url = "github:nix-community/emacs-overlay"; };

    emacs-lsp-booster.url = "github:slotThe/emacs-lsp-booster-flake";

    xremap = { url = "github:xremap/nix-flake"; };

    zen-browser = { url = "github:0xc000022070/zen-browser-flake"; };

    bzmenu.url = "github:e-tho/bzmenu";
    iwmenu.url = "github:e-tho/iwmenu";
    rep.url = "github:eraserhd/rep";
    llm-agents.url = "github:numtide/llm-agents.nix";
    sysc-greet = {
      url = "github:Nomadcxx/sysc-greet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mango.url = "github:mangowm/mango";
    waybar.url = "github:Alexays/Waybar/09e69e0f48214a1128d62417612bc47e8dc9e36a";
    zed.url = "github:zed-industries/zed/v1.10.1";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nur,
      emacs-lsp-booster,
      xremap,
      sysc-greet,
      mango,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      unstablePackages = nixpkgs-unstable.legacyPackages.${system};
      riverOverlay = final: prev: {
        river = final.callPackage ./nixos/pkgs/river.nix {
          river = unstablePackages.river;
        };
        machi = final.callPackage ./nixos/pkgs/machi.nix { };
        channel = final.callPackage ./nixos/pkgs/channel.nix { };
        zelbar = final.callPackage ./nixos/pkgs/zelbar.nix { };
      };
      packages = import nixpkgs {
        inherit system;
        overlays = [ riverOverlay ];
      };
    in
    {
      packages.${system} = {
        inherit (packages) river machi channel zelbar;
      };

      checks.${system} =
        let
          yuriArtifacts = {
            homeGeneration =
              self.nixosConfigurations.yuri-alpha.config.home-manager.users.seryiza.home.activationPackage;
            toplevel = self.nixosConfigurations.yuri-alpha.config.system.build.toplevel;
          };
        in
        {
          waybar-session-profiles =
            packages.callPackage ./nixos/tests/waybar-session-profiles.nix yuriArtifacts;

          river-session-policy = packages.callPackage ./nixos/tests/river-session-policy.nix (
            yuriArtifacts // { inherit (packages) river machi channel; }
          );

          river-decoration-globals = packages.callPackage ./nixos/tests/river-decoration-globals.nix {
            inherit (packages) river;
          };

          zelbar-package = packages.callPackage ./nixos/tests/zelbar-package.nix {
            inherit (packages) zelbar;
          };

          river-xkb-shortcuts =
            packages.callPackage ./nixos/tests/river-xkb-shortcuts.nix yuriArtifacts;

          soteria-session-agent = packages.callPackage ./nixos/tests/soteria-session-agent.nix (
            yuriArtifacts
            // {
              inherit (packages) soteria;
              configuredPackages =
                self.nixosConfigurations.yuri-alpha.config.environment.systemPackages
                ++ self.nixosConfigurations.yuri-alpha.config.home-manager.users.seryiza.home.packages;
            }
          );
        };

      nixosConfigurations."yuri-alpha" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = inputs;
        modules = [
          {
            nixpkgs.overlays = [
              nur.overlays.default
              emacs-lsp-booster.overlays.default
              riverOverlay
              (final: prev: {
                jdk = final.zulu21;
                clojure = prev.clojure.override { jdk = final.zulu21; };
                smooth-scroll-linux =
                  final.callPackage ./nixos/pkgs/smooth-scroll-linux.nix { };
              })
            ];
          }

          ./nixos/configuration.nix
          sysc-greet.nixosModules.default
          (import ./nixos/home/mango.nix { inherit mango; }).nixosModule
          (import ./nixos/home/river.nix).nixosModule

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.users.seryiza = {
              imports = [
                (import ./nixos/home/mango.nix { inherit mango; }).homeManagerModule
                (import ./nixos/home/river.nix).homeManagerModule
                ./nixos/home.nix
              ];
            };
            home-manager.sharedModules = [ xremap.homeManagerModules.default ];
            home-manager.extraSpecialArgs = inputs;
          }

          nur.modules.nixos.default
        ];
      };
    };
}
