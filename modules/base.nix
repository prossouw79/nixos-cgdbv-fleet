{ config, pkgs, lib, inputs, ... }:

let
  transcribeComposeFile = ../opt/docker-compose/live-transcribe/docker-compose.yml;
  transcribeConfigFile = ../opt/docker-compose/live-transcribe/config.yaml;
in
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

  # Reboot automatically after a kernel panic instead of hanging
  boot.kernel.sysctl = {
    "kernel.panic"        = 10; # reboot 10 s after panic
    "kernel.panic_on_oops" = 1;
  };

  # ── Filesystems (btrfs subvolumes) ───────────────────────────
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@persist" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  # Roll back @ to the blank snapshot on every boot
  boot.initrd.supportedFilesystems = [ "btrfs" ];
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    echo "[rollback] Starting btrfs root rollback" > /dev/kmsg
    mkdir -p /btrfs_tmp
    if mount -o subvolid=5 /dev/disk/by-label/nixos /btrfs_tmp; then
      echo "[rollback] Mounted btrfs top-level" > /dev/kmsg

      # systemd creates btrfs subvolumes inside @ on every boot (srv, tmp,
      # var/tmp, var/lib/machines, var/lib/portables). They must be deleted
      # before @ itself can be deleted. Sort -r so deeper paths go first.
      for sv in $(btrfs subvolume list -o /btrfs_tmp/@ | awk '{print $NF}' | sort -r); do
        echo "[rollback] Deleting nested subvolume: $sv" > /dev/kmsg
        btrfs subvolume delete "/btrfs_tmp/$sv" 2>&1 | tee /dev/kmsg || true
      done

      if btrfs subvolume delete /btrfs_tmp/@ 2>&1 | tee /dev/kmsg; then
        echo "[rollback] Deleted @, syncing..." > /dev/kmsg
        sync
        if btrfs subvolume snapshot /btrfs_tmp/@blank /btrfs_tmp/@ 2>&1 | tee /dev/kmsg; then
          echo "[rollback] Snapshot created successfully" > /dev/kmsg
        else
          echo "[rollback] ERROR: snapshot failed" > /dev/kmsg
        fi
      else
        echo "[rollback] ERROR: delete @ failed" > /dev/kmsg
      fi
      umount /btrfs_tmp
    else
      echo "[rollback] ERROR: mount failed" > /dev/kmsg
    fi
  '';

  # ── Persistence ───────────────────────────────────────────────
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/tailscale"
      "/var/lib/docker"
      "/var/log"
      "/opt/live-transcribe"
      { directory = "/home/admin/.local/share/keyrings"; user = "admin"; group = "admin"; mode = "0700"; }
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/nixos/local.nix"
    ];
  };

  # ── Hardware firmware ─────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # VirtIO drivers for Proxmox/QEMU VMs — harmless on physical hardware
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

  # ── Networking ────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false; # prevent WiFi disconnects on idle
  networking.firewall.enable = true;

  # Wake-on-LAN for all ethernet interfaces (also requires BIOS setting)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*|en*", \
      RUN+="${pkgs.ethtool}/sbin/ethtool -s $name wol g"
  '';

  # ── Desktop (GNOME) ───────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.autoSuspend = false;
  services.xserver.desktopManager.gnome.enable = true;

  # Trim GNOME to a minimal footprint (packages moved to top-level in 24.11)
  environment.gnome.excludePackages = with pkgs; [
    gnome-maps gnome-music gnome-weather gnome-contacts
    gnome-calendar totem cheese epiphany
  ];

  # Disable screen blanking, screensaver lock, and idle power actions.
  # Locked so users cannot override them via GNOME Settings.
  # Also suppress the Activities Overview that GNOME 40+ shows on startup
  # when no windows are open (before Chrome launches).
  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/desktop/session".idle-delay             = lib.gvariant.mkUint32 0;
      "org/gnome/desktop/screensaver".lock-enabled       = false;
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type      = "nothing";
        sleep-inactive-battery-type = "nothing";
        power-button-action         = "nothing";
      };
      "org/gnome/shell".enabled-extensions = [ "no-overview@fthx" ];
      "org/gnome/shell".welcome-dialog-last-shown-version = "9999";
    };
    locks = [
      "/org/gnome/desktop/session/idle-delay"
      "/org/gnome/desktop/screensaver/lock-enabled"
      "/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type"
      "/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type"
      "/org/gnome/settings-daemon/plugins/power/power-button-action"
    ];
  }];

  # ── GNOME Keyring ─────────────────────────────────────────────
  # Auto-unlock the keyring on login. gdm-autologin is the PAM service used
  # when auto-login is enabled — hooking it here means gnome-keyring-daemon
  # receives the (empty) credentials at login and unlocks without prompting.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm-autologin.enableGnomeKeyring = true;

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
    # ── Desktop / user apps ───────────────────────────────────────
    google-chrome
    #vlc
    #vscode
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
    #rsync
    #file
    #tree
    #unzip
    #zip
    #jq
    #tmux
    #vim
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
    #nethogs
    dig

    # ── Hardware inspection ───────────────────────────────────────
    pciutils      # lspci
    usbutils      # lsusb
    smartmontools # smartctl

    # ── Secrets management ────────────────────────────────────────
    inputs.agenix.packages.${pkgs.system}.default
  ];

  # ── nix-ld (run unpatched binaries — VSCode extensions, pip native deps)
  programs.nix-ld.enable = true;

  # ── Docker ────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Place the transcribe compose file at /opt/docker-compose/transcribe/docker-compose.yml
  systemd.tmpfiles.rules = [
    "d /opt/docker-compose/transcribe 0755 root root -"
    "L+ /opt/docker-compose/transcribe/docker-compose.yml - - - - ${transcribeComposeFile}"
    "L+ /opt/docker-compose/transcribe/config.yaml - - - - ${transcribeConfigFile}"
  ];

  # Start transcribe via docker-compose on boot (after Docker is ready)
  systemd.services.transcribe-docker = {
    description = "Nginx Docker Compose (port 8885)";
    after    = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/opt/docker-compose/transcribe";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --pull always";
      ExecStop  = "${pkgs.docker-compose}/bin/docker-compose down";
    };
  };

  # ── Power management ──────────────────────────────────────────
  # Kiosk devices must never sleep, suspend, or hibernate
  systemd.targets.sleep.enable        = false;
  systemd.targets.suspend.enable      = false;
  systemd.targets.hibernate.enable    = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Systemd hardware watchdog — reboots the machine if the kernel hangs
  systemd.watchdog.runtimeTime = "30s";

  # Ignore lid close and define power button behaviour
  services.logind.extraConfig = ''
    HandlePowerKey=poweroff
    HandleLidSwitch=ignore
    HandleLidSwitchExternalPower=ignore
    HandleLidSwitchDocked=ignore
  '';

  # ── Kiosk browser ─────────────────────────────────────────────
  # Chrome runs as a systemd user service so it restarts automatically on crash.
  # After 3 failures within 60 s the system reboots.
  # Override the URL per-device in hosts/<name>/configuration.nix.
  systemd.user.services.chrome-kiosk = {
    description = "Chrome Kiosk Browser";
    wantedBy = [ "graphical-session.target" ];
    after    = [ "graphical-session.target" ];
    unitConfig = {
      StartLimitBurst       = 5;
      StartLimitIntervalSec = 120;
    };
    serviceConfig = {
      # --no-sandbox: required when running under a systemd user service where
      # Chrome's namespace sandbox cannot initialise (causes SIGTRAP otherwise).
      # --disable-dev-shm-usage: avoids /dev/shm exhaustion on low-memory machines.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5"; # let GNOME settle first
      ExecStart = ''
        ${pkgs.google-chrome}/bin/google-chrome-stable \
          --no-sandbox \
          --test-type \
          --disable-dev-shm-usage \
          --hide-crash-restore-bubble \
          --noerrdialogs \
          --start-fullscreen \
          --password-store=basic \
          --no-first-run \
          --disable-default-browser-check \
          --no-default-browser-check \
          --metrics-recording-only \
          http://localhost:8885
      '';
      Restart    = "on-failure";
      RestartSec = "5s";
    };
  };

  # Reboot the system if Chrome exhausts its restart attempts
  systemd.user.services.chrome-kiosk-reboot = {
    description = "Reboot after Chrome kiosk failure";
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl reboot";
    };
  };

  # Wire OnFailure on the system slice (user services can't reboot directly)
  systemd.services.chrome-kiosk-reboot = {
    description = "Reboot triggered by Chrome kiosk failure";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl reboot";
    };
  };

  # ── Auto-update service ───────────────────────────────────────
  systemd.services.nixos-auto-update = {
    description = "Pull and apply NixOS configuration from GitHub";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail

      # Skip if a nixos-rebuild is already running (e.g. a manual update via SSH)
      if systemctl is-active --quiet nixos-rebuild-switch-to-configuration.service 2>/dev/null; then
        echo "[auto-update] nixos-rebuild already running — skipping"
        exit 0
      fi

      REPO="github:prossouw79/nixos-cgdbv-fleet"
      HOSTNAME=$(${pkgs.inetutils}/bin/hostname)

      echo "[auto-update] Applying config for host: $HOSTNAME"
      /run/current-system/sw/bin/nixos-rebuild switch \
        --flake "$REPO#$HOSTNAME" \
        2>&1

      echo "[auto-update] Switch succeeded"

      # Record the applied commit to /persist so it survives reboots.
      # Non-fatal — a metadata fetch failure must not abort the update.
      COMMIT=$(${pkgs.nix}/bin/nix flake metadata "$REPO" --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.locked.rev // "unknown"' 2>/dev/null \
        || echo "unknown")
      ENTRY="$(date -u +"%Y-%m-%dT%H:%M:%SZ")  $HOSTNAME  $COMMIT"
      echo "$ENTRY" >> /persist/manifest.txt \
        && echo "[auto-update] Manifest updated: $ENTRY" \
        || echo "[auto-update] Warning: could not write /persist/manifest.txt"

      # Reboot if the running system differs from the newly built one
      # (e.g. a new kernel was installed)
      booted=$(readlink /run/booted-system)
      current=$(readlink /run/current-system)
      if [ "$booted" != "$current" ]; then
        echo "[auto-update] New generation requires reboot — rebooting now"
        /run/current-system/sw/bin/systemctl reboot
      fi
    '';
  };

  # Run the update every 5 minutes (increase OnUnitActiveSec to "30min" once stable)
  systemd.timers.nixos-auto-update = {
    description = "Periodic NixOS auto-update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec          = "1min";
      OnUnitActiveSec    = "5min";
      RandomizedDelaySec = "10sec";
    };
  };

  # Trigger an update whenever a network interface comes online
  networking.networkmanager.dispatcherScripts = [{
    source = pkgs.writeShellScript "nixos-auto-update-on-connect" ''
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
    user   = "admin";
  };
  systemd.services."getty@tty1".enable  = false;
  systemd.services."autovt@tty1".enable = false;

  # ── Locale / time ─────────────────────────────────────────────
  time.timeZone      = "Africa/Johannesburg";
  i18n.defaultLocale = "en_ZA.UTF-8";

  # ── Sudo ──────────────────────────────────────────────────────
  security.sudo.wheelNeedsPassword = false;

  # ── SSH ───────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin        = "no";
  };
  networking.firewall.allowedTCPPorts = [
    22     # SSH
    61208  # Glances
  ];

  # ── Monitoring ────────────────────────────────────────────────
  services.glances.enable = true;

  # ── Tailscale ─────────────────────────────────────────────────
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces  = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts    = [ config.services.tailscale.port ];
  # After first boot: sudo tailscale up --authkey=<your-key>

  # ── Users ─────────────────────────────────────────────────────
  users.groups.admin.gid = 1000;

  users.users.admin = {
    isNormalUser  = true;
    uid           = 1000;
    group         = "admin";
    extraGroups   = [ "wheel" "docker" "networkmanager" "video" "audio" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKBMYHX4vj6LafDI0GkMMhs+lzLEWI+wF56gVXBd0tOw cgdbv-fleet-admin"
    ];
    initialHashedPassword = "$6$2AhsfG2/VfnkE2uo$aoaXVpfCaOsI2tQU9aZJUHr.XvzEYOdS4SgVOjbkNgMVUH3L5GYHwqRU1DCyUvdKJ6OR0I.PStamNPc0UMse8.";
  };

  system.stateVersion = "24.11";
}
