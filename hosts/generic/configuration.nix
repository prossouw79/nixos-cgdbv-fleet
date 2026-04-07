{ ... }:

{
  # Placeholder hostname — override at install time with:
  #   nixos-install --flake .#generic
  # then set the real hostname in /etc/nixos/local.nix after first boot.
  networking.hostName = "optiplex";
}
