{
  description = "Simple flake with a devshell";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    # netbird is broken as of https://github.com/NixOS/nixpkgs/pull/453040
    # breaking commit
    nixpkgs-netbird-0-59-7.url = "github:NixOS/nixpkgs?ref=0cbfca7acd0bac87c34bb184130e4542c27da52c";
    # parent (working)
    nixpkgs-netbird-0-59-5.url = "github:NixOS/nixpkgs?ref=26afda1803886eab9161182bf169e6e43f3f6aed";
  };

  # Load the blueprint
  outputs = inputs: inputs.blueprint {
    inherit inputs;
    nixpkgs.overlays = [
      (final: prev: {
        netbird-0-59-5 = inputs.nixpkgs-netbird-0-59-5.legacyPackages.${final.system}.netbird;
        netbird-0-59-7 = inputs.nixpkgs-netbird-0-59-7.legacyPackages.${final.system}.netbird;
      })
    ];
  };
}
