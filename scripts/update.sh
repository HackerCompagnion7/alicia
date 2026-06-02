#!/bin/bash
# ============================================================================
# update.sh - Alicia Desktop Environment Update Management Script
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
# Description:  Update management script for the Alicia Desktop Environment.
#               Checks for updates on GitHub, downloads and applies them with
#               backup, rollback, and integrity verification support.
# Usage:        update.sh [--check] [--force] [--rollback]
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
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/update.log" 2>/dev/null || true
log_set_module "update"

# ============================================================================
# Variables
# ============================================================================
CHECK_ONLY=false
FORCE_REINSTALL=false
ROLLBACK_MODE=false
UPDATE_LOCK="${ALICIA_LOCK_DIR}/alicia-update.lock"
CURRENT_VERSION="${ALICIA_VERSION}"
LATEST_VERSION=""
DOWNLOAD_DIR="${ALICIA_DOWNLOAD_DIR}/updates"
BACKUP_DIR="${ALICIA_BACKUP_DIR}/pre-update"
ROLLBACK_DIR="${ALICIA_BACKUP_DIR}/rollback"

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check|-c)
                CHECK_ONLY=true
                shift
                ;;
            --force|-f)
                FORCE_REINSTALL=true
                shift
                ;;
            --rollback|-r)
                ROLLBACK_MODE=true
                shift
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
    echo "Usage: update.sh [OPTIONS]"
    echo ""
    echo "Update the Alicia Desktop Environment."
    echo ""
    echo "Options:"
    echo "  --check,   -c   Only check for updates (do not apply)"
    echo "  --force,   -f   Reinstall current version"
    echo "  --rollback, -r  Restore previous version"
    echo "  --help,    -h   Show this help"
    echo ""
    echo "Examples:"
    echo "  update.sh --check        Check if updates are available"
    echo "  update.sh                Apply available update"
    echo "  update.sh --force        Reinstall current version"
    echo "  update.sh --rollback     Roll back to previous version"
}

# ============================================================================
# Version Comparison
# ============================================================================
compare_versions() {
    local ver_a="$1"
    local op="$2"
    local ver_b="$3"

    # Strip leading 'v'
    ver_a="${ver_a#v}"
    ver_b="${ver_b#v}"

    # Parse into components
    IFS='.' read -ra parts_a <<< "${ver_a%%-*}"
    IFS='.' read -ra parts_b <<< "${ver_b%%-*}"

    local major_a="${parts_a[0]:-0}" minor_a="${parts_a[1]:-0}" patch_a="${parts_a[2]:-0}"
    local major_b="${parts_b[0]:-0}" minor_b="${parts_b[1]:-0}" patch_b="${parts_b[2]:-0}"

    local num_a=$(( major_a * 1000000 + minor_a * 1000 + patch_a ))
    local num_b=$(( major_b * 1000000 + minor_b * 1000 + patch_b ))

    case "${op}" in
        eq|==) [[ ${num_a} -eq ${num_b} ]] ;;
        ne|!=) [[ ${num_a} -ne ${num_b} ]] ;;
        lt|<)  [[ ${num_a} -lt ${num_b} ]] ;;
        le|<=) [[ ${num_a} -le ${num_b} ]] ;;
        gt|>)  [[ ${num_a} -gt ${num_b} ]] ;;
        ge|>=) [[ ${num_a} -ge ${num_b} ]] ;;
    esac
}

# ============================================================================
# Check for Updates
# ============================================================================
check_for_updates() {
    log_section "Checking for Updates"

    local current="${CURRENT_VERSION}"
    log_info "Current version: v${current}"

    # Check network first
    if ! network_is_available 2>/dev/null; then
        log_error "No network connectivity -- cannot check for updates"
        return 1
    fi

    # Query GitHub API
    log_info "Checking GitHub for latest release..."
    local api_url="https://api.github.com/repos/${ALICIA_GITHUB_REPO}/releases/latest"
    local response
    response=$(curl -s --connect-timeout 15 "$api_url" 2>/dev/null) || {
        log_error "Failed to reach GitHub API"
        return 1
    }

    # Extract latest version
    LATEST_VERSION=$(echo "${response}" | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null | head -1)
    LATEST_VERSION="${LATEST_VERSION#v}"  # Strip 'v' prefix

    if [[ -z "${LATEST_VERSION}" ]]; then
        log_error "Could not determine latest version from GitHub"
        return 1
    fi

    log_info "Latest version:  v${LATEST_VERSION}"

    # Compare versions
    if compare_versions "${LATEST_VERSION}" "gt" "${current}"; then
        log_info "Update available: v${current} -> v${LATEST_VERSION}"
        show_changelog "${response}"
        return 0  # Update available
    elif compare_versions "${LATEST_VERSION}" "eq" "${current}"; then
        if [[ "${FORCE_REINSTALL}" == "true" ]]; then
            log_info "Already at latest version (v${current}) -- force reinstall requested"
            return 0
        fi
        log_info "Already up to date: v${current}"
        return 2  # No update needed
    else
        log_warn "Current version (v${current}) is newer than latest release (v${LATEST_VERSION})"
        return 2
    fi
}

