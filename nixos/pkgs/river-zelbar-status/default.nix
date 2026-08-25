{
  bash,
  buildGoModule,
  coreutils,
  emacs,
  gawk,
  jq,
  lib,
  machi,
  networkmanager,
  stdenv,
  systemd,
  wireplumber,
  writeShellApplication,
  zelbar,
}:
let
  orgTimeblock = writeShellApplication {
    name = "waybar-org-timeblock";
    runtimeInputs = [ systemd emacs ];
    text = builtins.readFile ../../../scripts/waybar-org-timeblock;
  };
  orgClock = writeShellApplication {
    name = "waybar-org-current-clock";
    runtimeInputs = [ systemd emacs ];
    text = builtins.readFile ../../../scripts/waybar-org-current-clock;
  };
  wireGuard = writeShellApplication {
    name = "waybar-wireguard";
    runtimeInputs = [ bash coreutils gawk jq networkmanager ];
    text = builtins.readFile ../../../scripts/waybar-wireguard;
  };
in
buildGoModule {
  pname = "river-zelbar-status";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  vendorHash = "sha256-YKqCeXbHaaxoHmUC1/4Z0GIym3qxcqzh5SVaA+7ZI/o=";

  subPackages = [ "cmd/river-zelbar-status" ];
  ldflags = [
    "-X main.zelbarDefault=${zelbar}/bin/zelbar"
    "-X main.machictlDefault=${machi}/bin/machictl"
    "-X main.orgTimeblockDefault=${orgTimeblock}/bin/waybar-org-timeblock"
    "-X main.orgClockDefault=${orgClock}/bin/waybar-org-current-clock"
    "-X main.wireGuardDefault=${wireGuard}/bin/waybar-wireguard"
    "-X main.wpctlDefault=${wireplumber}/bin/wpctl"
    "-X main.nmcliDefault=${networkmanager}/bin/nmcli"
  ];
  doCheck = true;
  checkFlags = lib.optionals stdenv.hostPlatform.isLinux [ "-race" ];

  meta = {
    description = "Supervised River status producer for pinned Zelbar";
    mainProgram = "river-zelbar-status";
    platforms = lib.platforms.linux;
  };
}
