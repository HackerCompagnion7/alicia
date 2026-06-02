#!/bin/bash
# ============================================================================
# backup.sh - Alicia Desktop Environment Backup and Restore Script
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      3.1.0
# Description:  Comprehensive backup and restore script for the Alicia
#               Desktop Environment. Supports full and selective backups,
#               encrypted backups, remote storage, scheduling, verification,
#               and automatic cleanup of old backups.
# Usage:        backup.sh [COMMAND] [OPTIONS]
# ============================================================================

set -euo pipefail

# ============================================================================
# Script Directory Resolution
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
ALICIA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================================================
# Source Alicia Libraries
# ============================================================================
for lib_file in "${LIB_DIR}"/alicia-*.sh; do
    if [[ -f "${lib_file}" ]]; then
        # shellcheck source=/dev/null
        source "${lib_file}" 2>/dev/null || {
            echo "ERROR: Failed to source library: ${lib_file}" >&2
            exit 1
        }
    fi
done

if ! declare -f alicia_init_directories &>/dev/null; then
    echo "ERROR: Failed to load alicia core libraries" >&2
    exit 1
fi

# ============================================================================
# Initialize
# ============================================================================
alicia_init_directories || true
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/backup.log" 2>/dev/null || true
log_set_module "backup"

# ============================================================================
# Variables
# ============================================================================
COMMAND=""
BACKUP_TYPE="full"         # full, config, data, selective
ENCRYPT=false
REMOTE_PUSH=false
REMOTE_DEST=""
KEEP_COUNT=5
BACKUP_ID=""
RESTORE_FILE=""
VERIFY_ONLY=""

# Compression: try zstd > xz > gzip
detect_compression() {
    if command -v zstd &>/dev/null; then
        echo "zst"
    elif command -v xz &>/dev/null; then
        echo "xz"
    else
        echo "gz"
    fi
}
COMPRESSION="$(detect_compression)"

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    COMMAND="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t)
                BACKUP_TYPE="${2:-full}"
                shift 2
                ;;
            --encrypt|-e)
                ENCRYPT=true
                shift
                ;;
            --remote|-R)
                REMOTE_PUSH=true
                REMOTE_DEST="${2:-}"
                if [[ -z "${REMOTE_DEST}" ]]; then
                    log_error "--remote requires a destination (e.g., user@host:/path)"
                    exit 1
                fi
                shift 2
                ;;
            --keep|-k)
                KEEP_COUNT="${2:-5}"
                shift 2
                ;;
            --file|-f)
                RESTORE_FILE="${2:-}"
                if [[ -z "${RESTORE_FILE}" ]]; then
                    log_error "--file requires a path argument"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    echo "Usage: backup.sh COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  create              Create a new backup"
    echo "  restore             Restore from a backup"
    echo "  list                List available backups"
    echo "  verify              Verify backup integrity"
    echo "  delete              Delete old backups"
    echo "  schedule            Configure automatic backups"
    echo "  estimate            Estimate backup size"
    echo ""
    echo "Options:"
    echo "  --type,  -t TYPE    Backup type: full, config, data (default: full)"
    echo "  --encrypt, -e       Encrypt backup with GPG"
    echo "  --remote, -R DEST   Push backup to remote destination"
    echo "  --keep,  -k N       Keep last N backups when deleting (default: 5)"
    echo "  --file,  -f PATH    Backup file path (for restore/verify)"
    echo "  --help,  -h         Show this help"
    echo ""
    echo "Examples:"
    echo "  backup.sh create --type full"
    echo "  backup.sh create --type config --encrypt"
    echo "  backup.sh restore --file /path/to/backup.tar.gz"
    echo "  backup.sh list"
    echo "  backup.sh delete --keep 3"
    echo "  backup.sh verify --file /path/to/backup.tar.gz"
}

