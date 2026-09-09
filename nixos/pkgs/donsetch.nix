{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  cmake,
  go,
  gitMinimal,
  nasm,
  lld,
  perl,
  pkg-config,
  openssl,
  chromium,
  jq,
}:
let
  # These are the exact native payloads pinned by upstream build.rs.
  pdfium = fetchurl {
    url = "https://github.com/kognitos/pdfium-static/releases/download/chromium/7809/pdfium-linux-x64-static.tgz";
    sha256 = "13908bb2d40a6e017c4c5a6a7baecc6efd7b1c30392c8a79e80072d2b48b18eb";
  };
  onnx = fetchurl {
    url = "https://github.com/microsoft/onnxruntime/releases/download/v1.24.2/onnxruntime-linux-x64-1.24.2.tgz";
    sha256 = "43725474ba5663642e17684717946693850e2005efbd724ac72da278fead25e6";
  };
in
rustPlatform.buildRustPackage {
  pname = "donsetch";
  version = "3.6.7";

  src = fetchFromGitHub {
    owner = "dondai44423";
    repo = "donsetch";
    rev = "24e6ee8855e068d8868c6a7c1ce96446aac4f324";
    hash = "sha256-5/OdWjarm9ey/oZ5J2OXhkN7eGsvvck+JcSK0P567rM=";
  };
  cargoHash = "sha256-13CdykjUGyCHVd72ER1Ij6/SpmxpZkX+dxcu47V2u+w=";
  buildNoDefaultFeatures = true;
  buildFeatures = [ "ocr" "rerank" ];

  nativeBuildInputs = [
    rustPlatform.bindgenHook
    autoPatchelfHook
    makeWrapper
    cmake
    go
    gitMinimal
    nasm
    lld
    perl
    pkg-config
  ];
  buildInputs = [ stdenv.cc.cc.lib openssl ];
  dontUseCmakeConfigure = true;

  postPatch = ''
    mkdir -p vendor/pdfium vendor/onnx
    tar -xzf ${pdfium} -C vendor/pdfium
    tar -xzf ${onnx} -C vendor/onnx --strip-components=2 \
      onnxruntime-linux-x64-1.24.2/lib/libonnxruntime.so.1.24.2
    mv vendor/onnx/libonnxruntime.so.1.24.2 vendor/onnx/libonnxruntime.so
  '';

  # Upstream's integration suite needs the network and a running browser.
  doCheck = false;
  postInstall = ''
    # find_shared_lib() looks beside current_exe(), including the wrapped binary.
    ln -s ../lib/libonnxruntime.so "$out/bin/libonnxruntime.so"
    wrapProgram "$out/bin/donsetch" \
      --set-default DONGHOST_CHROME ${lib.getExe chromium}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ jq ];
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/donsetch" tools | jq -e '
      (.tools | map(.name) | sort) == ["web_crawl", "web_fetch", "web_search"] and
      all(.tools[]; .inputSchema.type == "object")
    '
    runHook postInstallCheck
  '';

  meta = {
    description = "Web fetch, search and crawl for AI agents";
    homepage = "https://github.com/dondai44423/donsetch";
    license = lib.licenses.agpl3Only;
    mainProgram = "donsetch";
    platforms = [ "x86_64-linux" ];
  };
}
