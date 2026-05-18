{ inputs, pkgs, ... }:

pkgs.callPackage ./netbird-repro {
  netbirdPackage = pkgs:
    inputs.nixpkgs-netbird-broken.legacyPackages.${pkgs.system}.netbird;

  netbirdManagementPackage = pkgs:
    inputs.nixpkgs-netbird-broken.legacyPackages.${pkgs.system}.netbird-management;
}
