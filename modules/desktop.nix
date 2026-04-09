{ pkgs, lib, ... }:
let
  trayscaleAutostart = pkgs.makeDesktopItem {
    name        = "trayscale-autostart";
    desktopName = "Trayscale";
    exec        = "${pkgs.trayscale}/bin/trayscale --hide-window";
  };
in
{
  # ── GNOME ─────────────────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.autoSuspend = false;
  services.xserver.desktopManager.gnome.enable = true;

  # Trim GNOME to a minimal footprint (packages moved to top-level in 24.11)
  environment.gnome.excludePackages = with pkgs; [
    baobab          # disk usage analyser
    cheese
    eog             # image viewer
    epiphany
    evince          # document viewer
    file-roller     # file roller / archive manager
    gnome-calculator
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-contacts
    #gnome-extensions-app
    gnome-font-viewer
    gnome-logs
    gnome-maps
    gnome-music
    gnome-text-editor
    gnome-weather
    seahorse        # passwords and keys
    simple-scan
    totem
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
      "org/gnome/shell".enabled-extensions = [ "no-overview@fthx" "appindicatorsupport@rgcjonas.gmail.com" ];
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

  # ── Trayscale (Tailscale tray applet) ────────────────────────
  environment.systemPackages = [ pkgs.trayscale pkgs.gnomeExtensions.appindicator ];
  xdg.autostart.entries = [ trayscaleAutostart ];

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
}
