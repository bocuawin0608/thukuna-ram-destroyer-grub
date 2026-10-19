#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Bootloader & Universal OS Detection Module (scripts/detect-bootloaders.sh)
# ==============================================================================
# Capability-based inspection of firmware mode (UEFI/BIOS), Secure Boot,
# active bootloader (GRUB vs systemd-boot / rEFInd), GRUB configuration paths,
# and existing Linux / Windows / custom / firmware boot entries.
# Never mounts partitions read-write or alters existing boot entries.
# ==============================================================================

set -euo pipefail

DETECT_BOOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/detect-system.sh
source "${DETECT_BOOT_DIR}/detect-system.sh"

detect_firmware_mode() {
    BOOT_MODE="bios"
    SECURE_BOOT_STATE="unknown"

    local efi_dir
    efi_dir="$(sys_path "/sys/firmware/efi")"
    if [[ -d "${efi_dir}" ]]; then
        BOOT_MODE="uefi"
        # Check SecureBoot efivar if readable (5th byte == 1 means enabled)
        local sb_var
        for sb_var in "${efi_dir}/efivars"/SecureBoot-*; do
            if [[ -r "${sb_var}" ]]; then
                local val
                val="$(od -An -t u1 -j 4 -N 1 "${sb_var}" 2>/dev/null | tr -d ' ' || true)"
                if [[ "${val}" == "1" ]]; then
                    SECURE_BOOT_STATE="enabled"
                elif [[ "${val}" == "0" ]]; then
                    SECURE_BOOT_STATE="disabled"
                fi
                break
            fi
        done

        if [[ "${SECURE_BOOT_STATE}" == "unknown" ]] && find_cmd mokutil >/dev/null; then
            local mok_out
            mok_out="$("$(find_cmd mokutil)" --sb-state 2>/dev/null || true)"
            if [[ "${mok_out}" == *"SecureBoot enabled"* ]]; then
                SECURE_BOOT_STATE="enabled"
            elif [[ "${mok_out}" == *"SecureBoot disabled"* ]]; then
                SECURE_BOOT_STATE="disabled"
            fi
        fi
    else
        SECURE_BOOT_STATE="not-applicable (legacy BIOS)"
    fi
}

detect_grub_paths() {
    GRUB_DEFAULT_FILE="$(sys_path "/etc/default/grub")"
    GRUB_CUSTOM_40="$(sys_path "/etc/grub.d/40_custom")"
    GRUB_CFG_PATH=""
    GRUB_DIR_PATH=""
    GRUB_THEMES_DIR=""

    local candidate
    for candidate in \
        "/boot/grub/grub.cfg" \
        "/boot/grub2/grub.cfg" \
        "/boot/efi/EFI/fedora/grub.cfg" \
        "/boot/efi/EFI/ubuntu/grub.cfg" \
        "/boot/efi/EFI/debian/grub.cfg" \
        "/boot/efi/EFI/arch/grub.cfg" \
        "/boot/efi/EFI/endeavouros/grub.cfg"; do
        local full_p
        full_p="$(sys_path "${candidate}")"
        if [[ -f "${full_p}" ]]; then
            GRUB_CFG_PATH="${full_p}"
            GRUB_DIR_PATH="$(dirname "${full_p}")"
            break
        fi
    done

    # If grub.cfg doesn't exist yet, check /boot/grub or /boot/grub2 directories
    if [[ -z "${GRUB_DIR_PATH}" ]]; then
        if [[ -d "$(sys_path "/boot/grub")" ]]; then
            GRUB_DIR_PATH="$(sys_path "/boot/grub")"
            GRUB_CFG_PATH="${GRUB_DIR_PATH}/grub.cfg"
        elif [[ -d "$(sys_path "/boot/grub2")" ]]; then
            GRUB_DIR_PATH="$(sys_path "/boot/grub2")"
            GRUB_CFG_PATH="${GRUB_DIR_PATH}/grub.cfg"
        fi
    fi

    if [[ -n "${GRUB_DIR_PATH}" ]]; then
        GRUB_THEMES_DIR="${GRUB_DIR_PATH}/themes"
    fi
}

