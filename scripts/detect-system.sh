#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — System & Package Manager Detection Module (scripts/detect-system.sh)
# ==============================================================================
# Inspects the current Linux distribution, package manager, GRUB utilities,
# and optional dependencies. Supports INFERNAL_ROOT for isolated test fixtures.
# ==============================================================================

set -euo pipefail

INFERNAL_ROOT="${INFERNAL_ROOT:-/}"
# Normalize INFERNAL_ROOT so trailing slash is stripped unless it is "/"
if [[ "${INFERNAL_ROOT}" != "/" ]]; then
    INFERNAL_ROOT="${INFERNAL_ROOT%/}"
fi

sys_path() {
    local rel="${1#/}"
    if [[ "${INFERNAL_ROOT}" == "/" ]]; then
        printf '/%s' "${rel}"
    else
        printf '%s/%s' "${INFERNAL_ROOT}" "${rel}"
    fi
}

find_cmd() {
    local cmd_name="$1"
    if [[ -n "${INFERNAL_BIN_DIR:-}" ]]; then
        if [[ -x "${INFERNAL_BIN_DIR}/${cmd_name}" ]]; then
            printf '%s\n' "${INFERNAL_BIN_DIR}/${cmd_name}"
            return 0
        fi
        return 1
    fi
    command -v "${cmd_name}" 2>/dev/null || return 1
}

detect_distro() {
    DISTRO_ID="unknown"
    DISTRO_ID_LIKE=""
    DISTRO_NAME="Unknown Linux"
    DISTRO_VERSION=""

    local os_release
    os_release="$(sys_path "/etc/os-release")"
    if [[ -r "${os_release}" ]]; then
        while IFS='=' read -r key val; do
            [[ -z "${key}" || "${key}" =~ ^# ]] && continue
            val="${val#\"}"
            val="${val%\"}"
            val="${val#\'}"
            val="${val%\'}"
            case "${key}" in
                ID) DISTRO_ID="${val}" ;;
                ID_LIKE) DISTRO_ID_LIKE="${val}" ;;
                PRETTY_NAME) DISTRO_NAME="${val}" ;;
                VERSION_ID) DISTRO_VERSION="${val}" ;;
            esac
        done < "${os_release}"
    fi
}

detect_package_manager() {
    PKG_MANAGER="unknown"
    PKG_FAMILY="unknown"

    # Prefer matching the distribution family first when multiple tools exist
    case "${DISTRO_ID} ${DISTRO_ID_LIKE}" in
        *arch*|*endeavouros*|*manjaro*|*cachyos*|*garuda*)
            if find_cmd pacman >/dev/null; then
                PKG_MANAGER="pacman"
                PKG_FAMILY="arch"
                return 0
            fi
            ;;
        *debian*|*ubuntu*|*linuxmint*|*pop*|*kali*)
            if find_cmd apt-get >/dev/null; then
                PKG_MANAGER="apt-get"
                PKG_FAMILY="debian"
                return 0
            fi
            ;;
        *fedora*|*rhel*|*centos*|*rocky*|*almalinux*)
            if find_cmd dnf >/dev/null; then
                PKG_MANAGER="dnf"
                PKG_FAMILY="fedora"
                return 0
            fi
            ;;
        *suse*|*opensuse*)
            if find_cmd zypper >/dev/null; then
                PKG_MANAGER="zypper"
                PKG_FAMILY="suse"
                return 0
            fi
            ;;
    esac

    # Fallback capability probe
    if find_cmd pacman >/dev/null; then
        PKG_MANAGER="pacman"
        PKG_FAMILY="arch"
    elif find_cmd apt-get >/dev/null; then
        PKG_MANAGER="apt-get"
        PKG_FAMILY="debian"
    elif find_cmd dnf >/dev/null; then
        PKG_MANAGER="dnf"
        PKG_FAMILY="fedora"
    elif find_cmd zypper >/dev/null; then
        PKG_MANAGER="zypper"
        PKG_FAMILY="suse"
    fi
}

