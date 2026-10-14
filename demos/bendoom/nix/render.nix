{ lib, callPackage, runCommand, bend, pname, root, sources, iwad }:

let
  inherit (lib.meta) getExe;
  inherit (lib.strings) escapeShellArg;

  program = callPackage ./program.nix {
    inherit bend root sources;
    pname = "${pname}-program";
  };
in
runCommand pname { } /* bash */ ''
  BENDOOM_IWAD=${escapeShellArg iwad} ${getExe program} --threads 1
  mkdir $out
  for hex in *.hex; do
    basenc --base16 -d "$hex" > "$out/''${hex%.hex}.raw"
  done
''
