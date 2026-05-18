{ flake, pkgs, ... }:

flake.lib.netbirdPackage pkgs {
  componentName = "client";
}
