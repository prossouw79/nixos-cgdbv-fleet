# Plan: Replace GNOME with cage kiosk compositor

Branch: `feat/cage-kiosk`

## Goal

Replace the GNOME desktop environment with `cage`, a minimal Wayland compositor
designed for single-application kiosks. This reduces install size and boot time
while preserving all kiosk behaviour (fullscreen Chrome, no sleep, auto-login,
crash recovery).

## What cage does differently

`services.cage` launches a bare Wayland compositor as a systemd service, runs
one program fullscreen, and exits when that program exits. There is no desktop
shell, no login screen, no window chrome — just the compositor and Chrome.
Auto-login and session management are handled by the cage systemd service itself,
replacing GDM entirely.

## Changes required in `modules/base.nix`

### 1. Remove GNOME/GDM block

Delete entirely:

```nix
services.xserver.displayManager.gdm.enable = true;
services.xserver.displayManager.gdm.autoSuspend = false;
services.xserver.desktopManager.gnome.enable = true;
environment.gnome.excludePackages = [ ... ];
programs.dconf.profiles.user.databases = [ ... ];
```

### 2. Remove GNOME-only packages from `environment.systemPackages`

```nix
gnomeExtensions.no-overview   # remove — GNOME-specific
vlc                            # optional: keep or remove, not needed for kiosk
vscode                         # optional: keep for remote dev access via SSH
```

### 3. Replace with cage service

`services.xserver.enable` can be set to false. cage uses Wayland directly.

```nix
services.cage = {
  enable  = true;
  user    = "admin";
  program = pkgs.writeShellScript "kiosk" ''
    # Disable DPMS (display sleep) at the Wayland/DRM level
    ${pkgs.wlr-randr}/bin/wlr-randr --output "*" --on 2>/dev/null || true

    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --no-sandbox \
      --test-type \
      --disable-dev-shm-usage \
      --hide-crash-restore-bubble \
      --noerrdialogs \
      --kiosk \
      --disable-features=UsePowerManagementApis \
      http://localhost:8885
  '';
};
```

Notes:
- `--kiosk` replaces `--start-fullscreen` (cage already fills the screen, but
  `--kiosk` also prevents the address bar from appearing on F11 etc.)
- `--disable-features=UsePowerManagementApis` tells Chrome not to touch DPMS
- `wlr-randr` disables display sleep at the compositor level (replaces the
  GNOME dconf idle/sleep settings)
- The `ExecStartPre sleep 5` delay from the GNOME version is not needed — cage
  ensures the compositor is ready before Chrome starts

### 4. Remove the separate `systemd.user.services.chrome-kiosk` block

Chrome is now launched directly by cage rather than as an independent systemd
user service. Crash recovery is handled by cage's own restart behaviour:

```nix
# cage restarts Chrome if it exits; add restart limits to still reboot on
# persistent failure
systemd.services.cage-1.serviceConfig = {
  Restart             = "on-failure";
  StartLimitBurst     = 5;
  StartLimitIntervalSec = 120;
};
# Reboot if cage exhausts its restart limit
systemd.services.cage-1.unitConfig.OnFailure = "reboot.target";
```

(NixOS names the cage service `cage-1` when `services.cage.user = "admin"`.)

### 5. Add `wlr-randr` to packages

```nix
pkgs.wlr-randr
```

### 6. Keep unchanged

- `services.xserver.enable` — can stay true (needed for X11 apps if any remain;
  set false if removing vscode/vlc)
- All systemd sleep target disables — still needed
- `services.logind.extraConfig` — still needed
- `systemd.watchdog` — still needed
- Docker / transcribe service — unchanged
- Auto-update service — unchanged
- PipeWire audio — unchanged (cage passes audio through to PipeWire normally)

## Things to verify after implementation

- [ ] Display does not sleep after idle period (DPMS off via wlr-randr)
- [ ] Chrome restarts automatically on crash
- [ ] System reboots after repeated Chrome failures
- [ ] Audio works through PipeWire (test with a page that plays sound)
- [ ] Tailscale still comes up (it's a system service, unaffected by DE change)
- [ ] Docker transcribe service starts before Chrome connects to localhost:8885
      (may need `ExecStartPre` delay in the cage program script if Chrome races
      ahead of the container)
- [ ] Wake-on-LAN still works (udev rule, unaffected by DE change)

## Estimated impact

| Metric | GNOME | cage |
|---|---|---|
| Additional packages | ~800 MB closure | ~50 MB closure |
| Time to first Chrome window | ~15–20 s | ~3–5 s |
| RAM at idle | ~400 MB | ~100 MB |

Numbers are approximate and will vary by machine.
