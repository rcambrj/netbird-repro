{ flake, pkgs, ... }:

pkgs.callPackage ./netbird-repro {
  netbirdPackage = pkgs:
    pkgs.callPackage ./netbird {
      inherit flake;
    };

  netbirdManagementPackage = pkgs:
    pkgs.callPackage ./netbird-management {
      inherit flake;
    };
}
