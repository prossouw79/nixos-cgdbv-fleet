{ config, pkgs, lib, inputs, ... }:

{
  # ── Nix settings ──────────────────────────────────────────────
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

  # ── Boot ──────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Placeholder root filesystem — overridden by hardware-configuration.nix
  # generated during nixos-install on each device.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # ── Hardware firmware ─────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # ── Networking ────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # ── Desktop (GNOME) ───────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Trim GNOME to a minimal footprint (packages moved to top-level in 24.11)
  environment.gnome.excludePackages = with pkgs; [
    gnome-maps gnome-music gnome-weather gnome-contacts
    gnome-calendar totem cheese epiphany
  ];

  # ── Audio ─────────────────────────────────────────────────────
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # ── System packages ───────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    google-chrome
    vlc
    git
    curl
    htop
    docker
    docker-compose
    (python3.withPackages (ps: [ ps.pip ]))  # venv is included in stdlib
    vscode
    inputs.agenix.packages.${pkgs.system}.default  # agenix CLI for encrypting secrets
  ];

  # ── nix-ld (run unpatched binaries — needed for VSCode extensions and pip native deps)
  programs.nix-ld.enable = true;

  # ── Docker + Compose ──────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # ── Auto-update service ───────────────────────────────────────
  # Every device polls GitHub and applies the matching config automatically.
  systemd.services.nixos-auto-update = {
    description = "Pull and apply NixOS configuration from GitHub";
    wants = [ "network-online.target" ];
    after  = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # View logs with: journalctl -u nixos-auto-update
    };

    script = ''
      set -euo pipefail

      # TODO: replace with your actual GitHub org/username and repo name
      REPO="github:prossouw79/nixos-cgdbv-fleet"
      HOSTNAME=$(hostname)

      echo "[auto-update] Applying config for host: $HOSTNAME"
      /run/current-system/sw/bin/nixos-rebuild switch \
        --flake "$REPO#$HOSTNAME" \
        2>&1
    '';
  };

  # Run the update every 5 minutes (increase OnUnitActiveSec to "30min" once stable)
  systemd.timers.nixos-auto-update = {
    description = "Periodic NixOS auto-update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "1min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "30sec";
    };
  };

  # Also trigger an update whenever a network interface comes online
  networking.networkmanager.dispatcherScripts = [{
    source = pkgs.writeShellScript "nixos-auto-update-on-connect" ''
      INTERFACE="$1"
      EVENT="$2"
      if [ "$EVENT" = "up" ] || [ "$EVENT" = "connectivity-change" ]; then
        systemctl start nixos-auto-update.service
      fi
    '';
    type = "basic";
  }];

  # ── Auto-login ────────────────────────────────────────────────
  services.displayManager.autoLogin = {
    enable = true;
    user = "admin";
  };
  # Required to avoid a GNOME autologin race condition
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # ── Kiosk startup ─────────────────────────────────────────────
  # Opens Chrome in fullscreen on login. Change the URL per-device by
  # overriding this entry in the host's configuration.nix.
  environment.etc."xdg/autostart/chrome-kiosk.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Chrome Kiosk
      Exec=${pkgs.google-chrome}/bin/google-chrome-stable --start-fullscreen https://www.google.com
      X-GNOME-Autostart-enabled=true
    '';
  };

  # ── Locale / time ─────────────────────────────────────────────
  time.timeZone = "Africa/Johannesburg";
  i18n.defaultLocale = "en_ZA.UTF-8";

  # ── SSH ───────────────────────────────────────────────────────
  # Open on LAN and Tailscale. Key-only — safe to leave open for remote management.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Tailscale ─────────────────────────────────────────────────
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
  # After first boot, run: sudo tailscale up --authkey=<your-key>
  # Generate a reusable auth key at https://login.tailscale.com/admin/settings/keys

  # ── Users ─────────────────────────────────────────────────────
  users.groups.admin = {
    gid = 1000;
  };

  users.users.admin = {
    isNormalUser = true;
    uid = 1000;
    group = "admin";
    extraGroups = [ "wheel" "docker" "networkmanager" "video" "audio" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKBMYHX4vj6LafDI0GkMMhs+lzLEWI+wF56gVXBd0tOw cgdbv-fleet-admin"
    ];
    initialHashedPassword = "$6$2AhsfG2/VfnkE2uo$aoaXVpfCaOsI2tQU9aZJUHr.XvzEYOdS4SgVOjbkNgMVUH3L5GYHwqRU1DCyUvdKJ6OR0I.PStamNPc0UMse8.";
  };

  system.stateVersion = "24.11";
}