# ============================================================================
# Show Changelog
# ============================================================================
show_changelog() {
    local response="$1"
    local body
    body=$(echo "${response}" | grep -oP '"body":\s*"\K[^"]*' 2>/dev/null | head -1 || echo "")

    if [[ -n "${body}" ]]; then
        # Unescape newlines in JSON
        body="${body//\\n/$'\n'}"
        body="${body//\\r/}"
        echo ""
        printf "${COLOR_BOLD_CYAN}  Changelog:${COLOR_RESET}\n"
        echo "  ----------------------------------------"
        while IFS= read -r line; do
            printf "  %s\n" "${line}"
        done <<< "${body}" | head -30
        echo "  ----------------------------------------"
    fi
}

# ============================================================================
# Create Pre-Update Backup
# ============================================================================
create_pre_update_backup() {
    log_section "Creating Pre-Update Backup"

    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_name="pre_update_v${CURRENT_VERSION}_${timestamp}"

    mkdir -p "${BACKUP_DIR}"

    log_info "Backing up Alicia root directory: ${ALICIA_ROOT}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"

    # Backup the entire Alicia installation
    tar -czf "${backup_file}" \
        -C "$(dirname "${ALICIA_ROOT}")" \
        "$(basename "${ALICIA_ROOT}")" \
        --exclude="${ALICIA_ROOT}/backups" \
        --exclude="${ALICIA_ROOT}/cache" \
        --exclude="${ALICIA_ROOT}/tmp" \
        --exclude="${ALICIA_ROOT}/rootfs" \
        --exclude="${ALICIA_ROOT}/logs" \
        2>/dev/null || {
        log_error "Failed to create pre-update backup"
        return 1
    }

    local backup_size
    backup_size=$(du -h "${backup_file}" | cut -f1)
    log_info "Pre-update backup created: ${backup_file} (${backup_size})"

    # Store rollback info
    mkdir -p "${ROLLBACK_DIR}"
    cat > "${ROLLBACK_DIR}/rollback.info" <<EOF
previous_version=${CURRENT_VERSION}
backup_file=${backup_file}
backup_timestamp=${timestamp}
updated_from=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    return 0
}

