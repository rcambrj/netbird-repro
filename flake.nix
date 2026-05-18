{
  description = "Simple flake with a devshell";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-netbird-working.url = "github:NixOS/nixpkgs?ref=26afda1803886eab9161182bf169e6e43f3f6aed";
    nixpkgs-netbird-broken.url = "github:NixOS/nixpkgs?ref=8a1b0127302ea51e05bf4ea5a291743fac442406";
  };

  # Load the blueprint
  outputs = inputs: inputs.blueprint {
    inherit inputs;
    nixpkgs.overlays = [
      (final: prev: {
        netbird-working = inputs.nixpkgs-netbird-working.legacyPackages.${final.system}.netbird;
        netbird-broken = inputs.nixpkgs-netbird-broken.legacyPackages.${final.system}.netbird;

        netbird-management-working = inputs.nixpkgs-netbird-working.legacyPackages.${final.system}.netbird-management;
        netbird-management-broken = inputs.nixpkgs-netbird-broken.legacyPackages.${final.system}.netbird-management;
      })
    ];
  };
}
