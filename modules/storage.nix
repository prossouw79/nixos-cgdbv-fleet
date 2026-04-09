{ ... }:
{
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

  # ── Persistence (impermanence) ────────────────────────────────
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
      { file = "/home/admin/.bash_history"; parentDirectory = { user = "admin"; group = "admin"; mode = "0700"; }; }
    ];
  };
}
