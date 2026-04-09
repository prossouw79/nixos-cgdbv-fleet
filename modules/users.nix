{ ... }:
{
  security.sudo.wheelNeedsPassword = false;

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

  # Ensure home directory structure exists (survives btrfs rollback via tmpfiles)
  systemd.tmpfiles.rules = [
    "d /home/admin                             0755 admin admin -"
    "d /home/admin/.local                      0755 admin admin -"
    "d /home/admin/.local/share                0755 admin admin -"
    "d /home/admin/.local/share/applications   0755 admin admin -"
    "d /home/admin/.config                     0755 admin admin -"
    "d /home/admin/Downloads                   0755 admin admin -"
  ];
}
