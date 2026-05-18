{ flake, pkgs, ... }:

let
  netbirdClientPatches = [
    ../patches/netbird-client-01-firewall-interface.patch
    ../patches/netbird-client-02-nftables-acl.patch
    ../patches/netbird-client-03-nftables-manager.patch
    ../patches/netbird-client-04-iptables-manager.patch
    ../patches/netbird-client-05-uspfilter-manager.patch
    ../patches/netbird-client-06-acl-manager.patch
  ];
in
pkgs.callPackage ./netbird-repro {
  netbirdPackage = pkgs:
    pkgs.callPackage ./netbird {
      inherit flake;
      patches = netbirdClientPatches;
    };

  netbirdManagementPackage = pkgs:
    pkgs.callPackage ./netbird-management {
      inherit flake;
    };
}