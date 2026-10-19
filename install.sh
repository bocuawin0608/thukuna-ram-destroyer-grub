#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Cinematic Universal GRUB Theme Installer (install.sh)
# ==============================================================================
# Production-grade, idempotent, distribution-aware GRUB theme installer.
# Default behavior (no flags) prints help and never modifies the host system.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/detect-system.sh
source "${SCRIPT_DIR}/scripts/detect-system.sh"
# shellcheck source=scripts/detect-bootloaders.sh
source "${SCRIPT_DIR}/scripts/detect-bootloaders.sh"
# shellcheck source=scripts/validate-theme.sh
source "${SCRIPT_DIR}/scripts/validate-theme.sh"
# shellcheck source=scripts/backup-restore.sh
source "${SCRIPT_DIR}/scripts/backup-restore.sh"

MODE=""
ASSUME_YES="false"
SELECTED_RES="1920x1080"
CUSTOM_BG=""
TEMP_FILES=()
ROLLBACK_ARMED="false"
INSTALLED_THEME_DIR=""

cleanup_and_rollback() {
    local exit_code=$?
    local f
    for f in "${TEMP_FILES[@]}"; do
        [[ -n "${f}" && -e "${f}" ]] && rm -f "${f}"
    done

    if [[ "${ROLLBACK_ARMED}" == "true" && "${exit_code}" -ne 0 ]]; then
        printf '\n[ALERT] Installation interrupted or failed (exit=%d). Executing automatic rollback...\n' "${exit_code}" >&2
        if [[ -n "${INSTALLED_THEME_DIR}" && "${INSTALLED_THEME_DIR}" == */themes/infernal && -d "${INSTALLED_THEME_DIR}" ]]; then
            rm -rf "${INSTALLED_THEME_DIR}"
        fi
        restore_backup "latest" "true" || true
        printf '[OK] Rollback completed. Previous GRUB state restored.\n' >&2
    fi
    exit "${exit_code}"
}
trap cleanup_and_rollback EXIT INT TERM

print_usage() {
    cat <<'EOF'
INFERNAL — Cinematic Universal GRUB Theme (Type C: Lower-Water Ritual Console)

Usage:
  ./install.sh [MODE] [OPTIONS]

Modes (explicit mode required; running without a mode does not modify the system):
  --check                 Inspect system, bootloader, OS entries, and theme validity (read-only)
  --dry-run               Show all planned configuration and file changes without modifying the host
  --install               Install the INFERNAL theme, back up existing configs, and update GRUB
  --uninstall             Remove the INFERNAL theme and restore previous GRUB configuration
  -h, --help              Show this help message and exit

Options:
  --resolution <RES>      Select background variant: 1920x1080 (default), 2560x1440, 1920x1200, 1024x768, original
  --background <PATH>     Use a custom PNG background file (validated before installation)
  -y, --yes               Skip interactive confirmation prompts (for automated/scripted runs)
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check|--dry-run|--install|--uninstall)
                if [[ -n "${MODE}" && "${MODE}" != "$1" ]]; then
                    printf '[ERROR] Conflicting modes specified: %s and %s\n' "${MODE}" "$1" >&2
                    exit 1
                fi
                MODE="$1"
                shift
                ;;
            --resolution)
                if [[ $# -lt 2 ]]; then
                    printf '[ERROR] --resolution requires an argument (e.g. 1920x1080, 2560x1440, 1920x1200, 1024x768, original)\n' >&2
                    exit 1
                fi
                SELECTED_RES="$2"
                shift 2
                ;;
            --background)
                if [[ $# -lt 2 ]]; then
                    printf '[ERROR] --background requires a path to a PNG image\n' >&2
                    exit 1
                fi
                CUSTOM_BG="$2"
                shift 2
                ;;
            -y|--yes)
                ASSUME_YES="true"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                printf '[ERROR] Unknown argument: %s\n' "$1" >&2
                print_usage >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "${MODE}" ]]; then
        print_usage
        exit 0
    fi
}

