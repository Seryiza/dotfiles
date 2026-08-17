{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  fmt,
  libevdev,
  spdlog,
  tomlplusplus,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "smooth-scroll-linux";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "Wayne6530";
    repo = "smooth-scroll-linux";
    tag = "v${finalAttrs.version}";
    hash = "sha256-6Q5Odm3YedXGp1v6L0+wMXOoU37xmLjUaZ+ulYojO70=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    fmt
    libevdev
    spdlog
    tomlplusplus
  ];

  postPatch = ''
    sed -i '/include(FetchContent)/,/FetchContent_MakeAvailable(tomlplusplus)/d' CMakeLists.txt
    substituteInPlace CMakeLists.txt \
      --replace-fail 'set(GIT_DESCRIBE "0.0.0-unknown")' \
                     'set(GIT_DESCRIBE "v${finalAttrs.version}")'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 smooth-scroll "$out/bin/smooth-scroll"
    runHook postInstall
  '';

  meta = {
    description = "System-level physics-based smooth scrolling daemon for Linux";
    homepage = "https://github.com/Wayne6530/smooth-scroll-linux";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "smooth-scroll";
  };
})
