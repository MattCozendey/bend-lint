{ lib, llvmPackages_19, bend, pname, root, sources, buildInputs ? [ ] }:

let
  inherit (lib.filesystem) baseNameOf;
  inherit (lib.fileset) toSource unions;
  inherit (lib.lists) singleton;
  inherit (lib.trivial) readFile;
in
llvmPackages_19.stdenv.mkDerivation {
  inherit pname;
  version = "0.1.0";

  src = toSource {
    root = ../.;
    fileset = unions (singleton root ++ sources);
  };

  nativeBuildInputs = singleton bend;
  inherit buildInputs;

  buildPhase = /* bash */ ''
    runHook preBuild
    export HOME=$TMPDIR
    ${readFile ./compile.sh}
    compile_bend ${baseNameOf root} program ${if llvmPackages_19.stdenv.hostPlatform.isDarwin then "darwin" else "linux"}
    runHook postBuild
  '';

  installPhase = /* bash */ ''
    runHook preInstall
    install -Dm755 program $out/bin/program
    runHook postInstall
  '';

  meta.mainProgram = "program";
}
