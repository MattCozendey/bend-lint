# Freedoom is BSD and in nixpkgs. The shareware DOOM1.WAD is free to pass
# on unmodified, not to sell (Carmack, 1999), so unfree-redistributable;
# doom19s.zip holds it as a two-part self-extractor whose parts
# concatenate into a zip.
{ lib, stdenvNoCC, fetchurl, unzip, freedoom, runCommand }:

let
  inherit (lib.lists) singleton;
  inherit (lib.licenses) unfreeRedistributable;
  inherit (lib.platforms) all;
in
{
  freedoom = runCommand "freedoom1-${freedoom.version}" { inherit (freedoom) meta; } /* bash */ ''
    install -Dm644 ${freedoom}/share/games/doom/freedoom1.wad $out/share/games/doom/freedoom1.wad
    mkdir -p $out/share/doc
    cp -r ${freedoom}/share/doc/freedoom $out/share/doc/freedoom
  '';

  doom1 = stdenvNoCC.mkDerivation {
    pname = "doom1-wad";
    version = "1.9";

    src = fetchurl {
      urls = [
        "https://ftp.fu-berlin.de/pc/games/idgames/idstuff/doom/doom19s.zip"
        "https://www.gamers.org/pub/idgames/idstuff/doom/doom19s.zip"
        "https://youfailit.net/pub/idgames/idstuff/doom/doom19s.zip"
      ];
      hash = "sha256-ys8BQrMcoa8AeWtKAzngeZKsXyG8P4HnUy/hteG0huY=";
    };

    nativeBuildInputs = singleton unzip;

    unpackPhase = /* bash */ ''
      unzip -q $src
      cat DOOMS_19.1 DOOMS_19.2 > dooms.zip
      unzip -q dooms.zip DOOM1.WAD README.TXT
    '';

    installPhase = /* bash */ ''
      install -Dm644 DOOM1.WAD $out/share/games/doom/doom1.wad
      install -Dm644 README.TXT $out/share/doc/doom1-wad/README.TXT
    '';

    meta = {
      description = "The shareware DOOM IWAD (episode 1)";
      license = unfreeRedistributable;
      platforms = all;
    };
  };
}
