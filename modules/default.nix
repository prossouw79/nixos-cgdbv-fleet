{ ... }:
{
  imports = [
    ./nix.nix        # Nix daemon, GC, nixpkgs, nix-ld
    ./boot.nix       # Bootloader, kernel, btrfs rollback
    ./storage.nix    # Filesystems and impermanence
    ./networking.nix # NetworkManager, WiFi, WoL, firewall, SSH, Tailscale
    ./desktop.nix    # GNOME, audio, keyring, dconf
    ./kiosk.nix      # Chrome kiosk, power management, auto-login
    ./docker.nix     # Docker, transcribe service
    ./auto-update.nix # Auto-update service and timer
    ./users.nix      # Users, groups, sudo
    ./system.nix     # Packages, locale, hardware, monitoring, stateVersion
  ];
}
