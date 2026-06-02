#!/bin/bash
# ============================================================================
# alicia-storage.sh - Alicia Desktop Environment Storage Management Library
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      3.1.0
# Description:  Storage management library providing space checking, download
#               management with resume, cache/backup management, file integrity,
#               and storage optimization capabilities.
# ============================================================================

# set -euo pipefail removed for library sourcing safety

if [[ -n "${_ALICIA_STORAGE_LOADED:-}" ]]; then
    return 0
fi
_ALICIA_STORAGE_LOADED=1

_ALICIA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ALICIA_LIB_DIR}/alicia-core.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-log.sh" 2>/dev/null || true

: "${ALICIA_CACHE_DIR:="${ALICIA_HOME:-$HOME/alicia}/cache"}"
: "${ALICIA_BACKUP_DIR:="${ALICIA_HOME:-$HOME/alicia}/backups"}"
: "${ALICIA_TEMP_DIR:="${ALICIA_HOME:-$HOME/alicia}/tmp"}"
: "${ALICIA_DOWNLOAD_DIR:="${ALICIA_HOME:-$HOME/alicia}/downloads"}"

# ============================================================================
# Storage Space Checking
# ============================================================================

# storage_get_available_space - Get available disk space in MB
storage_get_available_space() {
    local path="${1:-$HOME}"
    local avail
    avail=$(df -BM "$path" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'M')
    echo "${avail:-0}"
}

# storage_get_total_space - Get total disk space in MB
storage_get_total_space() {
    local path="${1:-$HOME}"
    local total
    total=$(df -BM "$path" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d 'M')
    echo "${total:-0}"
}

# storage_get_used_space - Get used disk space in MB
storage_get_used_space() {
    local path="${1:-$HOME}"
    local used
    used=$(df -BM "$path" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d 'M')
    echo "${used:-0}"
}

# storage_get_usage_percent - Get disk usage percentage
storage_get_usage_percent() {
    local path="${1:-$HOME}"
    local pct
    pct=$(df "$path" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    echo "${pct:-0}"
}

# storage_check_min_space - Check if minimum space is available
storage_check_min_space() {
    local required_mb="${1:-500}"
    local path="${2:-$HOME}"
    local available
    available=$(storage_get_available_space "$path")

    if [[ $available -ge $required_mb ]]; then
        log_debug "Storage check passed: ${available}MB available (needed: ${required_mb}MB)"
        return 0
    else
        log_error "Insufficient storage: ${available}MB available (needed: ${required_mb}MB)"
        return 1
    fi
}

# storage_get_info - Get comprehensive storage info
storage_get_info() {
    local path="${1:-$HOME}"
    echo "Storage Information for: $path"
    echo "  Total:     $(storage_get_total_space "$path") MB"
    echo "  Used:      $(storage_get_used_space "$path") MB"
    echo "  Available: $(storage_get_available_space "$path") MB"
    echo "  Usage:     $(storage_get_usage_percent "$path")%"
    echo ""
    echo "Alicia Directories:"
    echo "  Cache:     $(du -sm "$ALICIA_CACHE_DIR" 2>/dev/null | cut -f1 || echo 0) MB"
    echo "  Backups:   $(du -sm "$ALICIA_BACKUP_DIR" 2>/dev/null | cut -f1 || echo 0) MB"
    echo "  Temp:      $(du -sm "$ALICIA_TEMP_DIR" 2>/dev/null | cut -f1 || echo 0) MB"
    echo "  Downloads: $(du -sm "$ALICIA_DOWNLOAD_DIR" 2>/dev/null | cut -f1 || echo 0) MB"
}

# ============================================================================
# Download Management
# ============================================================================

# download_file - Download a file with progress and error handling
download_file() {
    local url="$1"
    local output_path="$2"
    local description="${3:-Downloading file}"

    if [[ -z "$url" || -z "$output_path" ]]; then
        log_error "URL and output path are required"
        return 1
    fi

    log_info "$description"
    log_debug "  URL: $url"
    log_debug "  Output: $output_path"

    # Ensure output directory exists
    mkdir -p "$(dirname "$output_path")"

    # Try wget first, then curl
    if command -v wget &>/dev/null; then
        wget --continue --progress=bar:force:noscroll \
            --tries=5 --timeout=30 \
            -O "$output_path" "$url" 2>&1 | while IFS= read -r line; do
            log_debug "  wget: $line"
        done
    elif command -v curl &>/dev/null; then
        curl --continue-at - --progress-bar \
            --retry 5 --retry-delay 3 --connect-timeout 30 \
            -o "$output_path" "$url" 2>&1 | while IFS= read -r line; do
            log_debug "  curl: $line"
        done
    else
        log_error "No download tool available (wget/curl)"
        return 1
    fi

    if [[ -f "$output_path" ]]; then
        log_info "Download complete: $output_path ($(du -h "$output_path" | cut -f1))"
        return 0
    else
        log_error "Download failed: $url"
        return 1
    fi
}

# download_verify - Download and verify a file's checksum
download_verify() {
    local url="$1"
    local output_path="$2"
    local expected_checksum="$3"
    local algorithm="${4:-sha256}"
    local description="${5:-Downloading and verifying file}"

    download_file "$url" "$output_path" "$description" || return 1

    log_info "Verifying checksum ($algorithm)..."
    local actual_checksum
    actual_checksum=$(_compute_checksum "$output_path" "$algorithm")

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log_info "Checksum verification passed"
        return 0
    else
        log_error "Checksum verification FAILED"
        log_error "  Expected: $expected_checksum"
        log_error "  Actual:   $actual_checksum"
        rm -f "$output_path"
        return 1
    fi
}

# _compute_checksum - Compute file checksum
_compute_checksum() {
    local file_path="$1"
    local algorithm="${2:-sha256}"

    case "$algorithm" in
        md5)    md5sum "$file_path" | awk '{print $1}' ;;
        sha1)   sha1sum "$file_path" | awk '{print $1}' ;;
        sha256) sha256sum "$file_path" | awk '{print $1}' ;;
        sha512) sha512sum "$file_path" | awk '{print $1}' ;;
        *)      sha256sum "$file_path" | awk '{print $1}' ;;
    esac
}

