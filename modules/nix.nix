{ ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.settings.trusted-users = [ "root" "admin" ];

  # Automatically remove old generations to prevent disk fill
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nixpkgs.config.allowUnfree = true;

  # Run unpatched binaries — VSCode extensions, pip native deps
  programs.nix-ld.enable = true;
}