detect_grub_tools() {
    GRUB_MKCONFIG_BIN=""
    GRUB_MKFONT_BIN=""
    GRUB_SCRIPT_CHECK_BIN=""
    GRUB_VERSION_STR="unavailable"
    GRUB_VERSION_MAJOR=0
    GRUB_VERSION_MINOR=0
    GRUB_THEME_SUPPORTED="false"

    local p
    if p="$(find_cmd grub-mkconfig)"; then
        GRUB_MKCONFIG_BIN="${p}"
    elif p="$(find_cmd grub2-mkconfig)"; then
        GRUB_MKCONFIG_BIN="${p}"
    fi

    if p="$(find_cmd grub-mkfont)"; then
        GRUB_MKFONT_BIN="${p}"
    elif p="$(find_cmd grub2-mkfont)"; then
        GRUB_MKFONT_BIN="${p}"
    fi

    if p="$(find_cmd grub-script-check)"; then
        GRUB_SCRIPT_CHECK_BIN="${p}"
    elif p="$(find_cmd grub2-script-check)"; then
        GRUB_SCRIPT_CHECK_BIN="${p}"
    fi

    if [[ -n "${GRUB_MKCONFIG_BIN}" ]]; then
        local ver_out
        ver_out="$("${GRUB_MKCONFIG_BIN}" --version 2>/dev/null || true)"
        if [[ -n "${ver_out}" ]]; then
            GRUB_VERSION_STR="${ver_out}"
            if [[ "${ver_out}" =~ ([0-9]+)\.([0-9]+) ]]; then
                GRUB_VERSION_MAJOR="${BASH_REMATCH[1]}"
                GRUB_VERSION_MINOR="${BASH_REMATCH[2]}"
                if (( GRUB_VERSION_MAJOR >= 2 )); then
                    GRUB_THEME_SUPPORTED="true"
                fi
            fi
        fi
    fi
}

detect_dependencies() {
    MISSING_REQUIRED_DEPS=()
    MISSING_OPTIONAL_DEPS=()
    SATISFIED_DEPS=()

    if [[ -n "${GRUB_MKCONFIG_BIN}" ]]; then
        SATISFIED_DEPS+=("grub-mkconfig (${GRUB_MKCONFIG_BIN})")
    else
        MISSING_REQUIRED_DEPS+=("grub (grub-mkconfig / grub2-mkconfig)")
    fi

    if find_cmd os-prober >/dev/null; then
        SATISFIED_DEPS+=("os-prober")
    else
        MISSING_OPTIONAL_DEPS+=("os-prober (optional: multi-boot OS discovery)")
    fi

    if find_cmd efibootmgr >/dev/null; then
        SATISFIED_DEPS+=("efibootmgr")
    else
        MISSING_OPTIONAL_DEPS+=("efibootmgr (optional: UEFI boot entry inspection)")
    fi

    if [[ -n "${GRUB_MKFONT_BIN}" ]]; then
        SATISFIED_DEPS+=("grub-mkfont (${GRUB_MKFONT_BIN})")
    else
        MISSING_OPTIONAL_DEPS+=("grub-mkfont (optional: prebuilt .pf2 fonts are bundled)")
    fi

    if [[ -n "${GRUB_SCRIPT_CHECK_BIN}" ]]; then
        SATISFIED_DEPS+=("grub-script-check (${GRUB_SCRIPT_CHECK_BIN})")
    else
        MISSING_OPTIONAL_DEPS+=("grub-script-check (optional: config syntax verifier)")
    fi
}

get_package_install_hint() {
    case "${PKG_FAMILY}" in
        arch)
            printf 'pacman -S --needed grub os-prober efibootmgr\n'
            ;;
        debian)
            printf 'apt-get install -y grub-common grub2-common os-prober efibootmgr\n'
            ;;
        fedora)
            printf 'dnf install -y grub2-tools grub2-common os-prober efibootmgr\n'
            ;;
        suse)
            printf 'zypper install -y grub2 os-prober efibootmgr\n'
            ;;
        *)
            printf 'Install grub (2.00+) and optionally os-prober / efibootmgr via your system package manager.\n'
            ;;
    esac
}

run_system_detection() {
    detect_distro
    detect_package_manager
    detect_grub_tools
    detect_dependencies
}

print_system_report() {
    run_system_detection
    printf '=== System & Dependency Report ===\n'
    printf 'Root Prefix         : %s\n' "${INFERNAL_ROOT}"
    printf 'Distribution        : %s (ID=%s, LIKE=%s)\n' "${DISTRO_NAME}" "${DISTRO_ID}" "${DISTRO_ID_LIKE:-none}"
    printf 'Package Manager     : %s (family=%s)\n' "${PKG_MANAGER}" "${PKG_FAMILY}"
    printf 'GRUB Version        : %s\n' "${GRUB_VERSION_STR}"
    printf 'GRUB Theme Support  : %s\n' "${GRUB_THEME_SUPPORTED}"
    printf 'grub-mkconfig       : %s\n' "${GRUB_MKCONFIG_BIN:-missing}"
    printf 'grub-script-check   : %s\n' "${GRUB_SCRIPT_CHECK_BIN:-missing}"
    printf 'Satisfied Deps      : %s\n' "${SATISFIED_DEPS[*]:-none}"
    printf 'Missing Required    : %s\n' "${MISSING_REQUIRED_DEPS[*]:-none}"
    printf 'Missing Optional    : %s\n' "${MISSING_OPTIONAL_DEPS[*]:-none}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    print_system_report
fi

