{ lib, runCommand, nodejs, playwright-driver, chromium, makeFontsConf, dejavu_fonts, game, iwad }:

let
  inherit (lib.meta) getExe;
in
runCommand "bendoom-web" {
  nativeBuildInputs = [ nodejs ];
  CHROMIUM = getExe chromium;
  PLAYWRIGHT_DRIVER = playwright-driver;
  FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ dejavu_fonts ]; };
} /* bash */ ''
  export XDG_CACHE_HOME=$TMPDIR/cache
  export XDG_CONFIG_HOME=$TMPDIR/config
  mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" $out
  cp ${game}/* ${../web}/* $out/
  node ${../tools/web-art.cjs} ${iwad} $out/art
  node ${../tools/web-card.cjs} $out
''
