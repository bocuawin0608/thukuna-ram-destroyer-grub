#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Theme & GRUB Config Validator (scripts/validate-theme.sh)
# ==============================================================================
# Validates theme.txt syntax, 9-slice pixmap completeness, PNG headers,
# background size limits, PF2 font magic headers & embedded font names,
# and generated grub.cfg syntax via grub-script-check.
# ==============================================================================

set -euo pipefail

VALIDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${VALIDATE_SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/detect-system.sh
source "${VALIDATE_SCRIPT_DIR}/detect-system.sh"

MAX_BG_BYTES=$((8 * 1024 * 1024)) # 8 MiB limit for fast bootloader rendering

check_png_magic() {
    local file="$1"
    [[ -f "${file}" && -s "${file}" ]] || return 1
    local magic
    magic="$(od -An -tx1 -N4 "${file}" 2>/dev/null | tr -d ' \n' || true)"
    [[ "${magic}" == "89504e47" ]]
}

check_pf2_magic() {
    local file="$1"
    [[ -f "${file}" && -s "${file}" ]] || return 1
    local magic
    magic="$(od -An -tx1 -N12 "${file}" 2>/dev/null | tr -d ' \n' || true)"
    # "FILE" (46494c45) + 4-byte length + "PFF2" (50464632)
    [[ "${magic}" =~ ^46494c45[0-9a-f]{8}50464632$ ]]
}

extract_pf2_name() {
    local file="$1"
    head -c 160 "${file}" | tr -d '\000' | sed -n 's/.*NAME....\([A-Za-z0-9 _-]*\).*/\1/p' | head -n 1
}

validate_theme_dir() {
    local theme_dir="${1:-${PROJECT_ROOT}/theme}"
    local theme_txt="${theme_dir}/theme.txt"
    local errors=0

    if [[ ! -f "${theme_txt}" ]]; then
        printf '[ERROR] Missing theme configuration: %s\n' "${theme_txt}" >&2
        return 1
    fi

    # 1. Check brace balance in theme.txt
    local open_braces close_braces
    open_braces="$(grep -o '{' "${theme_txt}" | wc -l | tr -d ' ' || true)"
    close_braces="$(grep -o '}' "${theme_txt}" | wc -l | tr -d ' ' || true)"
    if [[ "${open_braces}" -ne "${close_braces}" || "${open_braces}" -eq 0 ]]; then
        printf '[ERROR] Unbalanced or missing component blocks in %s (open=%s, close=%s)\n' \
            "${theme_txt}" "${open_braces}" "${close_braces}" >&2
        errors=$((errors + 1))
    fi

    # 2. Check required boot_menu component
    if ! grep -Eq '^\+[[:space:]]*boot_menu[[:space:]]*\{' "${theme_txt}"; then
        printf '[ERROR] Missing required + boot_menu block in %s\n' "${theme_txt}" >&2
        errors=$((errors + 1))
    fi

    # 3. Validate desktop-image and fallback background
    local desktop_img
    desktop_img="$(sed -n 's/^[[:space:]]*desktop-image:[[:space:]]*"\([^"]*\)".*/\1/p' "${theme_txt}" | head -n 1)"
    if [[ -z "${desktop_img}" ]]; then
        printf '[ERROR] Missing desktop-image property in %s\n' "${theme_txt}" >&2
        errors=$((errors + 1))
    else
        local bg_path="${theme_dir}/${desktop_img}"
        if ! check_png_magic "${bg_path}"; then
            printf '[ERROR] Invalid or missing desktop-image PNG: %s\n' "${bg_path}" >&2
            errors=$((errors + 1))
        else
            local bg_size
            bg_size="$(wc -c < "${bg_path}" | tr -d ' ')"
            if (( bg_size > MAX_BG_BYTES )); then
                printf '[ERROR] Background %s exceeds %d bytes (%d bytes)\n' \
                    "${bg_path}" "${MAX_BG_BYTES}" "${bg_size}" >&2
                errors=$((errors + 1))
            fi
        fi
    fi

    if ! check_png_magic "${theme_dir}/backgrounds/fallback.png"; then
        printf '[ERROR] Missing or invalid fallback background: %s/backgrounds/fallback.png\n' "${theme_dir}" >&2
        errors=$((errors + 1))
    fi

    # 4. Validate static image references (file = "...")
    while IFS= read -r rel_img; do
        [[ -z "${rel_img}" ]] && continue
        if ! check_png_magic "${theme_dir}/${rel_img}"; then
            printf '[ERROR] Missing or invalid image asset: %s/%s\n' "${theme_dir}" "${rel_img}" >&2
            errors=$((errors + 1))
        fi
    done < <(sed -n 's/^[[:space:]]*file[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${theme_txt}")

    # 5. Validate 9-slice pixmap styles (*_*.png)
    while IFS= read -r wildcard_rel; do
        [[ -z "${wildcard_rel}" ]] && continue
        local prefix="${wildcard_rel%\*.png}"
        local slice
        for slice in nw n ne w c e sw s se; do
            local slice_path="${theme_dir}/${prefix}${slice}.png"
            if ! check_png_magic "${slice_path}"; then
                printf '[ERROR] Missing or invalid 9-slice asset: %s\n' "${slice_path}" >&2
                errors=$((errors + 1))
            fi
        done
    done < <(sed -n 's/^[[:space:]]*[a-z_]*style[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p; s/^[[:space:]]*scrollbar_frame[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p; s/^[[:space:]]*scrollbar_thumb[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${theme_txt}")

    # 6. Validate .pf2 fonts in theme/fonts/
    local pf2_count=0
    local available_fonts=()
    local pf2_file
    for pf2_file in "${theme_dir}/fonts"/*.pf2; do
        [[ -e "${pf2_file}" ]] || continue
        if ! check_pf2_magic "${pf2_file}"; then
            printf '[ERROR] Invalid PF2 font header: %s\n' "${pf2_file}" >&2
            errors=$((errors + 1))
        else
            pf2_count=$((pf2_count + 1))
            local fname
            fname="$(extract_pf2_name "${pf2_file}")"
            [[ -n "${fname}" ]] && available_fonts+=("${fname}")
        fi
    done

    if (( pf2_count == 0 )); then
        printf '[ERROR] No valid .pf2 font files found in %s/fonts\n' "${theme_dir}" >&2
        errors=$((errors + 1))
    fi

    # 7. Validate required OS icons
    local req_icon
    for req_icon in endeavouros arch windows linux gnu-linux ubuntu debian fedora opensuse recovery uefi; do
        if ! check_png_magic "${theme_dir}/icons/${req_icon}.png"; then
            printf '[ERROR] Missing or invalid icon: %s/icons/%s.png\n' "${theme_dir}" "${req_icon}.png" >&2
            errors=$((errors + 1))
        fi
    done

    if (( errors > 0 )); then
        printf '[FAIL] Theme validation failed with %d error(s).\n' "${errors}" >&2
        return 1
    fi

    printf '[OK] Theme directory validated successfully (%s, %d PF2 fonts).\n' "${theme_dir}" "${pf2_count}"
    return 0
}

validate_grub_cfg() {
    local cfg_file="$1"
    if [[ ! -f "${cfg_file}" || ! -s "${cfg_file}" ]]; then
        printf '[ERROR] Generated GRUB configuration is missing or empty: %s\n' "${cfg_file}" >&2
        return 1
    fi

    run_system_detection
    if [[ -n "${GRUB_SCRIPT_CHECK_BIN}" ]]; then
        if ! "${GRUB_SCRIPT_CHECK_BIN}" "${cfg_file}"; then
            printf '[ERROR] grub-script-check reported syntax errors in %s\n' "${cfg_file}" >&2
            return 1
        fi
    fi

    printf '[OK] GRUB configuration syntax validated (%s).\n' "${cfg_file}"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    target="${1:-${PROJECT_ROOT}/theme}"
    if [[ -d "${target}" ]]; then
        validate_theme_dir "${target}"
    elif [[ -f "${target}" ]]; then
        validate_grub_cfg "${target}"
    else
        printf 'Usage: %s [theme-dir | grub.cfg]\n' "$0" >&2
        exit 1
    fi
fi