# ============================================================================
# Backup Size Estimation
# ============================================================================
estimate_backup_size() {
    log_section "Backup Size Estimate"

    local total_size=0

    # RootFS size
    local rootfs_size=0
    if [[ -d "${ALICIA_ROOTFS_DIR}" ]]; then
        rootfs_size=$(du -sm "${ALICIA_ROOTFS_DIR}" 2>/dev/null | cut -f1 || echo 0)
        printf "  %-25s %s MB\n" "RootFS:" "${rootfs_size}"
    fi

    # Config size
    local config_size=0
    if [[ -d "${ALICIA_CONFIG_DIR}" ]]; then
        config_size=$(du -sm "${ALICIA_CONFIG_DIR}" 2>/dev/null | cut -f1 || echo 0)
        printf "  %-25s %s MB\n" "Configuration:" "${config_size}"
    fi

    # State size
    local state_size=0
    if [[ -d "${ALICIA_STATE_DIR}" ]]; then
        state_size=$(du -sm "${ALICIA_STATE_DIR}" 2>/dev/null | cut -f1 || echo 0)
        printf "  %-25s %s MB\n" "State:" "${state_size}"
    fi

    # User data inside proot
    local userdata_size=0
    if proot_is_running 2>/dev/null; then
        userdata_size=$(proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
            "du -sm /home/alicia 2>/dev/null | tail -1 | cut -f1" 2>/dev/null || echo 0)
        printf "  %-25s %s MB\n" "User Data (proot):" "${userdata_size}"
    fi

    echo ""
    case "${BACKUP_TYPE}" in
        full)
            total_size=$((rootfs_size + config_size + state_size + userdata_size))
            ;;
        config)
            total_size=$((config_size + state_size))
            ;;
        data)
            total_size=$((userdata_size + config_size))
            ;;
    esac

    # Estimate compressed size (roughly 40-60% of original)
    local compressed_low=$((total_size * 40 / 100))
    local compressed_high=$((total_size * 60 / 100))

    printf "  ${COLOR_BOLD_WHITE}%-25s %s MB${COLOR_RESET}\n" "Total (uncompressed):" "${total_size}"
    printf "  %-25s ~%s-%s MB\n" "Estimated compressed:" "${compressed_low}" "${compressed_high}"
    echo ""

    # Check available space
    local avail
    avail=$(storage_get_available_space "${ALICIA_HOME}" 2>/dev/null || echo 0)
    if [[ ${avail} -lt ${compressed_high} ]]; then
        log_warn "Low disk space: ${avail}MB available, estimated ${compressed_high}MB needed"
    else
        log_info "Sufficient disk space: ${avail}MB available"
    fi
}

# ============================================================================
# Create Backup
# ============================================================================
create_backup() {
    log_section "Creating Backup (${BACKUP_TYPE})"

    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_name="alicia_${BACKUP_TYPE}_${timestamp}"

    # Check available storage
    local avail
    avail=$(storage_get_available_space "${ALICIA_HOME}" 2>/dev/null || echo 0)
    if [[ ${avail} -lt 500 ]]; then
        log_error "Insufficient storage for backup (${avail}MB available, need at least 500MB)"
        return 1
    fi

    # Determine file extension based on compression
    local ext
    case "${COMPRESSION}" in
        zst) ext="tar.zst" ;;
        xz)  ext="tar.xz" ;;
        *)   ext="tar.gz" ;;
    esac

    local backup_file="${ALICIA_BACKUP_DIR}/${backup_name}.${ext}"
    local temp_manifest="${ALICIA_TMP_DIR}/backup_manifest_${timestamp}.txt"

    log_info "Backup file: ${backup_file}"
    log_info "Compression: ${COMPRESSION}"
    log_info "Type: ${BACKUP_TYPE}"

    # Create manifest
    cat > "${temp_manifest}" <<MANIFEST
