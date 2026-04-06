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

  # ── Shorthand groups ──────────────────────────────────────────────
  allDevices = [ admin optiplex1 optiplex2 ];
in
{
  # Each .age file lists the public keys that are allowed to decrypt it.
  # The device decrypts its own secrets at boot using its SSH host key.
  # You encrypt secrets from your workstation using your admin key.

  "wifi-password.age".publicKeys = allDevices;
}
