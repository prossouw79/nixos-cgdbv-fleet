{ config, pkgs, lib, ... }:

{
  networking.hostName = "optiplex1";

  # WiFi — configured via local.nix (see local.nix.template).
  # Once device host keys are in secrets/secrets.nix, switch to agenix:
  #
  # age.secrets.wifi-password.file = ../../secrets/wifi-password.age;
  # networking.wireless.networks."CGROUNDWIFI".psk =
  #   config.age.secrets.wifi-password.path;
  imports = lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;

  # Hardware-specific overrides go here, e.g.:
  # boot.initrd.kernelModules = [ "i915" ];
}
