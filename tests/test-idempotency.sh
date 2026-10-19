#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Idempotency & Multi-Run Test Suite (tests/test-idempotency.sh)
# ==============================================================================
# Verifies that repeated executions of --install and --uninstall never create
# duplicate GRUB_THEME entries, never corrupt /etc/default/grub, and always
# restore the exact pre-INFERNAL baseline configuration.
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

printf '=== Running INFERNAL Idempotency Test Suite ===\n'

sb="$(create_mock_sandbox)"; SANDBOXES+=("${sb}")
populate_distro_fixture "${sb}/root" "endeavouros" "arch" "EndeavourOS" "uefi" "grub"
setup_mock_binaries "${sb}/bin" "pacman" "grub-mkconfig"

# Add a pre-existing theme and a commented GRUB_THEME line to test deduplication
cat >> "${sb}/root/etc/default/grub" <<'EOF'
#GRUB_THEME="/usr/share/grub/themes/starfield/theme.txt"
GRUB_THEME="/boot/grub/themes/previous-custom/theme.txt"
EOF

baseline_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"

# Run 1
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --yes >/dev/null
sha_run1="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
cfg_run1="$(sha256sum "${sb}/root/boot/grub/grub.cfg" | awk '{print $1}')"

# Run 2
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --yes >/dev/null
sha_run2="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
cfg_run2="$(sha256sum "${sb}/root/boot/grub/grub.cfg" | awk '{print $1}')"

# Run 3
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/install.sh" --install --yes >/dev/null
sha_run3="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
cfg_run3="$(sha256sum "${sb}/root/boot/grub/grub.cfg" | awk '{print $1}')"

assert_eq "${sha_run2}" "${sha_run1}" "Idempotent /etc/default/grub hash on 2nd install"
assert_eq "${sha_run3}" "${sha_run1}" "Idempotent /etc/default/grub hash on 3rd install"
assert_eq "${cfg_run2}" "${cfg_run1}" "Idempotent grub.cfg hash on 2nd install"
assert_eq "${cfg_run3}" "${cfg_run1}" "Idempotent grub.cfg hash on 3rd install"

theme_line_count="$(grep -c 'GRUB_THEME=' "${sb}/root/etc/default/grub" || true)"
assert_eq "${theme_line_count}" "1" "Exactly 1 GRUB_THEME line exists after 3 installs"

# Uninstall after 3 installs must restore the pre-INFERNAL baseline (including previous-custom theme)
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/uninstall.sh" --yes >/dev/null
restored_sha="$(sha256sum "${sb}/root/etc/default/grub" | awk '{print $1}')"
assert_eq "${restored_sha}" "${baseline_sha}" "Uninstall after 3 installs restores exact pre-INFERNAL baseline"

# Second uninstall must be a safe no-op
INFERNAL_ROOT="${sb}/root" INFERNAL_BIN_DIR="${sb}/bin" "${PROJECT_ROOT}/uninstall.sh" --yes >/dev/null
pass_test "Repeated uninstall succeeds cleanly as idempotent no-op"

printf '\nIdempotency Suite Summary: %d passed, %d failed\n' "${TESTS_Passed}" "${TESTS_Failed}"
[[ "${TESTS_Failed}" -eq 0 ]]