# ============================================================================
# Cache Management
# ============================================================================

# cache_init - Initialize cache directory
cache_init() {
    local cache_dir="${1:-$ALICIA_CACHE_DIR}"
    mkdir -p "$cache_dir"
    log_debug "Cache initialized: $cache_dir"
}

# cache_store - Store data in cache
cache_store() {
    local key="$1"
    local source_path="$2"
    local ttl="${3:-3600}"  # Time to live in seconds

    if [[ -z "$key" || ! -f "$source_path" ]]; then
        log_error "Cache key and valid source path are required"
        return 1
    fi

    local cache_file="${ALICIA_CACHE_DIR}/${key}"
    local meta_file="${ALICIA_CACHE_DIR}/.${key}.meta"

    cp "$source_path" "$cache_file" || {
        log_error "Failed to store cache: $key"
        return 1
    }

    echo "stored=$(date +%s)" > "$meta_file"
    echo "ttl=$ttl" >> "$meta_file"
    echo "source=$source_path" >> "$meta_file"

    log_debug "Cached: $key (TTL: ${ttl}s)"
    return 0
}

# cache_retrieve - Retrieve data from cache
cache_retrieve() {
    local key="$1"
    local output_path="${2:-}"

    local cache_file="${ALICIA_CACHE_DIR}/${key}"
    local meta_file="${ALICIA_CACHE_DIR}/.${key}.meta"

    if [[ ! -f "$cache_file" ]]; then
        log_debug "Cache miss: $key"
        return 1
    fi

    # Check TTL
    if [[ -f "$meta_file" ]]; then
        local stored ttl now
        stored=$(grep '^stored=' "$meta_file" | cut -d= -f2)
        ttl=$(grep '^ttl=' "$meta_file" | cut -d= -f2)
        now=$(date +%s)

        if [[ -n "$stored" && -n "$ttl" && $((now - stored)) -gt $ttl ]]; then
            log_debug "Cache expired: $key"
            rm -f "$cache_file" "$meta_file"
            return 1
        fi
    fi

    if [[ -n "$output_path" ]]; then
        cp "$cache_file" "$output_path"
    else
        cat "$cache_file"
    fi

    log_debug "Cache hit: $key"
    return 0
}

