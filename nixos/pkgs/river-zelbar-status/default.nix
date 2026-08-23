{
  buildGoModule,
  lib,
  stdenv,
}:

buildGoModule {
  pname = "river-zelbar-status";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  vendorHash = "sha256-eVTmOA2A3wA6CmdOkuiM0pQlA059J6ekpOUC3ZwtZ1A=";

  subPackages = [ "cmd/river-zelbar-status" ];
  doCheck = true;
  checkFlags = lib.optionals stdenv.hostPlatform.isLinux [ "-race" ];

  meta = {
    description = "Supervised River status producer for unmodified Zelbar";
    mainProgram = "river-zelbar-status";
    platforms = lib.platforms.linux;
  };
}
