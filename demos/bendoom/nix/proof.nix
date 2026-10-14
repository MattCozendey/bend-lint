{ lib, stdenvNoCC, bend }:

let
  inherit (lib.fileset) toSource unions;
  inherit (lib.lists) singleton;
in
stdenvNoCC.mkDerivation {
  pname = "bendoom-proof";
  version = "0.1.0";

  src = toSource {
    root = ../.;
    fileset = unions [
      ../doom.bend
      ../src
      ../LAWS.bend
      ../PROOF.bend
      ../tests/fixtures/closed.bend
    ];
  };

  nativeBuildInputs = singleton bend;

  buildPhase = /* bash */ ''
    runHook preBuild
    export HOME=$TMPDIR
    bend PROOF.bend | tee proof.log
    grep -q "All terms check." proof.log
    runHook postBuild
  '';

  installPhase = /* bash */ ''
    install -Dm644 proof.log $out/proof.log
  '';
}
