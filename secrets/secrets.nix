let
  # ── Admin workstation key (can encrypt secrets from your machine) ──
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKBMYHX4vj6LafDI0GkMMhs+lzLEWI+wF56gVXBd0tOw cgdbv-fleet-admin";

  # ── Device SSH host keys ───────────────────────────────────────────
  # Populate these after first boot on each device:
  #   ssh-keyscan -t ed25519 <device-ip>
  # or on the device:
  #   cat /etc/ssh/ssh_host_ed25519_key.pub
  optiplex1 = "ssh-ed25519 AAAA__REPLACE_WITH_OPTIPLEX1_HOST_KEY__ root@optiplex1";
  optiplex2 = "ssh-ed25519 AAAA__REPLACE_WITH_OPTIPLEX2_HOST_KEY__ root@optiplex2";
  intelnuc  = "ssh-ed25519 AAAA__REPLACE_WITH_INTELNUC_HOST_KEY__  root@intelnuc";

  # ── Shorthand groups ──────────────────────────────────────────────
  allDevices = [ admin optiplex1 optiplex2 intelnuc ];
in
{
  # Each .age file lists the public keys that are allowed to decrypt it.
  # The device decrypts its own secrets at boot using its SSH host key.
  # You encrypt secrets from your workstation using your admin key.
  #
  # Workflow:
  #   1. Replace AAAA__REPLACE_WITH_*__ placeholders with real host keys
  #   2. agenix -e secrets/<name>.age   # create / edit a secret
  #   3. agenix -r                      # re-encrypt after adding a new device
  #
  # Secret file formats:
  #   tailscale-authkey.age        plain text  — tskey-auth-xxxxxxxxxxxx
  #   dockerhub-credentials.age    JSON        — {"username":"...","password":"..."}
  #   wifi-credentials.age         env vars    — WIFI_PRIMARY_PSK=...\nWIFI_SECONDARY_PSK=...

  # Tailscale auth key — used by services.tailscale.authKeyFile on each node.
  # Use a *reusable*, non-ephemeral key from the Tailscale admin console so
  # all devices can enrol and re-enrol after reinstalls without rotating it.
  "tailscale-authkey.age".publicKeys = allDevices;

  # DockerHub credentials — used by the docker-login systemd service so the
  # Docker daemon can pull private images (e.g. prossouw79/grtspwhspr).
  "dockerhub-credentials.age".publicKeys = allDevices;

  # WiFi PSKs for both fleet networks — consumed by NetworkManager ensureProfiles.
  # File must export two variables (see format above).
  "wifi-credentials.age".publicKeys = allDevices;
}