# Alicia Desktop Environment Backup Manifest
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Version: ${ALICIA_VERSION}
# Type: ${BACKUP_TYPE}
# Compression: ${COMPRESSION}
# Encrypted: ${ENCRYPT}
MANIFEST

    # Build tar command based on backup type
    local tar_args=()

    case "${BACKUP_TYPE}" in
        full)
            log_info "Creating full backup (rootfs + config + user data)..."
            tar_args=(
                -C "${ALICIA_HOME}"
                --exclude="./backups"
                --exclude="./cache"
                --exclude="./tmp"
                --exclude="./logs"
                --exclude="./locks"
                --exclude="./downloads"
                .
            )
            ;;
        config)
            log_info "Creating configuration backup..."
            tar_args=(
                -C "${ALICIA_HOME}"
                ./config
                ./state
            )
            ;;
        data)
            log_info "Creating user data backup..."
            tar_args=(
                -C "${ALICIA_HOME}"
                ./config
                ./data
            )
            # Include proot home if accessible
            if [[ -d "${ALICIA_ROOTFS_DIR}/home/alicia" ]]; then
                tar_args+=(
                    -C "${ALICIA_ROOTFS_DIR}"
                    --transform="s,^home/alicia,rootfs_home,"
                    ./home/alicia
                )
            fi
            ;;
        *)
            log_error "Unknown backup type: ${BACKUP_TYPE}"
            rm -f "${temp_manifest}"
            return 1
            ;;
    esac

    # Create the archive with progress
    log_info "Compressing backup..."

    case "${COMPRESSION}" in
        zst)
            tar -cf - "${tar_args[@]}" 2>/dev/null | zstd -3 -o "${backup_file}" 2>/dev/null || {
                log_error "Failed to create zstd backup"
                rm -f "${backup_file}" "${temp_manifest}"
                return 1
            }
            ;;
        xz)
            tar -cJf "${backup_file}" "${tar_args[@]}" 2>/dev/null || {
                log_error "Failed to create xz backup"
                rm -f "${backup_file}" "${temp_manifest}"
                return 1
            }
            ;;
        *)
            tar -czf "${backup_file}" "${tar_args[@]}" 2>/dev/null || {
                log_error "Failed to create gzip backup"
                rm -f "${backup_file}" "${temp_manifest}"
                return 1
            }
            ;;
    esac

    # Verify the backup was created
    if [[ ! -f "${backup_file}" ]]; then
        log_error "Backup file was not created"
        rm -f "${temp_manifest}"
        return 1
    fi

    local backup_size
    backup_size=$(du -h "${backup_file}" | cut -f1)

    # Compute checksum
    local checksum
    checksum=$(alicia_compute_checksum "${backup_file}" "sha256" 2>/dev/null || echo "unknown")

    # Update manifest
    echo "file=$(basename "${backup_file}")" >> "${temp_manifest}"
    echo "size=${backup_size}" >> "${temp_manifest}"
    echo "checksum=${checksum}" >> "${temp_manifest}"

    # Store manifest alongside backup
    cp "${temp_manifest}" "${ALICIA_BACKUP_DIR}/${backup_name}.manifest"
    rm -f "${temp_manifest}"

    log_info "Backup created: ${backup_file} (${backup_size})"
    log_info "Checksum: ${checksum}"

    # Encrypt if requested
    if [[ "${ENCRYPT}" == "true" ]]; then
        encrypt_backup "${backup_file}" || {
            log_error "Backup encryption failed"
            return 1
        }
    fi

    # Push to remote if requested
    if [[ "${REMOTE_PUSH}" == "true" ]]; then
        push_backup_remote "${backup_file}" || {
            log_warn "Remote push failed -- backup is still available locally"
        }
    fi

    # Log the backup
    alicia_set_state "last_backup" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    alicia_set_state "last_backup_file" "${backup_file}"
    alicia_set_state "last_backup_type" "${BACKUP_TYPE}"

    printf "\n${COLOR_BOLD_GREEN}  Backup created successfully!${COLOR_RESET}\n"
    printf "  File: %s\n" "${backup_file}"
    printf "  Size: %s\n" "${backup_size}"
    printf "  Type: %s\n" "${BACKUP_TYPE}"
    if [[ "${ENCRYPT}" == "true" ]]; then
        printf "  Encrypted: yes (GPG)\n"
    fi
    printf "\n"

    return 0
}

