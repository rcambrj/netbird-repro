{ flake, patches ? [], pkgs, ... }:

flake.lib.netbirdPackage pkgs {
  componentName = "client";
  inherit patches;
}
