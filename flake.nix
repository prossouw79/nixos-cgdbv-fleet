{
  description = "NixOS fleet configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # Pin to a stable channel. Update with: nix flake update && git add flake.lock && git commit -m "bump nixpkgs"

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs"; # reuse our nixpkgs, avoids a second download
    };
  };

  outputs = { self, nixpkgs, agenix } @ inputs: {
    nixosConfigurations = {

      # Add one entry per device. The name must match the device's hostname.
      optiplex1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          ./modules/base.nix
          ./hosts/optiplex1/configuration.nix
        ];
      };

      optiplex2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          ./modules/base.nix
          ./hosts/optiplex2/configuration.nix
        ];
      };

    };
  };
}
