{
  buildGoModule,
  dbus,
  emacs,
  lib,
  machi,
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
in
buildGoModule {
  pname = "river-zelbar-status";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  vendorHash = "sha256-/w1E2h0/EOmyxc7PQ1yqyQjqM+FKml1JBoP7uMf8zBQ=";

  subPackages = [ "cmd/river-zelbar-status" ];
  ldflags = [
    "-X main.zelbarDefault=${zelbar}/bin/zelbar"
    "-X main.machictlDefault=${machi}/bin/machictl"
    "-X main.orgTimeblockDefault=${orgTimeblock}/bin/waybar-org-timeblock"
    "-X main.wpctlDefault=${wireplumber}/bin/wpctl"
  ];
  doCheck = true;
  nativeCheckInputs = [ dbus ];
  checkPhase = ''
    runHook preCheck
    go test ${lib.optionalString stdenv.hostPlatform.isLinux "-race"} ./...
    runHook postCheck
  '';

  meta = {
    description = "Supervised River status producer for pinned Zelbar";
    mainProgram = "river-zelbar-status";
    platforms = lib.platforms.linux;
  };
}
