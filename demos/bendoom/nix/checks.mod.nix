{
  perSystem = { config, pkgs, ... }: {
    checks = {
      launchers = pkgs.callPackage ./launchers.nix { };
      proof = pkgs.callPackage ./proof.nix { inherit (config.packages) bend; };
      tests = pkgs.callPackage ./tests.nix {
        inherit (config.packages) bend;
        music = config.packages.music-freedoom;
        sounds = config.packages.sounds-freedoom;
      };
    };
  };
}
