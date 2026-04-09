{ pkgs, ... }:
{
  # ── Auto-login ────────────────────────────────────────────────
  services.displayManager.autoLogin = {
    enable = true;
    user   = "admin";
  };
  systemd.services."getty@tty1".enable  = false;
  systemd.services."autovt@tty1".enable = false;

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

  # ── Chrome kiosk browser ──────────────────────────────────────
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
}