# ============================================================================
# Encrypt Backup
# ============================================================================
encrypt_backup() {
    local input_file="$1"

    if ! command -v gpg &>/dev/null; then
        log_error "GPG is not installed -- cannot encrypt backup"
        log_info "Install with: pkg install gnupg (Termux) or apt install gnupg"
        return 1
    fi

    log_info "Encrypting backup with GPG..."

    local encrypted_file="${input_file}.gpg"

    gpg --symmetric --cipher-algo AES256 --compress-algo none \
        --output "${encrypted_file}" "${input_file}" 2>/dev/null || {
        log_error "GPG encryption failed"
        rm -f "${encrypted_file}"
        return 1
    }

    # Remove unencrypted backup
    rm -f "${input_file}"

    local enc_size
    enc_size=$(du -h "${encrypted_file}" | cut -f1)
    log_info "Backup encrypted: ${encrypted_file} (${enc_size})"

    return 0
}

# ============================================================================
# Push Backup to Remote
# ============================================================================
push_backup_remote() {
    local backup_file="$1"

    if [[ -z "${REMOTE_DEST}" ]]; then
        log_error "No remote destination specified"
        return 1
    fi

    log_info "Pushing backup to remote: ${REMOTE_DEST}"

    # Try rsync first, then scp
    if command -v rsync &>/dev/null; then
        rsync -avz --progress "${backup_file}" "${REMOTE_DEST}/" 2>/dev/null || {
            log_warn "rsync failed, trying scp..."
            scp "${backup_file}" "${REMOTE_DEST}/" 2>/dev/null || {
                log_error "Failed to push backup to remote"
                return 1
            }
        }
    elif command -v scp &>/dev/null; then
        scp "${backup_file}" "${REMOTE_DEST}/" 2>/dev/null || {
            log_error "Failed to push backup to remote via scp"
            return 1
        }
    else
        log_error "No remote copy tool available (rsync/scp)"
        return 1
    fi

    log_info "Backup pushed to remote successfully"
    return 0
}

