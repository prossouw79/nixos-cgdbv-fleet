{
  description = "NixOS fleet configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # Pin to a stable channel. Update with: nix flake update && git add flake.lock && git commit -m "bump nixpkgs"

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs"; # reuse our nixpkgs, avoids a second download
    };

    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, agenix, impermanence } @ inputs: {
    nixosConfigurations = {

      # Add one entry per device. The name must match the device's hostname.
      optiplex1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          impermanence.nixosModules.impermanence
          ./modules/base.nix
          ./hosts/optiplex1/configuration.nix
        ];
      };

      optiplex2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          impermanence.nixosModules.impermanence
          ./modules/base.nix
          ./hosts/optiplex2/configuration.nix
        ];
      };

      testvm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          impermanence.nixosModules.impermanence
          ./modules/base.nix
          ./hosts/testvm/configuration.nix
        ];
      };

      intelnuc = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          impermanence.nixosModules.impermanence
          ./modules/base.nix
          ./hosts/intelnuc/configuration.nix
        ];
      };

      # Bootable installer ISO — flash to USB with:
      #   dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
      # Boots to a shell; run: nixos-install --flake /iso/flake#generic
      iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          {
            # Pre-load the fleet admin SSH key so you can log in remotely during install
            users.users.nixos.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKBMYHX4vj6LafDI0GkMMhs+lzLEWI+wF56gVXBd0tOw cgdbv-fleet-admin"
            ];
            services.openssh.enable = true;

            # Bake the generic host closure into the ISO's nix store for offline install
            isoImage.storeContents = [
              self.nixosConfigurations.generic.config.system.build.toplevel
            ];
          }
        ];
      };

    };
  };
}
