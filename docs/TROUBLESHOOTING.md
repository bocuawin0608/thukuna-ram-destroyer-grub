# INFERNAL — Troubleshooting & Emergency Recovery Guide

## 1. Automated Rollback via `uninstall.sh`

If you can boot into your Linux distribution and want to revert to your previous GRUB configuration:

```bash
sudo ./uninstall.sh
```

This verifies the SHA-256 checksum of the baseline snapshot in `/var/backups/infernal-grub-theme/`, restores `/etc/default/grub`, removes `/boot/grub/themes/infernal`, and regenerates `grub.cfg`.

---

## 2. Manual Rollback from Backup Snapshots

Every `--install` run creates a timestamped backup directory in `/var/backups/infernal-grub-theme/backup-<TIMESTAMP>-<PID>/` containing:
- `etc_default_grub.bak` and `etc_default_grub.sha256`
- `grub.cfg.bak` and `grub.cfg.sha256`
- `metadata.env`

To restore manually without running `grub-mkconfig`:

```bash
SNAP="$(cat /var/backups/infernal-grub-theme/baseline_backup.txt)"
sudo sha256sum -c "${SNAP}/etc_default_grub.sha256"
sudo sha256sum -c "${SNAP}/grub.cfg.sha256"
sudo cp -p "${SNAP}/etc_default_grub.bak" /etc/default/grub
sudo cp -p "${SNAP}/grub.cfg.bak" /boot/grub/grub.cfg
sudo rm -rf /boot/grub/themes/infernal
```

---

## 3. Recovery at the GRUB Boot Screen

Because INFERNAL never disables keyboard navigation, command-line access, or entry editing:

- **Boot normally even if a graphical asset fails**: Use `↑` and `↓` to select your entry and press `Enter`.
- **Switch to text console inside GRUB**: Press `c` to open the GRUB command line, then run:
  ```text
  terminal_output console
  normal
  ```
  This immediately switches GRUB to plain text mode for the current boot session so you can select your OS and run `sudo ./uninstall.sh`.
- **Edit kernel parameters**: Highlight any entry and press `e`, make changes, and press `Ctrl+X` or `F10` to boot.

---

## 4. Common Diagnostics

### Theme Does Not Appear (Black/Blue Text Box Shown Instead)
- Check `/etc/default/grub` for `GRUB_TERMINAL=console` or `GRUB_TERMINAL_OUTPUT="console"`. Note that `install.sh` automatically converts `GRUB_TERMINAL_OUTPUT="console"` to `GRUB_TERMINAL_OUTPUT="gfxterm"`, but if `GRUB_TERMINAL="console"` (without `_OUTPUT`) is set, comment it out (`#GRUB_TERMINAL=console`) and re-run `sudo ./install.sh --install`.
- Ensure `GRUB_GFXMODE` is set to a resolution supported by your UEFI GOP or BIOS VBE firmware (e.g., `GRUB_GFXMODE=1920x1080,auto`).

### Other Operating Systems (Windows / Dual-Boot Linux) Not Listed
1. Verify that `os-prober` is installed (`which os-prober`).
2. Ensure `/etc/default/grub` contains `GRUB_DISABLE_OS_PROBER=false`.
3. Re-run `sudo grub-mkconfig -o /boot/grub/grub.cfg` (or `sudo ./install.sh --install`).

