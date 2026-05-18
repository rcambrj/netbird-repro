{ flake, patches ? [], pkgs, ... }:

flake.lib.netbirdPackage pkgs {
  componentName = "management";
  inherit patches;
}
