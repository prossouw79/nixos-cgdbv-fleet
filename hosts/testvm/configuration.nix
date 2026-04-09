{ config, pkgs, lib, ... }:

{
  networking.hostName = "testvm";
  imports = lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;
  
  # Hardware-specific overrides go here, e.g.:
  # boot.initrd.kernelModules = [ "i915" ];
}