# ============================================================================
# Restore from Backup
# ============================================================================
restore_backup() {
    log_section "Restoring from Backup"

    local restore_file="${RESTORE_FILE}"

    # If no file specified, show available backups and ask
    if [[ -z "${restore_file}" ]]; then
        log_error "No backup file specified. Use --file /path/to/backup"
        list_backups
        return 1
    fi

    # Handle encrypted backups
    if [[ "${restore_file}" == *.gpg ]]; then
        log_info "Encrypted backup detected -- decrypting..."
        if ! command -v gpg &>/dev/null; then
            log_error "GPG is not installed -- cannot decrypt backup"
            return 1
        fi

        local decrypted_file="${restore_file%.gpg}"
        gpg --decrypt --output "${decrypted_file}" "${restore_file}" 2>/dev/null || {
            log_error "GPG decryption failed"
            return 1
        }
        restore_file="${decrypted_file}"
        log_info "Backup decrypted"
    fi

    # Verify the backup file exists
    if [[ ! -f "${restore_file}" ]]; then
        log_error "Backup file not found: ${restore_file}"
        return 1
    fi

    # Verify integrity
    log_info "Verifying backup integrity..."
    if ! backup_verify "${restore_file}" 2>/dev/null; then
        log_error "Backup integrity check failed -- aborting restore"
        return 1
    fi
    log_info "Backup integrity verified"

    # Check for manifest
    local manifest_file="${restore_file%.*}.manifest"
    local backup_type="full"
    if [[ -f "${manifest_file}" ]]; then
        backup_type=$(grep '^Type:' "${manifest_file}" 2>/dev/null | cut -d' ' -f2 || echo "full")
        log_info "Backup type from manifest: ${backup_type}"
    fi

    # Stop Alicia before restoring
    log_warn "Alicia must be stopped before restoring"
    if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
        log_info "Stopping Alicia..."
        bash "${SCRIPT_DIR}/stop.sh" --force 2>/dev/null || true
        sleep 3
    fi

    # Create a safety backup of current state
    log_info "Creating safety backup of current state..."
    local safety_backup="${ALICIA_BACKUP_DIR}/pre_restore_safety_$(date '+%Y%m%d_%H%M%S').tar.gz"
    tar -czf "${safety_backup}" \
        -C "${ALICIA_HOME}" \
        --exclude="./backups" \
        --exclude="./cache" \
        --exclude="./tmp" \
        ./config ./state 2>/dev/null || true

    log_info "Safety backup created: ${safety_backup}"

    # Extract the backup
    log_info "Restoring backup: ${restore_file}"
    local extract_dir
    extract_dir=$(mktemp -d "${ALICIA_TMP_DIR}/alicia-restore.XXXXXX")

    case "${restore_file}" in
        *.tar.zst)
            tar --zstd -xf "${restore_file}" -C "${extract_dir}" 2>/dev/null || {
                log_error "Failed to extract zstd backup"
                rm -rf "${extract_dir}"
                return 1
            }
            ;;
        *.tar.xz)
            tar -xJf "${restore_file}" -C "${extract_dir}" 2>/dev/null || {
                log_error "Failed to extract xz backup"
                rm -rf "${extract_dir}"
                return 1
            }
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "${restore_file}" -C "${extract_dir}" 2>/dev/null || {
                log_error "Failed to extract gzip backup"
                rm -rf "${extract_dir}"
                return 1
            }
            ;;
        *)
            log_error "Unknown backup format: ${restore_file}"
            rm -rf "${extract_dir}"
            return 1
            ;;
    esac

    # Restore files based on backup type
    log_info "Restoring files..."

    case "${backup_type}" in
        full)
            # Full restore -- replace everything except runtime dirs
            local src="${extract_dir}"
            for item in config state data; do
                if [[ -d "${src}/${item}" ]]; then
                    rm -rf "${ALICIA_HOME}/${item}"
                    cp -a "${src}/${item}" "${ALICIA_HOME}/${item}"
                    log_info "  Restored: ${item}/"
                fi
            done
            # Restore rootfs if present
            if [[ -d "${src}/rootfs" ]]; then
                rm -rf "${ALICIA_ROOTFS_DIR}"
                cp -a "${src}/rootfs" "${ALICIA_ROOTFS_DIR}"
                log_info "  Restored: rootfs/"
            fi
            ;;
        config)
            for item in config state; do
                if [[ -d "${extract_dir}/${item}" ]]; then
                    rm -rf "${ALICIA_HOME}/${item}"
                    cp -a "${extract_dir}/${item}" "${ALICIA_HOME}/${item}"
                    log_info "  Restored: ${item}/"
                fi
            done
            ;;
        data)
            for item in config data; do
                if [[ -d "${extract_dir}/${item}" ]]; then
                    rm -rf "${ALICIA_HOME}/${item}"
                    cp -a "${extract_dir}/${item}" "${ALICIA_HOME}/${item}"
                    log_info "  Restored: ${item}/"
                fi
            done
            ;;
    esac

    # Clean up
    rm -rf "${extract_dir}"

    # Clean up decrypted file if it was encrypted
    if [[ "${RESTORE_FILE}" == *.gpg && -f "${restore_file}" ]]; then
        rm -f "${restore_file}"
    fi

    log_info "Restore complete"

    printf "\n${COLOR_BOLD_GREEN}  Backup restored successfully!${COLOR_RESET}\n"
    printf "  Run 'start.sh' to start Alicia with the restored data.\n\n"

    return 0
}

# ============================================================================
# List Backups
# ============================================================================
list_backups() {
    log_section "Available Backups"

    if [[ ! -d "${ALICIA_BACKUP_DIR}" ]] || [[ -z "$(ls -A "${ALICIA_BACKUP_DIR}" 2>/dev/null)" ]]; then
        printf "  No backups found.\n\n"
        return 0
    fi

    printf "  %-40s %-10s %-12s %-8s %-10s\n" "FILE" "SIZE" "DATE" "TYPE" "ENCRYPTED"
    printf "  %s\n" "$(printf '%.0s-' {1..82})"

    local count=0
    local archive_files=()
    for f in "${ALICIA_BACKUP_DIR}"/alicia-*.tar.* "${ALICIA_BACKUP_DIR}"/alicia-*.tar.gz.gpg; do
        [[ -f "${f}" ]] && archive_files+=("${f}")
    done

    # Sort by modification time (newest first)
    IFS=$'\n' sorted=($(ls -t "${archive_files[@]}" 2>/dev/null)); unset IFS

    for f in "${sorted[@]}"; do
        local basename size date_str btype encrypted
        basename=$(basename "${f}")
        size=$(du -h "${f}" | cut -f1)
        date_str=$(stat -c %y "${f}" 2>/dev/null | cut -d. -f1 || echo "unknown")

        # Parse type from filename
        if [[ "${basename}" == *"_full_"* ]]; then
            btype="full"
        elif [[ "${basename}" == *"_config_"* ]]; then
            btype="config"
        elif [[ "${basename}" == *"_data_"* ]]; then
            btype="data"
        else
            btype="other"
        fi

        encrypted="no"
        [[ "${basename}" == *.gpg ]] && encrypted="yes"

        printf "  %-40s %-10s %-12s %-8s %-10s\n" "${basename}" "${size}" "${date_str:0:10}" "${btype}" "${encrypted}"
        ((count++)) || true
    done

    if [[ ${count} -eq 0 ]]; then
        printf "  No backups found.\n"
    else
        echo ""
        printf "  Total: %d backup(s)\n" "${count}"
    fi

    printf "\n"
    return 0
}

