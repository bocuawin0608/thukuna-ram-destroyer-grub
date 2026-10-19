# INFERNAL — Installation, Preview & Rollback Guide

## 1. Pre-Flight Inspection & Preview (Zero Host Changes)

Before making any changes to your bootloader configuration, inspect your environment and validate all theme assets:

```bash
# 1. Validate theme.txt syntax, 9-slice PNGs, and .pf2 font headers
./scripts/validate-theme.sh

# 2. Inspect distro, package manager, UEFI/BIOS state, and discovered OS entries
./install.sh --check

# 3. Preview exact planned changes and unified diff of /etc/default/grub
./install.sh --dry-run
```

### Visual Preview Before Activating

- Inspect the rendered 1920×1080 Type C composition at [`docs/previews/preview_type_c.png`](previews/preview_type_c.png).
- Inspect active vs. inactive entry states and scrollbar behavior at [`docs/previews/preview_states_and_long_menu.png`](previews/preview_states_and_long_menu.png).
- If `grub-emu` or `qemu-system-x86_64` with a test ISO (`grub-mkrescue`) is installed, you can test the theme inside a disposable VM without touching `/boot`:
  ```bash
  # Optional isolated test in a temporary directory
  ./tests/test-detection.sh && ./tests/test-installer.sh && ./tests/test-idempotency.sh
  ```

---

## 2. Installing the Theme

Run the installer with root privileges (`sudo`) and the explicit `--install` flag:

```bash
# Standard installation (1920x1080 16:9 Type C background)
sudo ./install.sh --install
```

### Selecting a Resolution Variant or Custom Background

```bash
# 2560x1440 (16:9 QHD)
sudo ./install.sh --install --resolution 2560x1440

# 1920x1200 (16:10 WUXGA)
sudo ./install.sh --install --resolution 1920x1200

# 1024x768 (4:3 Legacy / VBE framebuffer)
sudo ./install.sh --install --resolution 1024x768

# Untouched original source image (1024x576)
sudo ./install.sh --install --resolution original

# Custom PNG background
sudo ./install.sh --install --background /path/to/your-background.png
```

### What `--install` Does Step-by-Step

1. Validates `theme/theme.txt`, all 9-slice pixmaps, `.pf2` font headers, and OS icons.
2. Verifies that GNU GRUB (`>= 2.00`) is the active bootloader.
3. Creates a timestamped, SHA-256 checksummed backup of `/etc/default/grub` and the active `grub.cfg` under `/var/backups/infernal-grub-theme/`.
4. Arms an automatic rollback trap (`EXIT` / `INT` / `TERM`) so any failure during installation immediately restores the backup.
5. Copies the theme into `/boot/grub/themes/infernal` (or `/boot/grub2/themes/infernal`).
6. Updates `GRUB_THEME="/boot/grub/themes/infernal/theme.txt"` idempotently in `/etc/default/grub` while preserving `GRUB_DEFAULT`, `GRUB_TIMEOUT`, `GRUB_CMDLINE_LINUX*`, and `GRUB_DISABLE_OS_PROBER`.
7. Regenerates `grub.cfg` into a temporary file, validates its syntax with `grub-script-check`, and atomically updates the active `grub.cfg`.

---

## 3. Uninstalling & Restoring the Previous Theme

To remove INFERNAL and restore your exact pre-INFERNAL `/etc/default/grub` (including any previous custom theme):

```bash
sudo ./uninstall.sh
# or equivalently:
sudo ./install.sh --uninstall
```

