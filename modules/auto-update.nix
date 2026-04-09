{ pkgs, ... }:
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
}
