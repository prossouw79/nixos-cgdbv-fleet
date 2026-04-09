#!/usr/bin/env bash
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ── Flake source ──────────────────────────────────────────────────────────────
# Use the local repo if run from a clone so the pulled commit is what gets
# installed, rather than relying on nix's remote fetch cache.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-scripts/install.sh}")" 2>/dev/null && pwd || true)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
if [[ -f "$REPO_ROOT/flake.nix" ]]; then
  FLAKE_URL="$REPO_ROOT"
  info "Using local repo at $FLAKE_URL"
else
  FLAKE_URL="github:prossouw79/nixos-cgdbv-fleet"
  warn "Could not detect local repo — fetching from GitHub"
fi

# ── Must run as root ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Run as root (sudo bash install.sh)"

# ── Select target device ──────────────────────────────────────────────────────
echo ""
echo "Available block devices:"
echo ""
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -v "^loop" | grep -v "^sr"
echo ""

read -rp "Target device (e.g. sda): " DEV_NAME </dev/tty
DEVICE="/dev/${DEV_NAME}"

[[ -b "$DEVICE" ]] || error "Device $DEVICE not found"

echo ""
warn "This will ERASE all data on $DEVICE"
lsblk "$DEVICE"
echo ""
read -rp "Type YES to confirm: " CONFIRM </dev/tty
[[ "$CONFIRM" == "YES" ]] || error "Aborted"

# ── Select hostname ───────────────────────────────────────────────────────────
echo ""
echo "Available hosts:"
echo "  1) optiplex1"
echo "  2) optiplex2"
echo "  3) intelnuc"
echo ""
read -rp "Select host [1-3]: " HOST_NUM </dev/tty
case "$HOST_NUM" in
  1) HOSTNAME="optiplex1" ;;
  2) HOSTNAME="optiplex2" ;;
  3) HOSTNAME="intelnuc" ;;
  *) error "Invalid selection" ;;
esac

info "Installing $HOSTNAME onto $DEVICE"

# ── Wipe existing mounts and partitions ───────────────────────────────────────
info "Cleaning up any existing mounts on $DEVICE..."
# Unmount everything under /mnt (silently — may not be mounted)
umount -R /mnt 2>/dev/null || true
# Unmount any other mounts directly on the device's partitions
for part in "${DEVICE}"?*; do
  umount -R "$part" 2>/dev/null || true
done
# Wipe partition table and any filesystem signatures so parted starts clean
wipefs -a "$DEVICE"

# ── Partition ─────────────────────────────────────────────────────────────────
info "Partitioning $DEVICE..."
parted -s "$DEVICE" -- mklabel gpt
parted -s "$DEVICE" -- mkpart ESP fat32 1MiB 512MiB
parted -s "$DEVICE" -- set 1 esp on
parted -s "$DEVICE" -- mkpart primary btrfs 512MiB 100%

# Give the kernel a moment to register the new partitions
partprobe "$DEVICE"
sleep 2

PART1="${DEVICE}1"
PART2="${DEVICE}2"

# ── Format ────────────────────────────────────────────────────────────────────
info "Formatting partitions..."
mkfs.fat -F 32 -n BOOT "$PART1"
mkfs.btrfs -f -L nixos "$PART2"

# ── Create btrfs subvolumes ───────────────────────────────────────────────────
info "Creating btrfs subvolumes..."
mount "$PART2" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@persist
btrfs subvolume snapshot -r /mnt/@ /mnt/@blank

umount /mnt

# ── Mount for install ─────────────────────────────────────────────────────────
info "Mounting filesystems..."
mount -o subvol=@,compress=zstd,noatime "$PART2" /mnt
mkdir -p /mnt/{nix,persist,boot}
mount -o subvol=@nix,compress=zstd,noatime  "$PART2" /mnt/nix
mount -o subvol=@persist,compress=zstd,noatime "$PART2" /mnt/persist
mount "$PART1" /mnt/boot

# ── Seed /persist ─────────────────────────────────────────────────────────────
info "Seeding /persist..."
mkdir -p /mnt/persist/etc/ssh
mkdir -p /mnt/persist/etc/nixos
mkdir -p /mnt/persist/var/log
mkdir -p /mnt/persist/opt/live-transcribe

info "Generating SSH host keys..."
ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
ssh-keygen -t rsa    -b 4096 -N "" -f /mnt/persist/etc/ssh/ssh_host_rsa_key

echo ""
warn "New SSH host key (update secrets/secrets.nix with this after install):"
echo ""
cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
echo ""

# ── Install ───────────────────────────────────────────────────────────────────
info "Running nixos-install from ${FLAKE_URL}#${HOSTNAME} ..."
nixos-install --flake "${FLAKE_URL}#${HOSTNAME}" --no-root-passwd

echo ""
info "Install complete."
warn "Remember to re-encrypt agenix secrets with the new host key shown above."
warn "Run: agenix -r  (in the repo on your admin machine)"
echo ""
read -rp "Reboot now? [y/N]: " DO_REBOOT </dev/tty
[[ "${DO_REBOOT,,}" == "y" ]] && reboot
