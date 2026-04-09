{ config, pkgs, lib, ... }:

{
  networking.hostName = "optiplex1";
  imports = lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;

  # Hardware-specific overrides go here, e.g.:
  # boot.initrd.kernelModules = [ "i915" ];
}
