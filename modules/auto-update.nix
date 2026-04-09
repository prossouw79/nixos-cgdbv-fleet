{ pkgs, ... }:
let
  # Send a desktop notification to the kiosk user's GNOME session from a root service.
  # urgency: low | normal | critical
  notifyUser = pkgs.writeShellScript "notify-kiosk-user" ''
    URGENCY="''${1:-normal}"
    TITLE="$2"
    BODY="$3"
    USER="admin"
    USER_UID=$(id -u "$USER")
    DBUS="unix:path=/run/user/$USER_UID/bus"
    DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS" \
      ${pkgs.libnotify}/bin/notify-send \
        --urgency="$URGENCY" \
        --expire-time=0 \
        --app-name="System Update" \
        "$TITLE" "$BODY"
  '';

  # Show a blocking error dialog in the kiosk user's session.
  errorDialog = pkgs.writeShellScript "error-dialog-kiosk-user" ''
    USER="admin"
    USER_UID=$(id -u "$USER")
    DBUS="unix:path=/run/user/$USER_UID/bus"
    DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS" \
      ${pkgs.zenity}/bin/zenity \
        --error \
        --title="System Update Failed" \
        --text="$1" \
        --width=400 &
  '';
in
{
  # Pull and apply the fleet configuration from GitHub every 5 minutes,
  # and immediately whenever a network interface comes online.
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
      ${notifyUser} low "System Update" "Applying configuration update..." || true

      GEN_BEFORE=$(readlink /run/current-system)

      if ! /run/current-system/sw/bin/nixos-rebuild switch \
          --flake "$REPO#$HOSTNAME" \
          2>&1; then
        ${errorDialog} "Update failed on $HOSTNAME.\n\nCheck logs with:\njournalctl -u nixos-auto-update" || true
        echo "[auto-update] Switch failed"
        exit 1
      fi

      GEN_AFTER=$(readlink /run/current-system)
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

      if [ "$GEN_BEFORE" != "$GEN_AFTER" ]; then
        echo "[auto-update] New generation applied — rebooting"
        /run/current-system/sw/bin/systemctl reboot
      else
        echo "[auto-update] Already on latest generation — no reboot needed"
      fi
    '';
  };

  # TODO: increase OnUnitActiveSec to "5min" or "30min" once stable
  systemd.timers.nixos-auto-update = {
    description = "Periodic NixOS auto-update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec          = "1min";
      OnUnitActiveSec    = "1min";
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
}
