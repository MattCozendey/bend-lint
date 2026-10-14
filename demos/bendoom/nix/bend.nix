# Bend is a TypeScript program bun runs as is; clang 19 serves its C
# backend (14 suffices on the CPU, 19 for the GPU lane). The patch
# paints the window by walking the frame's tree once, where the pin
# walks it from the root for every pixel
# (.scratch/upstream-bend/issues/01-slow-window-fill.md).
{ lib, stdenvNoCC, makeWrapper, bun, llvmPackages_19, src }:

let
  inherit (lib.lists) singleton;
  inherit (lib.strings) makeBinPath;
  inherit (lib.licenses) asl20;
  inherit (lib.platforms) unix;
in
stdenvNoCC.mkDerivation {
  pname = "bend";
  version = "2.0.26";
  inherit src;

  patches = singleton ./window-fill.patch;

  nativeBuildInputs = singleton makeWrapper;

  dontBuild = true;

  installPhase = /* bash */ ''
    runHook preInstall
    mkdir -p $out/share/bend $out/bin
    cp -r bend2 guide $out/share/bend/
    makeWrapper ${bun}/bin/bun $out/bin/bend \
      --add-flags "$out/share/bend/bend2/main.ts" \
      --set BEND_NO_TELEMETRY 1 \
      --set-default CC ${llvmPackages_19.clang}/bin/clang \
      --prefix PATH : ${makeBinPath (singleton llvmPackages_19.clang)}
    runHook postInstall
  '';

  meta = {
    description = "A fast language that blocks AI mistakes via proof";
    homepage = "https://bend-lang.com";
    license = asl20;
    mainProgram = "bend";
    platforms = unix;
  };
}
