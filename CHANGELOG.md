# Changelog

All notable changes to the CGDBV NixOS Fleet configuration will be documented in this file.

## [1.0.0] - 2026-04-08

### Initial Release

This is the first versioned release of the CGDBV NixOS fleet configuration. The repository
establishes a fully declarative, self-updating fleet of kiosk machines built on NixOS 24.11.

---

### Architecture

- **Ephemeral root filesystem** via Btrfs subvolumes: the root (`/`) is rolled back to a blank
  snapshot on every boot, ensuring a clean, predictable state. Persistent data lives exclusively
  under `/persist`.
- **Self-updating deployments**: each machine runs a systemd timer that pulls and applies the
  latest configuration from `github:prossouw79/nixos-cgdbv-fleet` every 5 minutes, with an
  automatic reboot if the running kernel differs from the new generation.
- **Offline installation ISO**: a bootable NixOS ISO target pre-loads the `generic` host closure
  into the Nix store, enabling air-gapped installation via `scripts/install.sh`.

---

### Hosts

| Host | Architecture | Purpose |
|------|-------------|---------|
| `optiplex1` | x86_64-linux | Physical Dell OptiPlex kiosk, unit 1 |
| `optiplex2` | x86_64-linux | Physical Dell OptiPlex kiosk, unit 2 |
| `generic`   | x86_64-linux | Blank install target (hostname overridden via `local.nix`) |
| `iso`       | x86_64-linux | Bootable NixOS installer image |

---

### Core Features (modules/base.nix)

**Boot & Filesystem**
- systemd-boot with a 5-generation limit
- Btrfs subvolumes (`@`, `@nix`, `@persist`) with zstd compression
- Root rollback to `@blank` snapshot in `initrd.postDeviceCommands`
- Impermanence module managing explicit persistence of `/var/log`, `/var/lib/tailscale`,
  `/var/lib/docker`, `/var/lib/nixos`, SSH host keys, and `/etc/nixos/local.nix`

**Desktop (GNOME Kiosk)**
- GNOME 24.11 with GDM, auto-login as `admin` user
- Screensaver, screen lock, idle suspend, and all sleep/hibernate states disabled
- GNOME extension: `no-overview` to bypass the Activities screen on startup
- Hardware watchdog (30 s) and systemd power inhibitors ensure machines never idle offline

**Live Transcribe Service**
- Docker Compose service running `prossouw79/grtspwhspr` on port 8885
- Consumes an RTSP stream (`100.94.100.86:8554`) and transcribes audio via OpenAI Whisper (English)
- Compose files deployed to `/opt/docker-compose/transcribe` via `systemd-tmpfiles`

**Chrome Kiosk**
- Systemd user service launches Google Chrome pointed at `http://localhost:8885`
- Fullscreen, no first-run dialogs, no crash-restore prompts
- Restarts on failure (5 s delay); reboots the machine if Chrome fails 5 times within 120 s

**Networking & Remote Management**
- NetworkManager with Wi-Fi powersave disabled
- Tailscale enabled for secure remote access (post-boot activation required)
- Wake-on-LAN enabled for all Ethernet interfaces via udev rules
- Glances monitoring exposed on port 61208

**Auto-Update**
- `nixos-rebuild-update` systemd service + timer: runs every 5 minutes and on
  `network-online.target`
- Detects running hostname, rebuilds from flake, records applied commit hash and timestamp to
  `/persist/manifest.txt`
- Skips concurrent runs; reboots automatically when the booted system generation changes

**Locale & Time**
- Timezone: `Africa/Johannesburg`
- Locale: `en_ZA.UTF-8`

---

### Flake Inputs

| Input | Source | Pinned Version |
|-------|--------|---------------|
| `nixpkgs` | `nixos-24.11` (stable) | `e4bae1b` (Dec 2024) |
| `agenix` | `github:ryantm/agenix` | `b027ee2` (Dec 2024) |
| `impermanence` | `github:nix-community/impermanence` | `7b1d382` (Dec 2024) |

All inputs follow `inputs.nixpkgs.follows = "nixpkgs"` to avoid duplicate dependency fetches.

---

### Tooling

- **`scripts/install.sh`**: interactive installer — wipes disk, partitions (EFI + Btrfs), creates
  subvolumes, seeds `/persist` with SSH host keys, and runs `nixos-install` against the flake.
- **`Makefile`**: Docker-wrapped CI targets — `check`, `build`, `eval`, `iso`, `lock`, `clean`.
- **`docker-compose.yml`** (dev): mounts the repo into a `nixpkgs/nix` container with a
  persistent Nix store volume for fast local iteration.
- **`local.nix.template`**: per-machine Wi-Fi credential template; copied to
  `/persist/etc/nixos/local.nix` at install time and excluded from version control.

---

### Known Limitations / Work In Progress

- **Agenix secrets not yet deployed**: `secrets/secrets.nix` scaffolds encrypted secret support,
  but device SSH host keys are still placeholders (`AAAA__REPLACE_WITH_...__`). Wi-Fi PSKs are
  currently stored in the untracked `local.nix` rather than encrypted `.age` files.
- **Home Manager not integrated**: present as a transitive dependency but not wired up; user
  environment is managed at the system level.
- **No GitHub Actions CI**: the flake is public and machines pull directly from GitHub, but
  there are no automated CI workflows validating PRs before merge.
- **Tailscale auth manual**: after first boot, `sudo tailscale up --authkey=<key>` must be run
  by hand; no pre-auth key automation yet.
