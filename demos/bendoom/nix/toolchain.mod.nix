{ inputs, ... }:
{
  perSystem = { lib, pkgs, system, ... }:
    let
      inherit (lib.strings) getName;
    in {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: getName pkg == "doom1-wad";
      };

      packages.bend = pkgs.callPackage ./bend.nix { src = inputs.bend-src; };
    };
}
