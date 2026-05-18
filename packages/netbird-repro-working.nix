{ inputs, pkgs, ... }:

pkgs.callPackage ./netbird-repro {
  netbirdPackage = pkgs:
    inputs.nixpkgs-netbird-working.legacyPackages.${pkgs.system}.netbird;

  netbirdManagementPackage = pkgs:
    inputs.nixpkgs-netbird-working.legacyPackages.${pkgs.system}.netbird-management;
}