resolve_background_source() {
    local theme_src="${SCRIPT_DIR}/theme"
    if [[ -n "${CUSTOM_BG}" ]]; then
        if ! check_png_magic "${CUSTOM_BG}"; then
            printf '[ERROR] Custom background is missing or not a valid PNG file: %s\n' "${CUSTOM_BG}" >&2
            return 1
        fi
        printf '%s\n' "${CUSTOM_BG}"
        return 0
    fi

    case "${SELECTED_RES}" in
        1920x1080) printf '%s\n' "${theme_src}/backgrounds/infernal.png" ;;
        2560x1440) printf '%s\n' "${theme_src}/backgrounds/infernal-2560x1440.png" ;;
        1920x1200) printf '%s\n' "${theme_src}/backgrounds/infernal-1920x1200.png" ;;
        1024x768)  printf '%s\n' "${theme_src}/backgrounds/infernal-1024x768.png" ;;
        original)  printf '%s\n' "${theme_src}/backgrounds/original.png" ;;
        *)
            printf '[ERROR] Unsupported --resolution "%s". Choose: 1920x1080, 2560x1440, 1920x1200, 1024x768, original\n' "${SELECTED_RES}" >&2
            return 1
            ;;
    esac
}

verify_compatibility() {
    local errors=0

    # 1. Validate bundled theme assets
    if ! validate_theme_dir "${SCRIPT_DIR}/theme"; then
        errors=$((errors + 1))
    fi

    # 2. Validate selected background
    local bg_src
    if ! bg_src="$(resolve_background_source)"; then
        errors=$((errors + 1))
    fi

    # 3. Run full system & bootloader discovery
    run_bootloader_detection

    # 4. Verify active bootloader is GRUB
    if [[ "${ACTIVE_BOOTLOADER}" != "grub" ]]; then
        printf '[ERROR] Active bootloader is "%s" (Alternatives detected: %s).\n' \
            "${ACTIVE_BOOTLOADER}" "${ALTERNATIVE_BOOTLOADERS[*]:-none}" >&2
        printf '        INFERNAL themes GNU GRUB only and will never silently replace systemd-boot, rEFInd, or firmware boot order.\n' >&2
        errors=$((errors + 1))
    fi

    # 5. Verify required GRUB utilities and version
    if [[ ${#MISSING_REQUIRED_DEPS[@]} -gt 0 ]]; then
        printf '[ERROR] Missing required dependencies: %s\n' "${MISSING_REQUIRED_DEPS[*]}" >&2
        printf '        Suggested remediation (%s): %s\n' "${PKG_MANAGER}" "$(get_package_install_hint)" >&2
        errors=$((errors + 1))
    elif [[ "${GRUB_THEME_SUPPORTED}" != "true" ]]; then
        printf '[ERROR] Installed GRUB version (%s) does not support gfxmenu themes (requires GRUB >= 2.00).\n' \
            "${GRUB_VERSION_STR}" >&2
        errors=$((errors + 1))
    fi

    # 6. Verify GRUB configuration files exist
    if [[ ! -f "${GRUB_DEFAULT_FILE}" ]]; then
        printf '[ERROR] GRUB configuration file not found at %s\n' "${GRUB_DEFAULT_FILE}" >&2
        errors=$((errors + 1))
    fi

    if [[ -z "${GRUB_THEMES_DIR}" || -z "${GRUB_CFG_PATH}" ]]; then
        printf '[ERROR] Could not locate active GRUB directory (/boot/grub or /boot/grub2).\n' >&2
        errors=$((errors + 1))
    fi

    return "${errors}"
}

build_updated_grub_default() {
    local src_file="$1"
    local theme_txt_path="$2"
    local out_file="$3"

    local theme_set="false"
    : > "${out_file}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*#?[[:space:]]*GRUB_THEME= ]]; then
            if [[ "${theme_set}" == "false" ]]; then
                printf 'GRUB_THEME="%s"\n' "${theme_txt_path}" >> "${out_file}"
                theme_set="true"
            fi
            # Skip any duplicate GRUB_THEME lines to guarantee idempotency
            continue
        fi
        # If GRUB_TERMINAL_OUTPUT is explicitly locked to "console", switch to "gfxterm" so themes render
        if [[ "${line}" =~ ^[[:space:]]*GRUB_TERMINAL_OUTPUT=[\"\']?console[\"\']?[[:space:]]*$ ]]; then
            printf 'GRUB_TERMINAL_OUTPUT="gfxterm"\n' >> "${out_file}"
            continue
        fi
        printf '%s\n' "${line}" >> "${out_file}"
    done < "${src_file}"

    if [[ "${theme_set}" == "false" ]]; then
        printf 'GRUB_THEME="%s"\n' "${theme_txt_path}" >> "${out_file}"
    fi
}

build_uninstalled_grub_default() {
    local src_file="$1"
    local out_file="$2"

    : > "${out_file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*GRUB_THEME=.*infernal/theme\.txt ]]; then
            continue
        fi
        printf '%s\n' "${line}" >> "${out_file}"
    done < "${src_file}"
}

check_privileges_and_writable() {
    if [[ "${INFERNAL_ROOT}" == "/" && "${EUID}" -ne 0 ]]; then
        printf '[ERROR] Modifying host GRUB configuration requires root privileges (run with sudo).\n' >&2
        return 1
    fi

    local parent_boot
    parent_boot="$(dirname "${GRUB_THEMES_DIR}")"
    if [[ ! -w "${GRUB_DEFAULT_FILE}" ]]; then
        printf '[ERROR] Configuration file is read-only or not writable: %s\n' "${GRUB_DEFAULT_FILE}" >&2
        return 1
    fi
    if [[ ! -d "${parent_boot}" || ! -w "${parent_boot}" ]]; then
        printf '[ERROR] Boot directory is read-only or not writable: %s\n' "${parent_boot}" >&2
        return 1
    fi
    if [[ -f "${GRUB_CFG_PATH}" && ! -w "${GRUB_CFG_PATH}" ]]; then
        printf '[ERROR] Active GRUB config is read-only or not writable: %s\n' "${GRUB_CFG_PATH}" >&2
        return 1
    fi

    # Check available space on target filesystem (require at least 15 MiB)
    local avail_kb
    avail_kb="$(df -Pk "${parent_boot}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 999999)"
    if [[ "${avail_kb}" =~ ^[0-9]+$ ]] && (( avail_kb < 15360 )); then
        printf '[ERROR] Insufficient disk space on %s (%s KiB available, >= 15360 KiB required).\n' \
            "${parent_boot}" "${avail_kb}" >&2
        return 1
    fi

    return 0
}

confirm_action() {
    local prompt_msg="$1"
    if [[ "${ASSUME_YES}" == "true" ]]; then
        return 0
    fi
    printf '%s [y/N]: ' "${prompt_msg}"
    local reply=""
    read -r reply || true
    case "${reply}" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *)
            printf '[INFO] Operation cancelled by user.\n'
            exit 0
            ;;
    esac
}

run_check_mode() {
    print_system_report
    printf '\n'
    print_bootloader_report
    printf '\n'
    if ! verify_compatibility; then
        printf '\n[RESULT] --check: System or configuration is NOT compatible with automatic installation.\n' >&2
        return 1
    fi
    printf '\n[RESULT] --check: System and bootloader are compatible with INFERNAL Type C theme.\n'
    return 0
}

run_dry_run_mode() {
    if ! verify_compatibility; then
        printf '[FAIL] --dry-run aborted due to compatibility errors above.\n' >&2
        return 1
    fi

    local target_theme_dir="${GRUB_THEMES_DIR}/infernal"
    local logical_theme_txt="${target_theme_dir#${INFERNAL_ROOT%/}}/theme.txt"
    [[ "${INFERNAL_ROOT}" == "/" ]] && logical_theme_txt="${target_theme_dir}/theme.txt"

    local tmp_default
    tmp_default="$(mktemp)"
    TEMP_FILES+=("${tmp_default}")
    build_updated_grub_default "${GRUB_DEFAULT_FILE}" "${logical_theme_txt}" "${tmp_default}"

    local bg_src
    bg_src="$(resolve_background_source)"

    printf '\n=== DRY-RUN PLANNED CHANGES (No host files modified) ===\n'
    printf '1. Theme Destination : %s\n' "${target_theme_dir}"
    printf '2. Selected Background: %s (resolution=%s)\n' "${bg_src}" "${SELECTED_RES}"
    printf '3. Backup Directory  : %s\n' "$(get_backup_base_dir)"
    printf '4. Preserved Settings: GRUB_DEFAULT=%s, GRUB_TIMEOUT=%s, Entries=%d\n' \
        "${CURRENT_GRUB_DEFAULT}" "${CURRENT_GRUB_TIMEOUT}" "${#DISCOVERED_GRUB_ENTRIES[@]}"
    printf '5. Config regeneration command:\n   %s -o "%s"\n' "${GRUB_MKCONFIG_BIN}" "${GRUB_CFG_PATH}"
    printf '6. Proposed changes to %s:\n' "${GRUB_DEFAULT_FILE}"
    diff -u "${GRUB_DEFAULT_FILE}" "${tmp_default}" || true
    printf '\n[RESULT] --dry-run completed successfully. Zero files were modified.\n'
    return 0
}

run_install_mode() {
    if ! verify_compatibility; then
        printf '[FAIL] Installation aborted due to compatibility check failures.\n' >&2
        return 1
    fi

    if ! check_privileges_and_writable; then
        return 1
    fi

    local target_theme_dir="${GRUB_THEMES_DIR}/infernal"
    local logical_theme_txt="${target_theme_dir#${INFERNAL_ROOT%/}}/theme.txt"
    [[ "${INFERNAL_ROOT}" == "/" ]] && logical_theme_txt="${target_theme_dir}/theme.txt"

    local bg_src
    bg_src="$(resolve_background_source)"

    printf '\n=== Planned Installation Summary ===\n'
    printf '  Target Theme Dir : %s\n' "${target_theme_dir}"
    printf '  GRUB Defaults    : %s (setting GRUB_THEME="%s")\n' "${GRUB_DEFAULT_FILE}" "${logical_theme_txt}"
    printf '  Active grub.cfg  : %s\n' "${GRUB_CFG_PATH}"
    printf '  Background Asset : %s\n' "${bg_src}"
    printf '  Preserved Entries: %d discovered OS entries\n' "${#DISCOVERED_GRUB_ENTRIES[@]}"

    confirm_action "Proceed with installing the INFERNAL GRUB theme?"

    # Step 6: Back up existing files before touching anything
    create_backup "${GRUB_DEFAULT_FILE}" "${GRUB_CFG_PATH}"
    ROLLBACK_ARMED="true"

    # Step 7: Install theme assets into dedicated directory (clean any stale files in infernal dir first)
    if [[ -d "${target_theme_dir}" && "${target_theme_dir}" == */themes/infernal ]]; then
        rm -rf "${target_theme_dir}"
    fi
    mkdir -p "${target_theme_dir}"
    INSTALLED_THEME_DIR="${target_theme_dir}"
    cp -r "${SCRIPT_DIR}/theme/"* "${target_theme_dir}/"
    if [[ "${bg_src}" != "${SCRIPT_DIR}/theme/backgrounds/infernal.png" ]]; then
        cp "${bg_src}" "${target_theme_dir}/backgrounds/infernal.png"
        cp "${bg_src}" "${target_theme_dir}/background.png"
    fi

    # Optional test hook to simulate mid-installation interruption and verify rollback
    if [[ "${INFERNAL_SIMULATE_INTERRUPT:-0}" == "1" ]]; then
        printf '[ERROR] Simulated interruption triggered (INFERNAL_SIMULATE_INTERRUPT=1).\n' >&2
        return 1
    fi

    # Validate installed theme directory
    validate_theme_dir "${target_theme_dir}"

    # Step 8: Apply minimum idempotent change to /etc/default/grub
    local tmp_default
    tmp_default="$(mktemp)"
    TEMP_FILES+=("${tmp_default}")
    build_updated_grub_default "${GRUB_DEFAULT_FILE}" "${logical_theme_txt}" "${tmp_default}"
    cp "${tmp_default}" "${GRUB_DEFAULT_FILE}"

    # Step 9: Regenerate grub.cfg using distribution-specific tool
    local tmp_cfg
    tmp_cfg="$(mktemp)"
    TEMP_FILES+=("${tmp_cfg}")
    "${GRUB_MKCONFIG_BIN}" -o "${tmp_cfg}"

    # Step 10: Validate generated configuration before overwriting active grub.cfg
    validate_grub_cfg "${tmp_cfg}"
    cp "${tmp_cfg}" "${GRUB_CFG_PATH}"

    ROLLBACK_ARMED="false"
    printf '\n[SUCCESS] INFERNAL Type C GRUB theme installed and validated!\n'
    printf '  - Installed Theme : %s\n' "${target_theme_dir}"
    printf '  - Backup Snapshot : %s\n' "${LAST_CREATED_BACKUP:-$(get_backup_base_dir)}"
    printf '  - To Rollback     : sudo ./uninstall.sh (or sudo ./install.sh --uninstall)\n'
    return 0
}

run_uninstall_mode() {
    run_bootloader_detection

    if [[ -z "${GRUB_THEMES_DIR}" || ! -f "${GRUB_DEFAULT_FILE}" ]]; then
        printf '[ERROR] Could not locate GRUB configuration to uninstall from.\n' >&2
        return 1
    fi

    if ! check_privileges_and_writable; then
        return 1
    fi

    local target_theme_dir="${GRUB_THEMES_DIR}/infernal"
    confirm_action "Remove INFERNAL theme (${target_theme_dir}) and restore previous GRUB configuration?"

    # Strictly remove only the infernal theme directory
    if [[ -d "${target_theme_dir}" && "${target_theme_dir}" == */themes/infernal ]]; then
        rm -rf "${target_theme_dir}"
        printf '[OK] Removed theme directory: %s\n' "${target_theme_dir}"
    else
        printf '[INFO] Theme directory not present at %s (already removed).\n' "${target_theme_dir}"
    fi

    # Restore pre-INFERNAL baseline /etc/default/grub if backup exists; otherwise strip GRUB_THEME line
    if ! restore_backup "baseline" "false" 2>/dev/null; then
        local tmp_default
        tmp_default="$(mktemp)"
        TEMP_FILES+=("${tmp_default}")
        build_uninstalled_grub_default "${GRUB_DEFAULT_FILE}" "${tmp_default}"
        cp "${tmp_default}" "${GRUB_DEFAULT_FILE}"
        printf '[OK] Removed INFERNAL GRUB_THEME assignment from %s\n' "${GRUB_DEFAULT_FILE}"
    fi

    # Regenerate and validate grub.cfg
    if [[ -n "${GRUB_MKCONFIG_BIN}" && -n "${GRUB_CFG_PATH}" ]]; then
        local tmp_cfg
        tmp_cfg="$(mktemp)"
        TEMP_FILES+=("${tmp_cfg}")
        "${GRUB_MKCONFIG_BIN}" -o "${tmp_cfg}"
        validate_grub_cfg "${tmp_cfg}"
        cp "${tmp_cfg}" "${GRUB_CFG_PATH}"
    fi

    printf '[SUCCESS] INFERNAL theme uninstalled and previous GRUB configuration restored.\n'
    return 0
}

main() {
    local orig_args=("$@")
    parse_args "$@"
    if [[ "${INFERNAL_ROOT}" == "/" && "${EUID}" -ne 0 && ( "${MODE}" == "--install" || "${MODE}" == "--uninstall" ) ]]; then
        if [[ -t 0 ]]; then
            exec sudo "$0" "${orig_args[@]}"
        elif [[ -x "/usr/bin/lxqt-openssh-askpass" && -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
            SUDO_ASKPASS="/usr/bin/lxqt-openssh-askpass" exec sudo -A "$0" "${orig_args[@]}"
        fi
    fi
    case "${MODE}" in
        --check)     run_check_mode ;;
        --dry-run)   run_dry_run_mode ;;
        --install)   run_install_mode ;;
        --uninstall) run_uninstall_mode ;;
    esac
}

main "$@"