detect_active_bootloader() {
    ACTIVE_BOOTLOADER="unknown"
    ALTERNATIVE_BOOTLOADERS=()

    local sd_boot_conf1 sd_boot_conf2 refind_conf1 refind_conf2
    sd_boot_conf1="$(sys_path "/boot/loader/loader.conf")"
    sd_boot_conf2="$(sys_path "/efi/loader/loader.conf")"
    refind_conf1="$(sys_path "/boot/efi/EFI/refind/refind.conf")"
    refind_conf2="$(sys_path "/boot/refind_linux.conf")"

    if [[ -f "${sd_boot_conf1}" || -f "${sd_boot_conf2}" ]]; then
        ALTERNATIVE_BOOTLOADERS+=("systemd-boot")
    fi
    if [[ -f "${refind_conf1}" || -f "${refind_conf2}" ]]; then
        ALTERNATIVE_BOOTLOADERS+=("rEFInd")
    fi

    if [[ -f "${GRUB_DEFAULT_FILE}" && -n "${GRUB_CFG_PATH}" && -f "${GRUB_CFG_PATH}" ]]; then
        ACTIVE_BOOTLOADER="grub"
    elif [[ ${#ALTERNATIVE_BOOTLOADERS[@]} -gt 0 && ! -f "${GRUB_CFG_PATH}" ]]; then
        ACTIVE_BOOTLOADER="${ALTERNATIVE_BOOTLOADERS[0]}"
    elif [[ -f "${GRUB_DEFAULT_FILE}" && -n "${GRUB_DIR_PATH}" ]]; then
        ACTIVE_BOOTLOADER="grub"
    fi
}

detect_os_entries() {
    DISCOVERED_GRUB_ENTRIES=()
    DISCOVERED_CUSTOM_ENTRIES=()
    DISCOVERED_EFI_ENTRIES=()
    OS_PROBER_POLICY="unknown"
    CURRENT_GRUB_DEFAULT="0"
    CURRENT_GRUB_TIMEOUT="5"
    CURRENT_GRUB_THEME=""
    CURRENT_GRUB_TERMINAL_OUTPUT=""

    # 1. Inspect /etc/default/grub without sourcing untrusted shell code
    if [[ -r "${GRUB_DEFAULT_FILE}" ]]; then
        while IFS= read -r line; do
            [[ "${line}" =~ ^[[:space:]]*# ]] && continue
            if [[ "${line}" =~ ^[[:space:]]*GRUB_DEFAULT=(.*)$ ]]; then
                CURRENT_GRUB_DEFAULT="${BASH_REMATCH[1]}"
                CURRENT_GRUB_DEFAULT="${CURRENT_GRUB_DEFAULT#\"}"
                CURRENT_GRUB_DEFAULT="${CURRENT_GRUB_DEFAULT%\"}"
            elif [[ "${line}" =~ ^[[:space:]]*GRUB_TIMEOUT=(.*)$ ]]; then
                CURRENT_GRUB_TIMEOUT="${BASH_REMATCH[1]}"
                CURRENT_GRUB_TIMEOUT="${CURRENT_GRUB_TIMEOUT#\"}"
                CURRENT_GRUB_TIMEOUT="${CURRENT_GRUB_TIMEOUT%\"}"
            elif [[ "${line}" =~ ^[[:space:]]*GRUB_THEME=(.*)$ ]]; then
                CURRENT_GRUB_THEME="${BASH_REMATCH[1]}"
                CURRENT_GRUB_THEME="${CURRENT_GRUB_THEME#\"}"
                CURRENT_GRUB_THEME="${CURRENT_GRUB_THEME%\"}"
            elif [[ "${line}" =~ ^[[:space:]]*GRUB_DISABLE_OS_PROBER=(.*)$ ]]; then
                local val="${BASH_REMATCH[1]}"
                val="${val#\"}"
                val="${val%\"}"
                val="${val#\'}"
                val="${val%\'}"
                if [[ "${val}" == "false" ]]; then
                    OS_PROBER_POLICY="enabled (GRUB_DISABLE_OS_PROBER=false)"
                elif [[ "${val}" == "true" ]]; then
                    OS_PROBER_POLICY="disabled (GRUB_DISABLE_OS_PROBER=true)"
                fi
            elif [[ "${line}" =~ ^[[:space:]]*GRUB_TERMINAL_OUTPUT=(.*)$ ]]; then
                CURRENT_GRUB_TERMINAL_OUTPUT="${BASH_REMATCH[1]}"
            elif [[ "${line}" =~ ^[[:space:]]*GRUB_TERMINAL=(.*)$ ]]; then
                CURRENT_GRUB_TERMINAL_OUTPUT="${BASH_REMATCH[1]}"
            fi
        done < "${GRUB_DEFAULT_FILE}"
    fi

    # 2. Parse existing menuentry titles from active grub.cfg
    GRUB_CFG_READABLE="false"
    if [[ -n "${GRUB_CFG_PATH}" && -r "${GRUB_CFG_PATH}" ]]; then
        GRUB_CFG_READABLE="true"
        while IFS= read -r line; do
            if [[ "${line}" =~ ^[[:space:]]*menuentry[[:space:]]+[\'\"]([^\'\"]+)[\'\"] ]]; then
                DISCOVERED_GRUB_ENTRIES+=("${BASH_REMATCH[1]}")
            fi
        done < "${GRUB_CFG_PATH}"
    fi

    # 3. Parse custom entries in /etc/grub.d/40_custom and custom.cfg
    local custom_f
    for custom_f in "${GRUB_CUSTOM_40}" "${GRUB_DIR_PATH:+${GRUB_DIR_PATH}/custom.cfg}"; do
        if [[ -n "${custom_f}" && -r "${custom_f}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ ^[[:space:]]*menuentry[[:space:]]+[\'\"]([^\'\"]+)[\'\"] ]]; then
                    DISCOVERED_CUSTOM_ENTRIES+=("${BASH_REMATCH[1]}")
                fi
            done < "${custom_f}"
        fi
    done

    # 4. Check accessible EFI System Partition directories (read-only inspection)
    local esp_base
    for esp_base in "/boot/efi/EFI" "/efi/EFI" "/boot/EFI"; do
        local full_esp
        full_esp="$(sys_path "${esp_base}")"
        if [[ -d "${full_esp}" && -r "${full_esp}" ]]; then
            if [[ -f "${full_esp}/Microsoft/Boot/bootmgfw.efi" ]]; then
                DISCOVERED_EFI_ENTRIES+=("Windows Boot Manager (${esp_base}/Microsoft/Boot/bootmgfw.efi)")
            fi
            local vendor_dir
            for vendor_dir in "${full_esp}"/*; do
                [[ -d "${vendor_dir}" ]] || continue
                local vname
                vname="$(basename "${vendor_dir}")"
                case "${vname,,}" in
                    boot|microsoft) continue ;;
                    *)
                        DISCOVERED_EFI_ENTRIES+=("EFI Vendor Entry: ${vname} (${esp_base}/${vname})")
                        ;;
                esac
            done
        fi
    done

    # 5. Also inspect efibootmgr if running on host or mock efibootmgr is provided
    if [[ "${BOOT_MODE}" == "uefi" ]] && find_cmd efibootmgr >/dev/null; then
        local efi_out
        efi_out="$("$(find_cmd efibootmgr)" 2>/dev/null || true)"
        if [[ -n "${efi_out}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ ^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+(.+)$ ]]; then
                    local entry_desc="${BASH_REMATCH[1]}"
                    entry_desc="${entry_desc%%	*}"
                    DISCOVERED_EFI_ENTRIES+=("NVRAM: ${entry_desc}")
                fi
            done <<< "${efi_out}"
        fi
    fi
}

run_bootloader_detection() {
    run_system_detection
    detect_firmware_mode
    detect_grub_paths
    detect_active_bootloader
    detect_os_entries
}

print_bootloader_report() {
    run_bootloader_detection
    printf '=== Bootloader & OS Discovery Report ===\n'
    printf 'Firmware Mode       : %s\n' "${BOOT_MODE}"
    printf 'Secure Boot State   : %s\n' "${SECURE_BOOT_STATE}"
    printf 'Active Bootloader   : %s\n' "${ACTIVE_BOOTLOADER}"
    printf 'Alt Bootloaders     : %s\n' "${ALTERNATIVE_BOOTLOADERS[*]:-none}"
    printf 'GRUB Defaults File  : %s\n' "${GRUB_DEFAULT_FILE}"
    printf 'Active grub.cfg     : %s\n' "${GRUB_CFG_PATH:-not-found}"
    printf 'Themes Directory    : %s\n' "${GRUB_THEMES_DIR:-not-found}"
    printf 'GRUB Default Entry  : %s\n' "${CURRENT_GRUB_DEFAULT}"
    printf 'GRUB Timeout        : %s\n' "${CURRENT_GRUB_TIMEOUT}"
    printf 'Current GRUB Theme  : %s\n' "${CURRENT_GRUB_THEME:-none}"
    printf 'os-prober Policy    : %s\n' "${OS_PROBER_POLICY}"
    if [[ "${GRUB_CFG_READABLE:-false}" == "true" ]]; then
        printf 'Discovered Entries  : %d in grub.cfg\n' "${#DISCOVERED_GRUB_ENTRIES[@]}"
    elif [[ -n "${GRUB_CFG_PATH}" && -f "${GRUB_CFG_PATH}" ]]; then
        printf 'Discovered Entries  : grub.cfg present (mode 0600; run with sudo to list internal menuentries)\n'
    else
        printf 'Discovered Entries  : 0 in grub.cfg\n'
    fi
    local e
    for e in "${DISCOVERED_GRUB_ENTRIES[@]}"; do
        printf '  - [grub.cfg] %s\n' "${e}"
    done
    for e in "${DISCOVERED_CUSTOM_ENTRIES[@]}"; do
        printf '  - [custom]   %s\n' "${e}"
    done
    for e in "${DISCOVERED_EFI_ENTRIES[@]}"; do
        printf '  - [efi]      %s\n' "${e}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    print_bootloader_report
fi