# cache_invalidate - Invalidate a cache entry
cache_invalidate() {
    local key="$1"
    rm -f "${ALICIA_CACHE_DIR}/${key}" "${ALICIA_CACHE_DIR}/.${key}.meta"
    log_debug "Cache invalidated: $key"
}

# cache_clear - Clear all cache
cache_clear() {
    log_info "Clearing cache directory: $ALICIA_CACHE_DIR"
    rm -rf "${ALICIA_CACHE_DIR:?}"/*
    log_info "Cache cleared"
}

# cache_size - Get total cache size
cache_size() {
    du -sm "$ALICIA_CACHE_DIR" 2>/dev/null | cut -f1 || echo 0
}

# ============================================================================
# Backup Management
# ============================================================================

# backup_create - Create a backup of specified directory
backup_create() {
    local source_dir="$1"
    local backup_name="${2:-backup}"
    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")

    if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
        log_error "Valid source directory is required for backup"
        return 1
    fi

    mkdir -p "$ALICIA_BACKUP_DIR"
    local backup_file="${ALICIA_BACKUP_DIR}/${backup_name}_${timestamp}.tar.gz"

    log_info "Creating backup: $backup_name"
    log_debug "  Source: $source_dir"
    log_debug "  Output: $backup_file"

    tar -czf "$backup_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>&1 | while IFS= read -r line; do
        log_debug "  tar: $line"
    done || {
        log_error "Backup creation failed"
        rm -f "$backup_file"
        return 1
    }

    local size
    size=$(du -h "$backup_file" | cut -f1)
    log_info "Backup created: $backup_file ($size)"
    return 0
}

# backup_restore - Restore from a backup
backup_restore() {
    local backup_file="$1"
    local restore_dir="${2:-$(dirname "$ALICIA_ROOTFS_DIR")}"

    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        log_error "Valid backup file is required"
        return 1
    fi

    log_info "Restoring backup: $backup_file"
    tar -xzf "$backup_file" -C "$restore_dir" || {
        log_error "Backup restoration failed"
        return 1
    }

    log_info "Backup restored to: $restore_dir"
    return 0
}

# backup_list - List available backups
backup_list() {
    if [[ ! -d "$ALICIA_BACKUP_DIR" ]]; then
        echo "No backups found"
        return 0
    fi

    echo "Available Backups:"
    echo "=================="
    local count=0
    for f in "${ALICIA_BACKUP_DIR}"/*.tar.gz; do
        if [[ -f "$f" ]]; then
            local size
            size=$(du -h "$f" | cut -f1)
            local basename
            basename=$(basename "$f")
            echo "  $basename ($size)"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "  No backups found"
    fi
}

# backup_delete - Delete a backup
backup_delete() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        rm -f "$backup_file"
        log_info "Backup deleted: $(basename "$backup_file")"
        return 0
    else
        log_error "Backup file not found: $backup_file"
        return 1
    fi
}

# backup_verify - Verify a backup's integrity
backup_verify() {
    local backup_file="$1"
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_info "Verifying backup integrity: $(basename "$backup_file")"
    tar -tzf "$backup_file" &>/dev/null || {
        log_error "Backup integrity check failed: $backup_file"
        return 1
    }

    log_info "Backup integrity verified"
    return 0
}

# ============================================================================
# Temporary File Management
# ============================================================================

# temp_create - Create a temporary file
temp_create() {
    local prefix="${1:-alicia}"
    local tmp_dir="${ALICIA_TEMP_DIR}"
    mkdir -p "$tmp_dir"

    local tmp_file
    tmp_file=$(mktemp "${tmp_dir}/${prefix}.XXXXXX")
    log_debug "Created temp file: $tmp_file"
    echo "$tmp_file"
}

# temp_create_dir - Create a temporary directory
temp_create_dir() {
    local prefix="${1:-alicia}"
    local tmp_dir="${ALICIA_TEMP_DIR}"
    mkdir -p "$tmp_dir"

    local tmp_dir_path
    tmp_dir_path=$(mktemp -d "${tmp_dir}/${prefix}.XXXXXX")
    log_debug "Created temp directory: $tmp_dir_path"
    echo "$tmp_dir_path"
}

# temp_cleanup - Clean up temporary files
temp_cleanup() {
    local max_age_days="${1:-1}"
    local count=0

    if [[ ! -d "$ALICIA_TEMP_DIR" ]]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done < <(find "$ALICIA_TEMP_DIR" -type f -mtime +"$max_age_days" -print0 2>/dev/null)

    while IFS= read -r -d '' dir; do
        rmdir "$dir" 2>/dev/null && ((count++)) || true
    done < <(find "$ALICIA_TEMP_DIR" -type d -empty -mtime +"$max_age_days" -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        log_info "Cleaned up $count temporary files/directories"
    fi
}

# temp_list - List temporary files
temp_list() {
    if [[ ! -d "$ALICIA_TEMP_DIR" ]]; then
        echo "No temporary files"
        return 0
    fi
    find "$ALICIA_TEMP_DIR" -type f | head -20
}

# ============================================================================
# Storage Optimization
# ============================================================================

# storage_optimize - Optimize storage usage
storage_optimize() {
    log_section "Optimizing Storage"

    local freed_mb=0

    # Clean package manager caches
    log_info "Cleaning package manager caches..."
    local before after
    before=$(storage_get_available_space)
    proot_exec "$ALICIA_DISTRO_NAME" "apk cache purge 2>/dev/null; apt-get clean 2>/dev/null; dnf clean all 2>/dev/null" 2>/dev/null || true
    after=$(storage_get_available_space)
    freed_mb=$((after - before))
    log_info "Package caches cleaned (freed: ${freed_mb}MB)"

    # Clean temp files
    temp_cleanup

    # Clean old log files
    log_cleanup 7

    # Clean expired cache
    cache_clear

    # Remove orphan packages
    log_info "Removing orphan packages..."
    proot_exec "$ALICIA_DISTRO_NAME" "apk autoremove 2>/dev/null; apt-get autoremove -y 2>/dev/null" 2>/dev/null || true

    log_info "Storage optimization complete (freed approximately ${freed_mb}MB)"
}

# ============================================================================
# File Integrity Verification
# ============================================================================

# verify_checksum - Verify a file's checksum
verify_checksum() {
    local file_path="$1"
    local expected_checksum="$2"
    local algorithm="${3:-sha256}"

    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi

    local actual_checksum
    actual_checksum=$(_compute_checksum "$file_path" "$algorithm")

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log_info "Checksum verified: $file_path"
        return 0
    else
        log_error "Checksum mismatch: $file_path"
        log_error "  Expected: $expected_checksum"
        log_error "  Actual:   $actual_checksum"
        return 1
    fi
}

# generate_checksum - Generate checksum for a file
generate_checksum() {
    local file_path="$1"
    local algorithm="${2:-sha256}"

    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi

    _compute_checksum "$file_path" "$algorithm"
}

# ============================================================================
# Archive Management
# ============================================================================

# create_archive - Create a compressed archive
create_archive() {
    local source_dir="$1"
    local output_file="$2"
    local compression="${3:-gz}"

    if [[ -z "$source_dir" || -z "$output_file" ]]; then
        log_error "Source directory and output file are required"
        return 1
    fi

    log_info "Creating archive: $output_file from $source_dir"

    case "$compression" in
        gz|gzip) tar -czf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" ;;
        bz2|bzip2) tar -cjf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" ;;
        xz) tar -cJf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" ;;
        none) tar -cf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" ;;
        *) tar -czf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" ;;
    esac

    if [[ -f "$output_file" ]]; then
        log_info "Archive created: $output_file ($(du -h "$output_file" | cut -f1))"
        return 0
    else
        log_error "Failed to create archive"
        return 1
    fi
}

# extract_archive - Extract a compressed archive
extract_archive() {
    local archive_file="$1"
    local output_dir="${2:-.}"

    if [[ ! -f "$archive_file" ]]; then
        log_error "Archive file not found: $archive_file"
        return 1
    fi

    log_info "Extracting: $archive_file to $output_dir"
    mkdir -p "$output_dir"

    case "$archive_file" in
        *.tar.gz|*.tgz)  tar -xzf "$archive_file" -C "$output_dir" ;;
        *.tar.bz2|*.tbz2) tar -xjf "$archive_file" -C "$output_dir" ;;
        *.tar.xz|*.txz)  tar -xJf "$archive_file" -C "$output_dir" ;;
        *.tar)            tar -xf "$archive_file" -C "$output_dir" ;;
        *.zip)            unzip -q "$archive_file" -d "$output_dir" ;;
        *.7z)             7z x "$archive_file" -o"$output_dir" ;;
        *)
            log_error "Unknown archive format: $archive_file"
            return 1
            ;;
    esac

    log_info "Extraction complete"
    return 0
}

# list_archive - List contents of an archive
list_archive() {
    local archive_file="$1"

    if [[ ! -f "$archive_file" ]]; then
        log_error "Archive file not found: $archive_file"
        return 1
    fi

    case "$archive_file" in
        *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.tar)
            tar -tf "$archive_file" | head -50
            ;;
        *.zip)
            unzip -l "$archive_file" | head -50
            ;;
        *)
            log_error "Unknown archive format"
            return 1
            ;;
    esac
}

# ============================================================================
# Large File Handling
# ============================================================================

# split_file - Split a large file into parts
split_file() {
    local file_path="$1"
    local part_size="${2:-100M}"
    local output_dir="${3:-.}"

    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi

    log_info "Splitting file: $file_path (part size: $part_size)"
    mkdir -p "$output_dir"

    split -b "$part_size" -d --suffix-length=3 "$file_path" "${output_dir}/$(basename "$file_path").part"

    log_info "File split complete"
    ls -la "${output_dir}/$(basename "$file_path").part"*
}

# join_file - Join split file parts
join_file() {
    local part_pattern="$1"
    local output_file="$2"

    if [[ -z "$part_pattern" || -z "$output_file" ]]; then
        log_error "Part pattern and output file are required"
        return 1
    fi

    log_info "Joining files: $part_pattern -> $output_file"
    cat $part_pattern > "$output_file"

    if [[ -f "$output_file" ]]; then
        log_info "Files joined: $output_file"
        return 0
    else
        log_error "Failed to join files"
        return 1
    fi
}

# ============================================================================
# Old Version Cleanup
# ============================================================================

# cleanup_old_versions - Remove old version data
cleanup_old_versions() {
    local keep_versions="${1:-3}"
    log_info "Cleaning up old versions (keeping last $keep_versions)"

    if [[ ! -d "$ALICIA_BACKUP_DIR" ]]; then
        return 0
    fi

    local count=0
    local backups=()
    while IFS= read -r f; do
        backups+=("$f")
    done < <(ls -t "${ALICIA_BACKUP_DIR}"/*.tar.gz 2>/dev/null)

    if [[ ${#backups[@]} -le $keep_versions ]]; then
        log_info "Not enough backups to clean up (${#backups[@]} found, keeping $keep_versions)"
        return 0
    fi

    for ((i = keep_versions; i < ${#backups[@]}; i++)); do
        rm -f "${backups[$i]}"
        ((count++))
        log_debug "Removed old backup: $(basename "${backups[$i]}")"
    done

    log_info "Cleaned up $count old backup files"
}

# ============================================================================
# Initialize storage directories
# ============================================================================
mkdir -p "$ALICIA_CACHE_DIR" "$ALICIA_BACKUP_DIR" "$ALICIA_TEMP_DIR" "$ALICIA_DOWNLOAD_DIR" 2>/dev/null || true
