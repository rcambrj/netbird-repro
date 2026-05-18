{ ... }:

rec {
  netbirdVersion = "0.71.1";
  netbirdHash = "sha256-xU2P4COLufGdFrit8+IRn96FT1IJKGQ97R9eGv5cjqU=";
  netbirdVendorHash = "sha256-NeZuj9o2yu5di+6jbNqCnAw0fI55GA5Otmr77c08QFc=";

  netbirdPackage = pkgs: args:
    pkgs.callPackage ./netbird-package.nix ({
      version = netbirdVersion;
      hash = netbirdHash;
      vendorHash = netbirdVendorHash;
    } // args);
}