# ============================================================================
# Verify Backup
# ============================================================================
verify_backup() {
    local verify_file="${RESTORE_FILE}"

    if [[ -z "${verify_file}" ]]; then
        log_error "No backup file specified. Use --file /path/to/backup"
        return 1
    fi

    # Handle encrypted files
    if [[ "${verify_file}" == *.gpg ]]; then
        log_warn "Cannot verify encrypted backup without decrypting first"
        log_info "Use: gpg --decrypt backup.tar.gz.gpg | tar -tz"
        return 1
    fi

    log_section "Verifying Backup"

    if [[ ! -f "${verify_file}" ]]; then
        log_error "Backup file not found: ${verify_file}"
        return 1
    fi

    log_info "File: ${verify_file}"
    log_info "Size: $(du -h "${verify_file}" | cut -f1)"

    # Check manifest if available
    local manifest_file="${verify_file%.*}.manifest"
    if [[ -f "${manifest_file}" ]]; then
        log_info "Checking manifest..."
        local expected_checksum
        expected_checksum=$(grep '^checksum=' "${manifest_file}" 2>/dev/null | cut -d= -f2 || echo "")

        if [[ -n "${expected_checksum}" && "${expected_checksum}" != "unknown" ]]; then
            log_info "Verifying checksum..."
            local actual_checksum
            actual_checksum=$(alicia_compute_checksum "${verify_file}" "sha256" 2>/dev/null || echo "")

            if [[ "${actual_checksum}" == "${expected_checksum}" ]]; then
                log_info "Checksum: PASSED"
            else
                log_error "Checksum: FAILED"
                log_error "  Expected: ${expected_checksum}"
                log_error "  Actual:   ${actual_checksum}"
                return 1
            fi
        fi
    fi

    # Test archive integrity
    log_info "Testing archive integrity..."
    case "${verify_file}" in
        *.tar.zst)
            tar --zstd -tf "${verify_file}" &>/dev/null || {
                log_error "Archive integrity check FAILED"
                return 1
            }
            ;;
        *.tar.xz)
            tar -tJf "${verify_file}" &>/dev/null || {
                log_error "Archive integrity check FAILED"
                return 1
            }
            ;;
        *.tar.gz|*.tgz)
            tar -tzf "${verify_file}" &>/dev/null || {
                log_error "Archive integrity check FAILED"
                return 1
            }
            ;;
    esac

    log_info "Archive integrity: PASSED"

    # Count files in archive
    local file_count
    file_count=$(tar -tf "${verify_file}" 2>/dev/null | wc -l || echo "unknown")
    log_info "Files in archive: ${file_count}"

    printf "\n${COLOR_BOLD_GREEN}  Backup verification PASSED${COLOR_RESET}\n\n"
    return 0
}

