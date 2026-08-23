{
  lib,
  stdenv,
  fetchFromCodeberg,
  libxkbcommon,
  pkg-config,
  scdoc,
  wayland,
  wayland-protocols,
  wayland-scanner,
  zig_0_16,
}:
let
  zig = zig_0_16;
  rev = "65a0fc12f2796f41f4c9cbb7e034aaa137009b01";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "machi";
  version = "0.5.0-dev-${builtins.substring 0 7 rev}";

  src = fetchFromCodeberg {
    owner = "machi";
    repo = "machi";
    inherit rev;
    hash = "sha256-StpGIGnIjtdEQ9fWdsei6n93IJOG6BG7gRKaOS9sI24=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    fetchAll = true;
    hash = "sha256-AHPg1FHHx/9/gfcj9E7s5/WZ2dLf00DWf9QsMVxOY3s=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    scdoc
    wayland-scanner
    zig
  ];

  buildInputs = [
    libxkbcommon
    wayland
    wayland-protocols
    wayland-scanner
  ];

  postPatch = ''
    substituteInPlace build.zig \
      --replace-fail 'const sha = b.run(&.{ "git", "rev-parse", "HEAD" });' \
                     'const sha: ?[]const u8 = "${rev}";'
  '';

  postConfigure = ''
    cp -rLT ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  doCheck = true;

  passthru = { inherit rev; };

  meta = {
    description = "Window manager for River with cascading windows, panels, and workspaces";
    homepage = "https://codeberg.org/machi/machi";
    license = lib.licenses.isc;
    mainProgram = "machi";
    platforms = lib.platforms.linux;
  };
})
