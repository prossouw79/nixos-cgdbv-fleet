{ pkgs, inputs, ... }:
{
  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    # ── Desktop / user apps ───────────────────────────────────────
    google-chrome
    vlc
    vscode
    gnomeExtensions.no-overview

    # ── Dev tools ─────────────────────────────────────────────────
    git
    (python3.withPackages (ps: [ ps.pip ]))  # venv is included in stdlib

    # ── Container tools ───────────────────────────────────────────
    docker
    docker-compose

    # ── System utilities ──────────────────────────────────────────
    curl
    wget
    rsync
    file
    tree
    unzip
    zip
    jq
    tmux
    vim
    nano
    ethtool   # used by WoL udev rule

    # ── Process / resource monitoring ─────────────────────────────
    htop
    btop
    iotop
    lsof

    # ── Network tools ─────────────────────────────────────────────
    inetutils     # hostname, ping, ifconfig, traceroute
    nettools      # netstat, route, arp
    nmap
    bmon
    nethogs
    dig

    # ── Hardware inspection ───────────────────────────────────────
    pciutils      # lspci
    usbutils      # lsusb
    smartmontools # smartctl

    # ── Secrets management ────────────────────────────────────────
    inputs.agenix.packages.${pkgs.system}.default
  ];

  time.timeZone      = "Africa/Johannesburg";
  i18n.defaultLocale = "en_ZA.UTF-8";

  services.glances.enable = true;

  system.stateVersion = "24.11";
}
