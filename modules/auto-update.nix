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

      REV_STATE=/persist/current-rev
      GEN_BEFORE=$(readlink /run/current-system)
      REV_BEFORE=$(cat "$REV_STATE" 2>/dev/null || echo "unknown")

      # Fetch the latest remote rev to check if there's anything new
      REV_REMOTE=$(${pkgs.nix}/bin/nix flake metadata "$REPO" --json --refresh 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.locked.rev // "unknown"' 2>/dev/null || echo "unknown")

      if [ "$REV_BEFORE" = "$REV_REMOTE" ] && [ "$REV_REMOTE" != "unknown" ]; then
        echo "[auto-update] Already on latest commit ($REV_REMOTE) — skipping"
        exit 0
      fi

      echo "[auto-update] New commit detected ($REV_BEFORE -> $REV_REMOTE), applying..."

      LOG=/persist/nixos-update-''${REV_REMOTE}.log
      echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") host=$HOSTNAME rev=$REV_REMOTE" > "$LOG"

      # Capture exit code without triggering set -e.
      # Code 0: success. Code 4: activation warnings (partial success, generation
      # may still have been built). Anything else is a real failure.
      /run/current-system/sw/bin/nixos-rebuild switch \
        --flake "$REPO#$HOSTNAME" \
        2>&1 | tee -a "$LOG" || REBUILD_EXIT=$?
      REBUILD_EXIT=''${REBUILD_EXIT:-0}

      GEN_AFTER=$(readlink /run/current-system)

      if [ "$REBUILD_EXIT" -ne 0 ] && [ "$GEN_BEFORE" = "$GEN_AFTER" ]; then
        echo "RESULT=failed exit=$REBUILD_EXIT" >> "$LOG"
        ${errorDialog} "Update failed on $HOSTNAME (exit $REBUILD_EXIT).\n\nSee /persist/nixos-update-''${REV_REMOTE}.log" || true
        echo "[auto-update] Switch failed (exit $REBUILD_EXIT, generation unchanged)"
        exit 1
      fi

      echo "RESULT=success exit=$REBUILD_EXIT" >> "$LOG"
      echo "[auto-update] Switch succeeded (exit $REBUILD_EXIT)"

      # Persist the applied rev and record in manifest
      echo "$REV_REMOTE" > "$REV_STATE"
      MANIFEST=/persist/manifest.txt
      ENTRY="$(date -u +"%Y-%m-%dT%H:%M:%SZ")  $HOSTNAME  $REV_REMOTE"
      echo "$ENTRY" >> "$MANIFEST" \
        && echo "[auto-update] Manifest updated: $ENTRY" \
        || echo "[auto-update] Warning: could not write $MANIFEST"

      echo "[auto-update] Change applied (gen: $GEN_BEFORE -> $GEN_AFTER, rev: $REV_BEFORE -> $REV_REMOTE) — rebooting"
      /run/current-system/sw/bin/systemctl reboot
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