# ============================================================================
# Download Update
# ============================================================================
download_update() {
    log_section "Downloading Update"

    mkdir -p "${DOWNLOAD_DIR}"

    local target_version="${LATEST_VERSION:-${CURRENT_VERSION}}"
    log_info "Downloading Alicia v${target_version}..."

    # Try GitHub release download
    if declare -f github_download_release &>/dev/null; then
        if github_download_release "${ALICIA_GITHUB_REPO}" "v${target_version}" "alicia" "${DOWNLOAD_DIR}" 2>/dev/null; then
            log_info "Update downloaded from GitHub releases"
            return 0
        fi
    fi

    # Fallback: git pull if it's a git repo
    if [[ -d "${ALICIA_ROOT}/.git" ]]; then
        log_info "Attempting git pull for update..."
        local current_branch
        current_branch=$(cd "${ALICIA_ROOT}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

        if (cd "${ALICIA_ROOT}" && git fetch origin "${current_branch}" 2>/dev/null && \
            git diff --quiet "origin/${current_branch}" 2>/dev/null); then
            log_info "No changes to pull from git"
        else
            (cd "${ALICIA_ROOT}" && git stash 2>/dev/null || true)
            (cd "${ALICIA_ROOT}" && git pull origin "${current_branch}" 2>/dev/null) || {
                log_error "Git pull failed"
                return 1
            }
            log_info "Update pulled via git"
        fi
        return 0
    fi

    log_error "No update method available (neither GitHub releases nor git)"
    return 1
}

# ============================================================================
# Apply Update
# ============================================================================
apply_update() {
    log_section "Applying Update"

    # Find the downloaded update archive
    local update_file=""
    for f in "${DOWNLOAD_DIR}"/alicia-*.tar.gz "${DOWNLOAD_DIR}"/alicia-*.zip; do
        if [[ -f "${f}" ]]; then
            update_file="${f}"
            break
        fi
    done

    if [[ -n "${update_file}" ]]; then
        log_info "Applying update from: ${update_file}"

        # Create temporary extraction directory
        local extract_dir
        extract_dir=$(mktemp -d "${ALICIA_TMP_DIR}/alicia-update.XXXXXX")

        # Extract
        if ! alicia_extract_archive "${update_file}" "${extract_dir}" 2>/dev/null; then
            log_error "Failed to extract update archive"
            rm -rf "${extract_dir}"
            return 1
        fi

        # Find the extracted directory (might be nested)
        local source_dir="${extract_dir}"
        if [[ -d "${extract_dir}/alicia" ]]; then
            source_dir="${extract_dir}/alicia"
        fi

        # Replace files (preserving local data)
        log_info "Replacing installation files..."
        local dirs_to_update=("scripts" "lib" "setup")
        for dir in "${dirs_to_update[@]}"; do
            if [[ -d "${source_dir}/${dir}" ]]; then
                rm -rf "${ALICIA_ROOT}/${dir}"
                cp -a "${source_dir}/${dir}" "${ALICIA_ROOT}/${dir}"
                log_info "  Updated: ${dir}/"
            fi
        done

        # Update version file if present
        if [[ -f "${source_dir}/VERSION" ]]; then
            cp "${source_dir}/VERSION" "${ALICIA_ROOT}/VERSION"
        fi

        # Clean up
        rm -rf "${extract_dir}"
        rm -f "${update_file}"

        log_info "Update files applied"
    else
        # Git-based update was already applied in download step
        log_info "Git-based update already applied"
    fi

    return 0
}

# ============================================================================
# Update Packages Inside proot
# ============================================================================
update_proot_packages() {
    log_section "Updating Packages"

    log_info "Updating package lists inside proot..."
    pkg_update 2>/dev/null || {
        log_warn "Failed to update package lists"
    }

    log_info "Upgrading installed packages..."
    pkg_upgrade 2>/dev/null || {
        log_warn "Failed to upgrade packages"
    }

    log_info "Package update complete"
}

# ============================================================================
# Run Post-Update Scripts
# ============================================================================
run_post_update_scripts() {
    log_section "Post-Update Scripts"

    local post_update_dir="${ALICIA_ROOT}/post-update.d"
    if [[ ! -d "${post_update_dir}" ]]; then
        log_info "No post-update scripts directory found"
        return 0
    fi

    local count=0
    for script in "${post_update_dir}"/*.sh; do
        if [[ -f "${script}" && -x "${script}" ]]; then
            log_info "Running post-update script: $(basename "${script}")"
            bash "${script}" 2>/dev/null || {
                log_warn "Post-update script failed: $(basename "${script}")"
            }
            ((count++)) || true
        fi
    done

    if [[ ${count} -eq 0 ]]; then
        log_info "No post-update scripts to run"
    else
        log_info "Ran ${count} post-update script(s)"
    fi

    return 0
}

# ============================================================================
# Verify Update Integrity
# ============================================================================
verify_update_integrity() {
    log_section "Verifying Update"

    local failures=0

    # Check core library files exist
    local required_libs=(
        "alicia-core.sh"
        "alicia-log.sh"
        "alicia-system.sh"
        "alicia-network.sh"
        "alicia-storage.sh"
        "alicia-ui.sh"
    )

    for lib in "${required_libs[@]}"; do
        if [[ ! -f "${LIB_DIR}/${lib}" ]]; then
            log_error "Missing library: ${lib}"
            ((failures++)) || true
        else
            # Check the file is not empty
            local size
            size=$(wc -c < "${LIB_DIR}/${lib}")
            if [[ ${size} -lt 100 ]]; then
                log_error "Library file appears corrupt: ${lib} (${size} bytes)"
                ((failures++)) || true
            fi
        fi
    done

    # Check scripts exist
    local required_scripts=(
        "start.sh"
        "stop.sh"
        "status.sh"
        "config.sh"
        "update.sh"
        "backup.sh"
        "watchdog.sh"
        "install.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
            log_error "Missing script: ${script}"
            ((failures++)) || true
        fi
    done

    # Check setup scripts exist
    if [[ -d "${ALICIA_ROOT}/setup" ]]; then
        local setup_count
        setup_count=$(find "${ALICIA_ROOT}/setup" -name "*.sh" | wc -l)
        if [[ ${setup_count} -lt 6 ]]; then
            log_warn "Some setup scripts may be missing (found ${setup_count}, expected 6)"
        fi
    fi

    if [[ ${failures} -gt 0 ]]; then
        log_error "Update verification failed (${failures} issue(s) found)"
        return 1
    fi

    log_info "Update integrity verification passed"
    return 0
}

# ============================================================================
# Rollback
# ============================================================================
perform_rollback() {
    log_section "Rolling Back Update"

    if [[ ! -f "${ROLLBACK_DIR}/rollback.info" ]]; then
        log_error "No rollback information found"
        log_info "Cannot determine previous version to roll back to"
        return 1
    fi

    # Read rollback info
    local previous_version backup_file
    previous_version=$(grep '^previous_version=' "${ROLLBACK_DIR}/rollback.info" | cut -d= -f2)
    backup_file=$(grep '^backup_file=' "${ROLLBACK_DIR}/rollback.info" | cut -d= -f2)

    if [[ -z "${backup_file}" || ! -f "${backup_file}" ]]; then
        log_error "Rollback backup file not found: ${backup_file}"
        return 1
    fi

    log_info "Rolling back to version: v${previous_version}"
    log_info "Using backup: ${backup_file}"

    # Verify backup integrity
    if ! backup_verify "${backup_file}" 2>/dev/null; then
        log_error "Rollback backup integrity check failed"
        return 1
    fi

    # Stop Alicia before rollback
    if alicia_is_running "alicia" 2>/dev/null; then
        log_info "Stopping Alicia before rollback..."
        if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
            bash "${SCRIPT_DIR}/stop.sh" --force 2>/dev/null || true
        fi
        sleep 2
    fi

    # Extract backup
    log_info "Restoring from backup..."
    local extract_dir
    extract_dir=$(mktemp -d "${ALICIA_TMP_DIR}/alicia-rollback.XXXXXX")

    tar -xzf "${backup_file}" -C "${extract_dir}" 2>/dev/null || {
        log_error "Failed to extract rollback backup"
        rm -rf "${extract_dir}"
        return 1
    }

    # Find the extracted directory
    local source_dir="${extract_dir}"
    if [[ -d "${extract_dir}/alicia" ]]; then
        source_dir="${extract_dir}/alicia"
    fi

    # Restore files (preserving data directories)
    local dirs_to_restore=("scripts" "lib" "setup")
    for dir in "${dirs_to_restore[@]}"; do
        if [[ -d "${source_dir}/${dir}" ]]; then
            rm -rf "${ALICIA_ROOT}/${dir}"
            cp -a "${source_dir}/${dir}" "${ALICIA_ROOT}/${dir}"
            log_info "  Restored: ${dir}/"
        fi
    done

    # Clean up
    rm -rf "${extract_dir}"
    rm -f "${ROLLBACK_DIR}/rollback.info"

    log_info "Rollback complete -- restored to v${previous_version}"

    printf "\n${COLOR_BOLD_GREEN}  Rollback successful!${COLOR_RESET}\n"
    printf "  Restored to version: v${previous_version}\n"
    printf "  Run 'start.sh' to restart Alicia.\n\n"

    return 0
}

# ============================================================================
# Full Update Process
# ============================================================================
perform_update() {
    log_section "Updating Alicia Desktop Environment"
    log_timer_start "update"

    # Acquire update lock
    if ! alicia_lock_acquire "alicia-update" 60; then
        log_error "Another update process is already running"
        return 1
    fi

    # Step 1: Check for updates
    local update_result
    check_for_updates
    update_result=$?

    if [[ ${update_result} -eq 2 ]]; then
        if [[ "${FORCE_REINSTALL}" != "true" ]]; then
            alicia_lock_release "alicia-update"
            return 0
        fi
        # Force reinstall continues below
    elif [[ ${update_result} -ne 0 ]]; then
        alicia_lock_release "alicia-update"
        return 1
    fi

    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log_info "Check-only mode -- not applying update"
        alicia_lock_release "alicia-update"
        return 0
    fi

    # Step 2: Create backup
    if ! create_pre_update_backup; then
        log_error "Aborting update -- backup failed"
        alicia_lock_release "alicia-update"
        return 1
    fi

    # Step 3: Download update
    if ! download_update; then
        log_error "Aborting update -- download failed"
        alicia_lock_release "alicia-update"
        return 1
    fi

    # Step 4: Apply update
    if ! apply_update; then
        log_error "Update apply failed -- initiating rollback"
        perform_rollback
        alicia_lock_release "alicia-update"
        return 1
    fi

    # Step 5: Verify integrity
    if ! verify_update_integrity; then
        log_error "Integrity verification failed -- initiating rollback"
        perform_rollback
        alicia_lock_release "alicia-update"
        return 1
    fi

    # Step 6: Update packages inside proot
    update_proot_packages || true

    # Step 7: Run post-update scripts
    run_post_update_scripts || true

    # Release lock
    alicia_lock_release "alicia-update"

    log_timer_end "update"

    # Success summary
    local new_version="${LATEST_VERSION:-${CURRENT_VERSION}}"
    printf "\n${COLOR_BOLD_GREEN}  Update successful!${COLOR_RESET}\n"
    printf "  Version: v${CURRENT_VERSION} -> v${new_version}\n"
    printf "  Restart Alicia to use the updated version.\n\n"

    log_info "Update completed: v${CURRENT_VERSION} -> v${new_version}"
    return 0
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"

    if [[ "${ROLLBACK_MODE}" == "true" ]]; then
        perform_rollback
        exit $?
    fi

    perform_update
    exit $?
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
