{ lib, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Reboot automatically after a kernel panic instead of hanging
  boot.kernel.sysctl = {
    "kernel.panic"        = 10; # reboot 10 s after panic
    "kernel.panic_on_oops" = 1;
  };

  # VirtIO drivers for Proxmox/QEMU VMs — harmless on physical hardware
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

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
}
