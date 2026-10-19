#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Backup & Atomic Rollback Module (scripts/backup-restore.sh)
# ==============================================================================
# Creates checksummed backups of /etc/default/grub and active grub.cfg before
# any modification, tracks the pre-INFERNAL baseline across idempotent runs,
# and supports atomic rollback on error or uninstallation.
# ==============================================================================

set -euo pipefail

BACKUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/detect-system.sh
source "${BACKUP_SCRIPT_DIR}/detect-system.sh"

get_backup_base_dir() {
    if [[ -n "${INFERNAL_BACKUP_DIR:-}" ]]; then
        printf '%s\n' "${INFERNAL_BACKUP_DIR}"
    else
        sys_path "/var/backups/infernal-grub-theme"
        printf '\n'
    fi
}

create_backup() {
    local grub_default="$1"
    local grub_cfg="${2:-}"
    local base_dir
    base_dir="$(get_backup_base_dir)"

    mkdir -p "${base_dir}"
    chmod 700 "${base_dir}" 2>/dev/null || true

    local ts
    ts="$(date -u +%Y%m%d-%H%M%S)-$$"
    local snap_dir="${base_dir}/backup-${ts}"
    mkdir -p "${snap_dir}"

    if [[ -f "${grub_default}" ]]; then
        cp -p "${grub_default}" "${snap_dir}/etc_default_grub.bak"
        sha256sum "${snap_dir}/etc_default_grub.bak" > "${snap_dir}/etc_default_grub.sha256"
    fi

    if [[ -n "${grub_cfg}" && -f "${grub_cfg}" ]]; then
        cp -p "${grub_cfg}" "${snap_dir}/grub.cfg.bak"
        sha256sum "${snap_dir}/grub.cfg.bak" > "${snap_dir}/grub.cfg.sha256"
    fi

    cat > "${snap_dir}/metadata.env" <<EOF
BACKUP_TIMESTAMP="${ts}"
ORIG_GRUB_DEFAULT="${grub_default}"
ORIG_GRUB_CFG="${grub_cfg}"
EOF

    printf '%s\n' "${snap_dir}" > "${base_dir}/latest_backup.txt"

    # Preserve the pre-INFERNAL baseline snapshot if not already recorded
    if [[ ! -f "${base_dir}/baseline_backup.txt" ]]; then
        printf '%s\n' "${snap_dir}" > "${base_dir}/baseline_backup.txt"
    else
        local base_snap
        base_snap="$(cat "${base_dir}/baseline_backup.txt" 2>/dev/null || true)"
        if [[ -z "${base_snap}" || ! -d "${base_snap}" ]]; then
            printf '%s\n' "${snap_dir}" > "${base_dir}/baseline_backup.txt"
        fi
    fi

    LAST_CREATED_BACKUP="${snap_dir}"
    printf '[OK] Created configuration backup at %s\n' "${snap_dir}"
}

restore_backup() {
    local mode="${1:-latest}" # "latest" (for error rollback) or "baseline" (for uninstall) or explicit dir
    local restore_cfg="${2:-true}"
    local base_dir
    base_dir="$(get_backup_base_dir)"

    local snap_dir=""
    if [[ "${mode}" == "latest" && -f "${base_dir}/latest_backup.txt" ]]; then
        snap_dir="$(cat "${base_dir}/latest_backup.txt")"
    elif [[ "${mode}" == "baseline" && -f "${base_dir}/baseline_backup.txt" ]]; then
        snap_dir="$(cat "${base_dir}/baseline_backup.txt")"
    elif [[ -d "${mode}" ]]; then
        snap_dir="${mode}"
    fi

    if [[ -z "${snap_dir}" || ! -d "${snap_dir}" ]]; then
        printf '[WARN] No backup snapshot found for mode "%s" in %s\n' "${mode}" "${base_dir}" >&2
        return 1
    fi

    local orig_default=""
    local orig_cfg=""
    if [[ -r "${snap_dir}/metadata.env" ]]; then
        while IFS='=' read -r key val; do
            val="${val#\"}"
            val="${val%\"}"
            case "${key}" in
                ORIG_GRUB_DEFAULT) orig_default="${val}" ;;
                ORIG_GRUB_CFG) orig_cfg="${val}" ;;
            esac
        done < "${snap_dir}/metadata.env"
    fi

    if [[ -f "${snap_dir}/etc_default_grub.bak" && -n "${orig_default}" ]]; then
        if [[ -f "${snap_dir}/etc_default_grub.sha256" ]]; then
            if ! sha256sum -c "${snap_dir}/etc_default_grub.sha256" >/dev/null 2>&1; then
                printf '[ERROR] Backup checksum verification failed for %s/etc_default_grub.bak\n' "${snap_dir}" >&2
                return 1
            fi
        fi
        cp -p "${snap_dir}/etc_default_grub.bak" "${orig_default}"
        printf '[OK] Restored %s from %s\n' "${orig_default}" "${snap_dir}"
    fi

    if [[ "${restore_cfg}" == "true" && -f "${snap_dir}/grub.cfg.bak" && -n "${orig_cfg}" ]]; then
        if [[ -f "${snap_dir}/grub.cfg.bak" ]]; then
            if [[ -f "${snap_dir}/grub.cfg.sha256" ]]; then
                if ! sha256sum -c "${snap_dir}/grub.cfg.sha256" >/dev/null 2>&1; then
                    printf '[ERROR] Backup checksum verification failed for %s/grub.cfg.bak\n' "${snap_dir}" >&2
                    return 1
                fi
            fi
            cp -p "${snap_dir}/grub.cfg.bak" "${orig_cfg}"
            printf '[OK] Restored %s from %s\n' "${orig_cfg}" "${snap_dir}"
        fi
    fi

    return 0
}
