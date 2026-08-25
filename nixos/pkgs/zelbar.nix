{
  fcft,
  fetchFromSourcehut,
  lib,
  pixman,
  pkg-config,
  stdenv,
  wayland,
  wayland-protocols,
  wayland-scanner,
  zig_0_15,
}:
let
  zig = zig_0_15;
  rev = "b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932";
  sourceHash = "sha256-r5kJ7FOSAluytSsQztV8CRHQ63flpFeBOpVZY6CAVbM=";
  zigDepsHash = "sha256-OKrDhSBSa0Sro1zj8+YPMqrxtNfWIgvvCctcQDe3O98=";
  hidpiPatch = ./zelbar-hidpi.patch;
  hidpiPatchHash = "sha256-VpCCTjfMrpwobBqg6/9uHt5I5Zq3HETZc3Kz5+SMZT0=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zelbar";
  version = "1.2.0";

  src = fetchFromSourcehut {
    owner = "~novakane";
    repo = "zelbar";
    inherit rev;
    hash = sourceHash;
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    fetchAll = true;
    hash = zigDepsHash;
  };

  patches = [ hidpiPatch ];

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    zig
  ];

  buildInputs = [
    fcft
    pixman
    wayland
    wayland-protocols
    wayland-scanner
  ];

  postConfigure = ''
    cp -rLT ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  doCheck = true;

  passthru = {
    inherit
      rev
      sourceHash
      zigDepsHash
      hidpiPatch
      hidpiPatchHash
      ;
  };

  meta = {
    description = "Wayland status bar reading input from standard input";
    homepage = "https://git.sr.ht/~novakane/zelbar";
    license = lib.licenses.gpl3Only;
    mainProgram = "zelbar";
    platforms = lib.platforms.linux;
  };
})
