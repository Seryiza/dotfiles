{
  pkgs,
  zelbar,
}:
let
  sourceAfterPatchPhase = zelbar.overrideAttrs {
    pname = "zelbar-source-after-patch-phase";
    nativeBuildInputs = [ ];
    buildInputs = [ ];
    zigDeps = null;
    postConfigure = null;
    doCheck = false;
    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];
    installPhase = ''
      cp -a . "$out"
    '';
  };
in
assert zelbar.version == "1.2.0";
assert zelbar.rev == "b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932";
assert zelbar.sourceHash == "sha256-r5kJ7FOSAluytSsQztV8CRHQ63flpFeBOpVZY6CAVbM=";
assert zelbar.zigDepsHash == "sha256-OKrDhSBSa0Sro1zj8+YPMqrxtNfWIgvvCctcQDe3O98=";
assert (zelbar.patches or [ ]) == [ ];
assert !(zelbar ? prePatch);
assert !(zelbar ? postPatch);
assert !(zelbar ? patchPhase);
pkgs.runCommand "zelbar-package-check"
  {
    nativeBuildInputs = [ pkgs.diffutils ];
  }
  ''
    diff --recursive --no-dereference ${zelbar.src} ${sourceAfterPatchPhase}
    version="$(${zelbar}/bin/zelbar -version 2>&1)"
    test "$version" = 1.2.0
    touch "$out"
  ''