# ============================================================================
# Delete Old Backups
# ============================================================================
delete_old_backups() {
    log_section "Cleaning Up Old Backups"

    local keep="${KEEP_COUNT}"
    log_info "Keeping last ${keep} backup(s), deleting older ones..."

    if [[ ! -d "${ALICIA_BACKUP_DIR}" ]]; then
        log_info "No backup directory found"
        return 0
    fi

    # Collect all backup archives sorted by date (newest first)
    local backups=()
    while IFS= read -r f; do
        backups+=("$f")
    done < <(ls -t "${ALICIA_BACKUP_DIR}"/alicia-*.tar.* "${ALICIA_BACKUP_DIR}"/alicia-*.tar.gz.gpg 2>/dev/null)

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "No backups found to clean up"
        return 0
    fi

    if [[ ${#backups[@]} -le ${keep} ]]; then
        log_info "Only ${#backups[@]} backup(s) found -- nothing to delete (keeping ${keep})"
        return 0
    fi

    local deleted=0
    local freed_bytes=0

    for ((i = keep; i < ${#backups[@]}; i++)); do
        local file="${backups[$i]}"
        local size
        size=$(stat -c %s "${file}" 2>/dev/null || echo 0)
        local basename
        basename=$(basename "${file}")

        log_info "  Deleting: ${basename}"
        rm -f "${file}" 2>/dev/null || {
            log_warn "  Failed to delete: ${basename}"
            continue
        }

        # Also delete associated manifest
        rm -f "${file%.*}.manifest" 2>/dev/null || true

        freed_bytes=$((freed_bytes + size))
        ((deleted++)) || true
    done

    local freed_mb=$((freed_bytes / 1024 / 1024))
    log_info "Deleted ${deleted} old backup(s), freed ${freed_mb}MB"

    return 0
}

# ============================================================================
# Schedule Automatic Backups
# ============================================================================
schedule_backup() {
    log_section "Backup Scheduling"

    if [[ ! -n "${TERMUX_VERSION:-}" ]] && ! command -v crontab &>/dev/null; then
        log_warn "Cron is not available in this environment"
        log_info "On Termux: pkg install cronie"
        log_info "Then run: sv-enable crond"
        return 1
    fi

    local schedule_interval
    echo "Configure automatic backup schedule:"
    echo "  1) Every 6 hours"
    echo "  2) Every 12 hours"
    echo "  3) Daily (midnight)"
    echo "  4) Weekly (Sunday midnight)"
    echo "  5) Disable automatic backups"
    echo ""
    read -rp "Select option [1-5]: " schedule_interval

    local cron_expr=""
    local backup_cmd="$(readlink -f "${SCRIPT_DIR}/backup.sh" 2>/dev/null || echo "${SCRIPT_DIR}/backup.sh") create --type full"

    case "${schedule_interval}" in
        1) cron_expr="0 */6 * * * ${backup_cmd} >> ${ALICIA_LOG_DIR}/backup-cron.log 2>&1" ;;
        2) cron_expr="0 */12 * * * ${backup_cmd} >> ${ALICIA_LOG_DIR}/backup-cron.log 2>&1" ;;
        3) cron_expr="0 0 * * * ${backup_cmd} >> ${ALICIA_LOG_DIR}/backup-cron.log 2>&1" ;;
        4) cron_expr="0 0 * * 0 ${backup_cmd} >> ${ALICIA_LOG_DIR}/backup-cron.log 2>&1" ;;
        5)
            log_info "Disabling automatic backups..."
            if command -v crontab &>/dev/null; then
                crontab -l 2>/dev/null | grep -v "backup.sh" | crontab - 2>/dev/null || true
            fi
            alicia_set_state "backup_schedule" "disabled"
            log_info "Automatic backups disabled"
            return 0
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac

    # Add to crontab
    if command -v crontab &>/dev/null; then
        (crontab -l 2>/dev/null | grep -v "backup.sh"; echo "${cron_expr}") | crontab - 2>/dev/null || {
            log_error "Failed to update crontab"
            return 1
        }
        log_info "Crontab updated"
    fi

    alicia_set_state "backup_schedule" "enabled"
    alicia_set_state "backup_cron" "${cron_expr}"

    log_info "Automatic backup scheduled"
    echo "  Schedule: ${cron_expr}"
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"

    case "${COMMAND}" in
        create)
            create_backup
            ;;
        restore)
            restore_backup
            ;;
        list)
            list_backups
            ;;
        verify)
            verify_backup
            ;;
        delete)
            delete_old_backups
            ;;
        schedule)
            schedule_backup
            ;;
        estimate)
            estimate_backup_size
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            show_usage
            exit 1
            ;;
    esac

    return $?
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
