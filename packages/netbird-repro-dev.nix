{ flake, pkgs, ... }:

let
  netbirdManagementPatches = [
    # Add local netbird-management patches here while iterating on netbird-repro-dev.
  ];
in
pkgs.callPackage ./netbird-repro {
  netbirdPackage = pkgs:
    pkgs.callPackage ./netbird {
      inherit flake;
    };

  netbirdManagementPackage = pkgs:
    pkgs.callPackage ./netbird-management {
      inherit flake;
      patches = netbirdManagementPatches;
    };
}
