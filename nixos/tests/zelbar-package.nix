{
  pkgs,
  zelbar,
}:
let
  expectedUpstreamSource = pkgs.fetchFromSourcehut {
    owner = "~novakane";
    repo = "zelbar";
    rev = "b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932";
    hash = "sha256-r5kJ7FOSAluytSsQztV8CRHQ63flpFeBOpVZY6CAVbM=";
  };
  expectedPatchedSource = pkgs.applyPatches {
    name = "zelbar-expected-patched-source";
    src = expectedUpstreamSource;
    patches = [
      zelbar.hidpiPatch
      zelbar.gapTruncationPatch
    ];
  };
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
assert zelbar.src.rev == zelbar.rev;
assert zelbar.src.url == "https://git.sr.ht/~novakane/zelbar/archive/${zelbar.rev}.tar.gz";
assert zelbar.src.outputHash == zelbar.sourceHash;
assert zelbar.zigDepsHash == "sha256-OKrDhSBSa0Sro1zj8+YPMqrxtNfWIgvvCctcQDe3O98=";
assert zelbar.hidpiPatchHash == "sha256-VpCCTjfMrpwobBqg6/9uHt5I5Zq3HETZc3Kz5+SMZT0=";
assert
  builtins.hashFile "sha256" zelbar.hidpiPatch
  == "5690824e37ccae9c286c1aa0ebff6e1ede48e59ab71c44d97372b3e7e48c653d";
assert zelbar.gapTruncationPatchHash == "sha256-0Ypo7go8+er+cppIloWd9AIFKigN7Y0CmRh6FQSR8Yg=";
assert
  builtins.hashFile "sha256" zelbar.gapTruncationPatch
  == "d18a68ee0a3cf9eafe729a4896859df402052a280ded8d0299187a150491f188";
assert (zelbar.patches or [ ]) == [
  zelbar.hidpiPatch
  zelbar.gapTruncationPatch
];
assert !(zelbar ? postUnpack);
assert !(zelbar ? unpackPhase);
assert !(zelbar ? prePatch);
assert !(zelbar ? postPatch);
assert !(zelbar ? patchPhase);
assert !(zelbar ? preConfigure);
assert !(zelbar ? configurePhase);
assert !(zelbar ? preBuild);
assert !(zelbar ? postBuild);
assert !(zelbar ? buildPhase);
assert !(zelbar ? preCheck);
assert !(zelbar ? postCheck);
assert !(zelbar ? checkPhase);
assert !(zelbar ? preInstall);
assert !(zelbar ? postInstall);
assert !(zelbar ? installPhase);
assert !(zelbar ? preFixup);
assert !(zelbar ? postFixup);
assert !(zelbar ? fixupPhase);
assert
  zelbar.postConfigure == ''
    cp -rLT ${zelbar.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';
pkgs.runCommand "zelbar-package-check"
  {
    nativeBuildInputs = [ pkgs.diffutils ];
  }
  ''
    diff --recursive --no-dereference ${expectedPatchedSource} ${sourceAfterPatchPhase}
    version="$(${zelbar}/bin/zelbar -version 2>&1)"
    test "$version" = 1.2.0
    touch "$out"
  ''
