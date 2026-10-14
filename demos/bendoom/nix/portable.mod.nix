{
  perSystem = { config, pkgs, ... }: {
    packages.portable = pkgs.callPackage ./portable.nix {
      bendoom = config.packages.bendoom;
      variant = "shareware";
    };

    packages.portable-freedoom = pkgs.callPackage ./portable.nix {
      bendoom = config.packages.bendoom-freedoom;
      variant = "freedoom";
    };
  };
}
