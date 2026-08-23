{
  lib,
  stdenv,
  fetchFromCodeberg,
  libxkbcommon,
  pkg-config,
  river,
  wayland,
  wayland-protocols,
  wayland-scanner,
  zig_0_16,
}:
let
  zig = zig_0_16;
  rev = "4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "channel";
  version = "0.4.1";

  src = fetchFromCodeberg {
    owner = "Sivecano";
    repo = "channel";
    inherit rev;
    hash = "sha256-AIP5SO7p2Z8fYeLSoIliSya2fQALV1xkkYfIRdHY6TQ=";
  };

  # Channel 0.4.1 does not expose River's tap-button-map protocol request.
  # Keep the pinned release as the source while adding the missing policy knob.
  patches = [ ./channel-tap-button-map.patch ];

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    fetchAll = true;
    hash = "sha256-RD/0GMhzh26P2Hxb/5ksLC4kvLNOG489ojbFwwscIr8=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    zig
  ];

  buildInputs = [
    libxkbcommon
    river
    wayland
    wayland-protocols
    wayland-scanner
  ];

  postConfigure = ''
    cp -rLT ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  passthru = { inherit rev; };

  meta = {
    description = "Input configuration manager for River";
    homepage = "https://codeberg.org/Sivecano/channel";
    license = lib.licenses.agpl3Only;
    mainProgram = "channel";
    platforms = lib.platforms.linux;
  };
})
