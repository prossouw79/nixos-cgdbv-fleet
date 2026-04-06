{ config, pkgs, lib, ... }:

{
  networking.hostName = "optiplex2";

  # WiFi password lives in /etc/nixos/local.nix on the device (never committed).
  # Copy local.nix.template from the repo to /etc/nixos/local.nix and fill in the PSK.
  imports = lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;

  # Hardware-specific overrides go here, e.g.:
  # boot.initrd.kernelModules = [ "i915" ];
}
