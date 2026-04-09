{ config, pkgs, lib, ... }:

let
  hasWifiSecret      = builtins.pathExists ../secrets/wifi-credentials.age;
  hasTailscaleSecret = builtins.pathExists ../secrets/tailscale-authkey.age;
in
{
  warnings =
    lib.optional (!hasWifiSecret)
      "secrets/wifi-credentials.age not found — fleet WiFi profiles will not be configured"
    ++ lib.optional (!hasTailscaleSecret)
      "secrets/tailscale-authkey.age not found — Tailscale will not auto-authenticate";

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false; # prevent WiFi disconnects on idle
  networking.firewall.enable = true;

  # Fleet WiFi networks — all credentials (SSIDs and PSKs) injected at
  # activation from the agenix secret. Nothing identifying appears in the repo.
  # The wifi-credentials.age secret must export four variables:
  #   WIFI_PRIMARY_SSID=<ssid of primary network>
  #   WIFI_PRIMARY_PSK=<psk of primary network>
  #   WIFI_SECONDARY_SSID=<ssid of secondary network>
  #   WIFI_SECONDARY_PSK=<psk of secondary network>
  age.secrets.wifi-credentials = lib.mkIf hasWifiSecret {
    file = ../secrets/wifi-credentials.age;
  };

  networking.networkmanager.ensureProfiles = lib.mkIf hasWifiSecret {
    environmentFiles = [ config.age.secrets.wifi-credentials.path ];
    profiles = {
      # Profile keys are internal NM connection file names — generic is fine.
      # The actual SSID NetworkManager scans for is the wifi.ssid value below.
      "fleet-wifi-primary" = {
        connection = { id = "$WIFI_PRIMARY_SSID"; type = "wifi"; };
        wifi       = { mode = "infrastructure"; ssid = "$WIFI_PRIMARY_SSID"; };
        "wifi-security" = { key-mgmt = "wpa-psk"; psk = "$WIFI_PRIMARY_PSK"; };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
      "fleet-wifi-secondary" = {
        connection = { id = "$WIFI_SECONDARY_SSID"; type = "wifi"; };
        wifi       = { mode = "infrastructure"; ssid = "$WIFI_SECONDARY_SSID"; };
        "wifi-security" = { key-mgmt = "wpa-psk"; psk = "$WIFI_SECONDARY_PSK"; };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };

  # Wake-on-LAN for all ethernet interfaces (also requires BIOS setting)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*|en*", \
      RUN+="${pkgs.ethtool}/sbin/ethtool -s $name wol g"
  '';

  networking.firewall.allowedTCPPorts = [
    22     # SSH
    61208  # Glances
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin        = "no";
  };

  # ── Tailscale ─────────────────────────────────────────────────
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts  = [ config.services.tailscale.port ];
  services.tailscale.extraUpFlags = [
    "--ssh"            # enable Tailscale SSH over the tailnet (coexists with sshd)
    "--accept-routes"  # honour subnet routes advertised by other tailnet nodes
    "--accept-dns"     # use Tailscale MagicDNS / custom nameservers
  ];

  age.secrets.tailscale-authkey = lib.mkIf hasTailscaleSecret {
    file = ../secrets/tailscale-authkey.age;
  };

  # Automatically authenticates on first boot (or after reinstall).
  # authKeyFile is only consumed when the node is not already enrolled —
  # it is safe to leave this set permanently.
  # Use a *reusable* key from the Tailscale admin console so all devices
  # can enrol without rotating the secret.
  services.tailscale.authKeyFile = lib.mkIf hasTailscaleSecret
    config.age.secrets.tailscale-authkey.path;
}
