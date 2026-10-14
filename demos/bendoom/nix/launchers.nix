{ lib, runCommand, nushell, bash, dash, shellcheck }:

let
  inherit (lib.fileset) toSource unions;
in
runCommand "bendoom-launcher-tests" {
  nativeBuildInputs = [ nushell bash dash shellcheck ];
  src = toSource {
    root = ../.;
    fileset = unions [
      ../nix/launch.sh
      ../nix/portable.sh
      ../nix/compile.sh
      ../tools/play.sh
      ../tests/launchers.nu
    ];
  };
} /* bash */ ''
  cp -r "$src" source
  chmod -R u+w source
  cd source
  cat nix/portable.sh nix/launch.sh > portable.sh
  shellcheck --shell sh portable.sh tools/play.sh
  shellcheck --shell bash nix/compile.sh
  nu --no-config-file tests/launchers.nu
  touch "$out"
''
