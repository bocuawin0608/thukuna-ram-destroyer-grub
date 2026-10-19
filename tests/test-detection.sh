#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Automated Detection Test Suite (tests/test-detection.sh)
# ==============================================================================
# Tests OS, package manager, firmware (UEFI/BIOS), multi-OS entry discovery,
# custom GRUB entries, systemd-boot/rEFInd protection, and missing dependencies
# inside disposable mock sandboxes.
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
        [[ -n "${sb}" && -d "${sb}" ]] && rm -rf "${sb}"
    done
}
trap cleanup EXIT

printf '=== Running INFERNAL Detection Test Suite ===\n'

# 1. Arch Linux with GRUB (UEFI + Windows + Multiple Linux + 40_custom)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "arch" "arch" "Arch Linux" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "ID=arch" "Arch Linux distro detection"
assert_contains "${out}" "pacman (family=arch)" "Arch pacman package manager detection"
assert_contains "${out}" "Firmware Mode       : uefi" "UEFI firmware mode detection"
assert_contains "${out}" "Windows Boot Manager" "Windows Boot Manager discovery"
assert_contains "${out}" "Ubuntu 24.04 LTS" "Multi-Linux OS entry discovery"
assert_contains "${out}" "System Rescue Live ISO (Custom)" "Custom 40_custom entry discovery"

# 2. EndeavourOS with GRUB
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "endeavouros" "arch" "EndeavourOS" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "EndeavourOS (ID=endeavouros, LIKE=arch)" "EndeavourOS distro detection"
assert_contains "${out}" "pacman (family=arch)" "EndeavourOS pacman detection"

# 3. Debian / Ubuntu with GRUB
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "ubuntu" "debian" "Ubuntu 24.04.1 LTS" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "apt-get" "grub-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "Ubuntu 24.04.1 LTS (ID=ubuntu, LIKE=debian)" "Ubuntu/Debian distro detection"
assert_contains "${out}" "apt-get (family=debian)" "apt-get package manager detection"

# 4. Fedora with GRUB2 (/boot/grub2/grub.cfg & grub2-mkconfig)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "fedora" "fedora" "Fedora Linux 41" "uefi" "grub2"
setup_mock_binaries "${sb}/bin" "dnf" "grub2-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "Fedora Linux 41 (ID=fedora" "Fedora distro detection"
assert_contains "${out}" "dnf (family=fedora)" "dnf package manager detection"
assert_contains "${out}" "/boot/grub2/grub.cfg" "Fedora /boot/grub2/grub.cfg path detection"

# 5. openSUSE with zypper & GRUB2
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "opensuse-tumbleweed" "opensuse suse" "openSUSE Tumbleweed" "uefi" "grub2"
setup_mock_binaries "${sb}/bin" "zypper" "grub2-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "zypper (family=suse)" "openSUSE zypper package manager detection"

# 6. Legacy BIOS Mode
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "debian" "debian" "Debian GNU/Linux 12" "bios" "grub"
setup_mock_binaries "${sb}/bin" "apt-get" "grub-mkconfig"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "Firmware Mode       : bios" "Legacy BIOS mode detection"
assert_contains "${out}" "not-applicable (legacy BIOS)" "Legacy BIOS Secure Boot status"

# 7. systemd-boot instead of GRUB (must refuse installation safely)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
mkdir -p "${sb}/root/boot/loader" "${sb}/root/etc"
cat > "${sb}/root/etc/os-release" <<'EOF'
ID=arch
PRETTY_NAME="Arch Linux"
EOF
cat > "${sb}/root/boot/loader/loader.conf" <<'EOF'
default arch.conf
timeout 3
EOF
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"
set +e
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
rc=$?
set -e
assert_eq "${rc}" "1" "systemd-boot active rejects GRUB theme installation"
assert_contains "${out}" "Active bootloader is \"systemd-boot\"" "systemd-boot active bootloader diagnostic"

# 8. Missing GRUB utilities
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "arch" "arch" "Arch Linux" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "none"
set +e
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
rc=$?
set -e
assert_eq "${rc}" "1" "Missing grub-mkconfig fails compatibility check"
assert_contains "${out}" "Missing required dependencies: grub" "Missing grub-mkconfig diagnostic"

# 9. Missing optional dependencies (os-prober, efibootmgr absent)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "arch" "arch" "Arch Linux" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig" "grub-mkconfig (GRUB) 2:2.16-1" "false"
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
assert_contains "${out}" "Missing Optional    : os-prober" "Missing optional dependencies reported"
assert_contains "${out}" "compatible with INFERNAL Type C theme" "Compatible when only optional deps are missing"

# 10. Unsupported GRUB version (GRUB Legacy 0.97)
sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "debian" "debian" "Debian Legacy" "bios" "grub"
setup_mock_binaries "${sb}/bin" "apt-get" "grub-mkconfig" "grub (GNU GRUB 0.97)"
set +e
out="$(INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --check 2>&1)"
rc=$?
set -e
assert_eq "${rc}" "1" "Unsupported GRUB 0.97 rejected safely"
assert_contains "${out}" "does not support gfxmenu themes" "Unsupported GRUB version diagnostic"

printf '\nDetection Suite Summary: %d passed, %d failed\n' "${TESTS_Passed}" "${TESTS_Failed}"
[[ "${TESTS_Failed}" -eq 0 ]]

