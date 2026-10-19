#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Automated Installer & Rollback Test Suite (tests/test-installer.sh)
# ==============================================================================
# Tests dry-run, installation, resolution variants, read-only error handling,
# missing asset detection, mid-install interruption + automatic rollback,
# large menus with long OS names, and safe uninstallation.
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
source "${TEST_DIR}/test-helpers.sh"

SANDBOXES=()
cleanup() {
    local sb
    for sb in "${SANDBOXES[@]}"; do
        [[ -n "${sb}" && -d "${sb}" ]] && chmod -R u+w "${sb}" 2>/dev/null || true
        [[ -n "${sb}" && -d "${sb}" ]] && rm -rf "${sb}"
    done
}
trap cleanup EXIT

printf '=== Running INFERNAL Installer & Rollback Test Suite ===\n'

# 1. Default invocation (no args) and --dry-run must never modify files
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "endeavouros" "arch" "EndeavourOS" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
orig_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"

INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" >/dev/null
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --dry-run >/dev/null
after_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
assert_eq "${after_sha}" "${orig_sha}" "Default and --dry-run modes do not modify /etc/default/grub"
if [[ ! -d "${sb}/root/boot/grub/themes/infernal" ]]; then
    pass_test "--dry-run does not create theme directory"
else
    fail_test "--dry-run does not create theme directory" "Directory was created"
fi

# 2. Full installation on EndeavourOS + preservation of sibling themes & OS entries
mkdir -p "${sb}/root/boot/grub/themes/existing-user-theme"
touch "${sb}/root/boot/grub/themes/existing-user-theme/keep.txt"
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --yes >/dev/null

if [[ -f "${sb}/root/boot/grub/themes/infernal/theme.txt" ]]; then
    pass_test "--install installs theme/theme.txt into /boot/grub/themes/infernal"
else
    fail_test "--install installs theme/theme.txt" "File missing"
fi

def_content="$(cat "${sb}/root/etc/default/grub")"
assert_contains "${def_content}" 'GRUB_THEME="/boot/grub/themes/infernal/theme.txt"' "GRUB_THEME set in /etc/default/grub"
assert_contains "${def_content}" 'GRUB_DEFAULT="saved"' "GRUB_DEFAULT preserved during install"
assert_contains "${def_content}" 'GRUB_TIMEOUT=5' "GRUB_TIMEOUT preserved during install"
assert_contains "${def_content}" 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"' "Kernel cmdline preserved"

cfg_content="$(cat "${sb}/root/boot/grub/grub.cfg")"
assert_contains "${cfg_content}" "Windows Boot Manager (on /dev/nvme0n1p1)" "Windows entry preserved in grub.cfg"
assert_contains "${cfg_content}" "Ubuntu 24.04 LTS (on /dev/nvme0n1p4)" "Ubuntu entry preserved in grub.cfg"
assert_contains "${cfg_content}" "set theme=(\$root)/boot/grub/themes/infernal/theme.txt" "Theme activated in grub.cfg"

# 3. Uninstall restores original /etc/default/grub and preserves sibling themes
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/uninstall.sh" --yes >/dev/null
uninst_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
assert_eq "${uninst_sha}" "${orig_sha}" "uninstall.sh restores exact byte-for-byte original /etc/default/grub"
if [[ ! -d "${sb}/root/boot/grub/themes/infernal" && -f "${sb}/root/boot/grub/themes/existing-user-theme/keep.txt" ]]; then
    pass_test "uninstall.sh removes only infernal dir and preserves sibling themes"
else
    fail_test "uninstall.sh sibling theme preservation" "Unexpected directory state"
fi

# 4. Interrupted installation & automatic rollback verification
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "arch" "arch" "Arch Linux" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
orig_def_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
orig_cfg_sha="$(sha256sum "${sb}/root/boot/grub/grub.cfg" | awk '{print $1}')"

set +e
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" INFERNAL_SIMULATE_INTERRUPT=1 "${PROJECT_ROOT}/install.sh" --install --yes 2>&1)"
rc=$?
set -e
assert_eq "${rc}" "1" "Interrupted installation exits with non-zero status"
assert_contains "${out}" "Executing automatic rollback" "Rollback trap triggered on interruption"
post_def_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
post_cfg_sha="$(sha256sum "${sb}/root/boot/grub/grub.cfg" | awk '{print $1}')"
assert_eq "${post_def_sha}" "${orig_def_sha}" "Rollback restores /etc/default/grub after interruption"
assert_eq "${post_cfg_sha}" "${orig_cfg_sha}" "Rollback restores grub.cfg after interruption"
if [[ ! -d "${sb}/root/boot/grub/themes/infernal" ]]; then
    pass_test "Rollback cleans up partially installed theme directory"
else
    fail_test "Rollback cleans up partially installed theme directory" "Directory still exists"
fi

# 5. Read-only /etc/default/grub rejected safely
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "arch" "arch" "Arch Linux" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
chmod 0444 "${sb}/root/etc/default/grub"
set +e
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --yes 2>&1)"
rc=$?
set -e
chmod 0644 "${sb}/root/etc/default/grub"
assert_eq "${rc}" "1" "Read-only /etc/default/grub aborts installation safely"
assert_contains "${out}" "read-only or not writable" "Read-only configuration diagnostic"

# 6. Missing theme asset detection in validate-theme.sh
bad_theme="$(mktemp -d)"; SANDBOXES+=("${bad_theme}")
cp -r "${PROJECT_ROOT}/theme/"* "${bad_theme}/"
rm -f "${bad_theme}/assets/selection/select_w.png"
set +e
out="$("${PROJECT_ROOT}/scripts/validate-theme.sh" "${bad_theme}" 2>&1)"
rc=$?
set -e
assert_eq "${rc}" "1" "Missing 9-slice asset detected by validate-theme.sh"
assert_contains "${out}" "Missing or invalid 9-slice asset" "Missing 9-slice diagnostic message"

# 7. Large boot menu & long OS names (12 entries + real grub-script-check validation)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "fedora" "fedora" "Fedora Linux 41" "uefi" "grub2"
setup_mock_binaries "${sb}/bin" "dnf" "grub2-mkconfig"
for i in $(seq 1 12); do
    cat >> "${sb}/root/boot/grub2/grub.cfg" <<EOF
menuentry 'Fedora Linux (6.12.${i}-200.fc41.x86_64) 41 (Workstation Edition — Enterprise Snapshot #${i})' --class fedora {
    linux /boot/vmlinuz-6.12.${i} root=UUID=abcd-1234 ro rhgb quiet
}
EOF
done
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --resolution 2560x1440 --yes >/dev/null
long_cfg="$(cat "${sb}/root/boot/grub2/grub.cfg")"
assert_contains "${long_cfg}" "Enterprise Snapshot #12" "Large boot menu (12+ long OS entries) preserved and validated"

printf '\nInstaller Suite Summary: %d passed, %d failed\n' "${TESTS_Passed}" "${TESTS_Failed}"
[[ "${TESTS_Failed}" -eq 0 ]]

