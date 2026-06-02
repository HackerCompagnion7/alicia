#!/bin/bash
# ============================================================================
# alicia-network.sh - Alicia Desktop Environment Network Management Library
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      3.1.0
# Description:  Network management library providing connectivity testing,
#               smart downloading, SSH/web server management, DNS configuration,
#               network diagnostics, and GitHub API interaction.
# ============================================================================

set -euo pipefail

if [[ -n "${_ALICIA_NETWORK_LOADED:-}" ]]; then
    return 0
fi
_ALICIA_NETWORK_LOADED=1

_ALICIA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ALICIA_LIB_DIR}/alicia-core.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-log.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-storage.sh" 2>/dev/null || true

: "${ALICIA_NETWORK_TIMEOUT:=30}"
: "${ALICIA_NETWORK_RETRIES:=3}"
: "${ALICIA_NETWORK_RETRY_DELAY:=5}"

# ============================================================================
# Network Connectivity Testing
# ============================================================================

# network_is_available - Check if network is available
network_is_available() {
    local test_urls=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 5 "$url" &>/dev/null; then
            return 0
        fi
    done
    return 1
}

# network_test_connection - Test connection to a specific host
network_test_connection() {
    local host="${1:-8.8.8.8}"
    local port="${2:-0}"
    local timeout="${3:-$ALICIA_NETWORK_TIMEOUT}"

    if [[ $port -eq 0 ]]; then
        # Ping test
        ping -c 3 -W "$timeout" "$host" &>/dev/null
    else
        # Port test
        (echo >/dev/tcp/"$host"/"$port") 2>/dev/null
    fi
}

# network_test_dns - Test DNS resolution
network_test_dns() {
    local domain="${1:-google.com}"
    local timeout="${2:-10}"

    log_debug "Testing DNS resolution for: $domain"

    if nslookup "$domain" &>/dev/null || host "$domain" &>/dev/null || dig +short "$domain" &>/dev/null; then
        log_debug "DNS resolution OK for: $domain"
        return 0
    else
        log_warn "DNS resolution failed for: $domain"
        return 1
    fi
}

# network_test_speed - Basic network speed test
network_test_speed() {
    local test_url="${1:-https://speed.cloudflare.com/__down?bytes=1000000}"
    local iterations="${2:-3}"
    local total_time=0
    local success_count=0

    log_info "Running network speed test ($iterations iterations)..."

    for ((i = 1; i <= iterations; i++)); do
        local start_time end_time duration_ms
        start_time=$(date +%s%N)

        if curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$ALICIA_NETWORK_TIMEOUT" "$test_url" &>/dev/null; then
            end_time=$(date +%s%N)
            duration_ms=$(( (end_time - start_time) / 1000000 ))
            total_time=$((total_time + duration_ms))
            ((success_count++))
            log_debug "  Test $i: ${duration_ms}ms"
        else
            log_debug "  Test $i: failed"
        fi
    done

    if [[ $success_count -eq 0 ]]; then
        log_error "Network speed test failed (no successful connections)"
        return 1
    fi

    local avg_time=$((total_time / success_count))
    log_info "Average response time: ${avg_time}ms (${success_count}/${iterations} successful)"
}

# network_get_public_ip - Get public IP address
network_get_public_ip() {
    local ip_services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )

    for service in "${ip_services[@]}"; do
        local ip
        ip=$(curl -s --connect-timeout 10 "$service" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo "Unknown"
    return 1
}

# network_get_local_ip - Get local IP address
network_get_local_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || \
    ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' || \
    echo "127.0.0.1"
}

# ============================================================================
# Smart Downloading
# ============================================================================

# smart_download - Download with retry, resume, and verification
smart_download() {
    local url="$1"
    local output_path="$2"
    local expected_checksum="${3:-}"
    local max_retries="${4:-$ALICIA_NETWORK_RETRIES}"
    local description="${5:-Downloading}"

    if [[ -z "$url" || -z "$output_path" ]]; then
        log_error "URL and output path are required"
        return 1
    fi

    log_info "$description: $(basename "$output_path")"

    local attempt=0
    while [[ $attempt -lt $max_retries ]]; do
        ((attempt++))
        log_info "  Attempt $attempt/$max_retries"

        if download_file "$url" "$output_path" "$description (attempt $attempt)"; then
            # Verify checksum if provided
            if [[ -n "$expected_checksum" ]]; then
                if verify_checksum "$output_path" "$expected_checksum"; then
                    log_info "Download and verification successful"
                    return 0
                else
                    log_warn "Checksum verification failed on attempt $attempt"
                    rm -f "$output_path"
                fi
            else
                log_info "Download successful (no checksum verification)"
                return 0
            fi
        fi

        if [[ $attempt -lt $max_retries ]]; then
            local delay=$((ALICIA_NETWORK_RETRY_DELAY * attempt))
            log_info "  Retrying in ${delay}s..."
            sleep "$delay"
        fi
    done

    log_error "Download failed after $max_retries attempts: $url"
    return 1
}

# ============================================================================
# SSH Server Management
# ============================================================================

# sshd_start - Start SSH server inside proot
sshd_start() {
    local port="${1:-8022}"
    log_info "Starting SSH server on port $port"

    # Generate host keys if needed
    proot_exec "$ALICIA_DISTRO_NAME" "ssh-keygen -A 2>/dev/null || true"

    # Configure SSHD
    _sshd_configure "$port"

    # Start SSHD
    proot_exec "$ALICIA_DISTRO_NAME" "/usr/sbin/sshd -p $port 2>&1" || {
        log_error "Failed to start SSH server"
        return 1
    }

    set_state "SSHD_RUNNING" "true"
    set_state "SSHD_PORT" "$port"
    log_info "SSH server started on port $port"
    return 0
}

# sshd_stop - Stop SSH server
sshd_stop() {
    log_info "Stopping SSH server..."
    proot_exec "$ALICIA_DISTRO_NAME" "pkill sshd 2>/dev/null || true"
    set_state "SSHD_RUNNING" "false"
    log_info "SSH server stopped"
}

# sshd_status - Get SSH server status
sshd_status() {
    local result
    result=$(proot_exec "$ALICIA_DISTRO_NAME" "pgrep -x sshd >/dev/null 2>&1 && echo 'running' || echo 'stopped'" 2>/dev/null)
    echo "SSH Server: $result"
}

# _sshd_configure - Configure SSHD
_sshd_configure() {
    local port="${1:-8022}"
    proot_exec "$ALICIA_DISTRO_NAME" bash -c "cat > /etc/ssh/sshd_config << SSHD_EOF
Port $port
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding yes
X11DisplayOffset 10
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
SSHD_EOF"
}

# ============================================================================
# Web Server Management (for noVNC)
# ============================================================================

# webserver_start - Start a simple web server for noVNC
webserver_start() {
    local port="${1:-6080}"
    local directory="${2:-/usr/share/novnc}"
    log_info "Starting web server on port $port"

    proot_exec "$ALICIA_DISTRO_NAME" "cd $directory && python3 -m http.server $port &" 2>/dev/null || \
    proot_exec "$ALICIA_DISTRO_NAME" "cd $directory && python -m SimpleHTTPServer $port &" 2>/dev/null || {
        log_error "Failed to start web server"
        return 1
    }

    set_state "WEBSERVER_RUNNING" "true"
    set_state "WEBSERVER_PORT" "$port"
    log_info "Web server started on port $port"
}

# webserver_stop - Stop web server
webserver_stop() {
    proot_exec "$ALICIA_DISTRO_NAME" "pkill -f 'http.server\|SimpleHTTPServer' 2>/dev/null || true"
    set_state "WEBSERVER_RUNNING" "false"
}

# ============================================================================
# DNS Configuration
# ============================================================================

# network_set_dns - Set DNS servers inside proot
network_set_dns() {
    local dns1="${1:-8.8.8.8}"
    local dns2="${2:-8.8.4.4}"

    log_info "Setting DNS servers: $dns1, $dns2"

    proot_exec "$ALICIA_DISTRO_NAME" bash -c "cat > /etc/resolv.conf << DNS_EOF
nameserver $dns1
nameserver $dns2
DNS_EOF"

    log_info "DNS servers configured"
}

# network_get_dns - Get current DNS servers
network_get_dns() {
    proot_exec "$ALICIA_DISTRO_NAME" "cat /etc/resolv.conf 2>/dev/null" || cat /etc/resolv.conf 2>/dev/null || echo "DNS configuration unavailable"
}

# ============================================================================
# Network Diagnostics
# ============================================================================

# network_ping - Ping a host
network_ping() {
    local host="${1:-8.8.8.8}"
    local count="${2:-4}"
    ping -c "$count" "$host" 2>/dev/null || proot_exec "$ALICIA_DISTRO_NAME" "ping -c $count $host" 2>/dev/null || {
        log_error "Ping failed: $host"
        return 1
    }
}

# network_traceroute - Traceroute to a host
network_traceroute() {
    local host="${1:-8.8.8.8}"
    proot_exec "$ALICIA_DISTRO_NAME" "traceroute $host 2>/dev/null || tracepath $host 2>/dev/null" || {
        log_error "Traceroute failed: $host"
        return 1
    }
}

# network_port_scan - Check if specific ports are open
network_port_scan() {
    local host="${1:-localhost}"
    local ports="${2:-22,80,443,5901,8022}"

    log_info "Scanning ports on $host: $ports"

    IFS=',' read -ra port_array <<< "$ports"
    for port in "${port_array[@]}"; do
        if (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
            echo "  Port $port: OPEN"
        else
            echo "  Port $port: CLOSED"
        fi
    done
}

# network_diagnose - Run full network diagnostics
network_diagnose() {
    log_section "Network Diagnostics"

    echo "1. Network Interfaces:"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "  Unavailable"
    echo ""

    echo "2. Default Route:"
    ip route show default 2>/dev/null || route -n 2>/dev/null || echo "  Unavailable"
    echo ""

    echo "3. DNS Configuration:"
    network_get_dns
    echo ""

    echo "4. Connectivity Test:"
    if network_is_available; then
        echo "  Internet: CONNECTED"
        echo "  Public IP: $(network_get_public_ip)"
        echo "  Local IP: $(network_get_local_ip)"
    else
        echo "  Internet: DISCONNECTED"
    fi
    echo ""

    echo "5. DNS Resolution:"
    if network_test_dns; then
        echo "  DNS: WORKING"
    else
        echo "  DNS: NOT WORKING"
    fi
    echo ""

    echo "6. Common Port Check:"
    network_port_scan localhost "22,80,443,5901,6080,8022"
}

# ============================================================================
# GitHub API Interaction
# ============================================================================

# github_check_update - Check for Alicia updates on GitHub
github_check_update() {
    local repo="${1:-proyecto-tomorrow/alicia}"
    local current_version="${2:-${ALICIA_VERSION:-3.1.0}}"

    log_info "Checking for updates: $repo"

    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local response
    response=$(curl -s --connect-timeout 15 "$api_url" 2>/dev/null) || {
        log_warn "Cannot check for updates (network error)"
        return 1
    }

    local latest_version
    latest_version=$(echo "$response" | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null | head -1)

    if [[ -z "$latest_version" ]]; then
        log_warn "Cannot determine latest version"
        return 1
    fi

    # Remove 'v' prefix if present
    latest_version="${latest_version#v}"

    if [[ "$latest_version" != "$current_version" ]]; then
        log_info "Update available: $current_version -> $latest_version"
        echo "UPDATE_AVAILABLE:$latest_version"
    else
        log_info "Alicia is up to date: v$current_version"
        echo "UP_TO_DATE:$current_version"
    fi
}

# github_download_release - Download a release asset from GitHub
github_download_release() {
    local repo="${1:-proyecto-tomorrow/alicia}"
    local version="${2:-latest}"
    local asset_pattern="${3:-alicia}"
    local output_dir="${4:-$ALICIA_DOWNLOAD_DIR}"

    log_info "Downloading release from GitHub: $repo ($version)"

    local api_url
    if [[ "$version" == "latest" ]]; then
        api_url="https://api.github.com/repos/$repo/releases/latest"
    else
        api_url="https://api.github.com/repos/$repo/releases/tags/$version"
    fi

    local response
    response=$(curl -s "$api_url" 2>/dev/null) || {
        log_error "Failed to fetch release info"
        return 1
    }

    # Extract download URL for matching asset
    local download_url
    download_url=$(echo "$response" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep "$asset_pattern" | head -1)

    if [[ -z "$download_url" ]]; then
        log_error "No matching release asset found"
        return 1
    fi

    local filename
    filename=$(basename "$download_url")
    local output_path="${output_dir}/${filename}"

    smart_download "$download_url" "$output_path" "" 3 "Downloading release asset"
}

# ============================================================================
# Hosts File Management
# ============================================================================

# network_add_host_entry - Add entry to hosts file
network_add_host_entry() {
    local ip="$1"
    local hostname="$2"

    if [[ -z "$ip" || -z "$hostname" ]]; then
        log_error "IP and hostname are required"
        return 1
    fi

    log_info "Adding hosts entry: $ip $hostname"

    # Check if entry already exists
    if proot_exec "$ALICIA_DISTRO_NAME" "grep -q '$hostname' /etc/hosts 2>/dev/null"; then
        log_debug "Host entry already exists: $hostname"
        return 0
    fi

    proot_exec "$ALICIA_DISTRO_NAME" "echo '$ip $hostname' >> /etc/hosts"
    log_info "Host entry added"
}

# network_remove_host_entry - Remove entry from hosts file
network_remove_host_entry() {
    local hostname="$1"
    if [[ -z "$hostname" ]]; then
        log_error "Hostname is required"
        return 1
    fi

    log_info "Removing hosts entry: $hostname"
    proot_exec "$ALICIA_DISTRO_NAME" "sed -i '/$hostname/d' /etc/hosts"
}

# ============================================================================
# SSL/TLS Certificate Management
# ============================================================================

# network_generate_self_signed_cert - Generate self-signed certificate
network_generate_self_signed_cert() {
    local cert_dir="${1:-/home/alicia/.alicia/certs}"
    local domain="${2:-alicia.local}"
    local days="${3:-365}"

    log_info "Generating self-signed certificate for: $domain"

    proot_exec "$ALICIA_DISTRO_NAME" bash -c "mkdir -p $cert_dir && openssl req -x509 -nodes -days $days -newkey rsa:2048 \
        -keyout ${cert_dir}/${domain}.key \
        -out ${cert_dir}/${domain}.crt \
        -subj '/CN=$domain/O=Alicia/C=DO' 2>/dev/null" || {
        log_error "Failed to generate certificate"
        return 1
    }

    log_info "Certificate generated: ${cert_dir}/${domain}.crt"
}

# ============================================================================
# Proxy Configuration
# ============================================================================

# network_set_proxy - Configure HTTP/HTTPS proxy
network_set_proxy() {
    local proxy_host="$1"
    local proxy_port="${2:-8080}"
    local no_proxy="${3:-localhost,127.0.0.1}"

    if [[ -z "$proxy_host" ]]; then
        log_error "Proxy host is required"
        return 1
    fi

    log_info "Setting proxy: $proxy_host:$proxy_port"

    export http_proxy="http://${proxy_host}:${proxy_port}"
    export https_proxy="http://${proxy_host}:${proxy_port}"
    export ftp_proxy="http://${proxy_host}:${proxy_port}"
    export no_proxy="$no_proxy"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    export FTP_PROXY="$ftp_proxy"
    export NO_PROXY="$no_proxy"

    # Also set inside proot
    proot_exec "$ALICIA_DISTRO_NAME" bash -c "cat >> /home/alicia/.bashrc << PROXY_EOF
export http_proxy='http://${proxy_host}:${proxy_port}'
export https_proxy='http://${proxy_host}:${proxy_port}'
export no_proxy='${no_proxy}'
PROXY_EOF"

    log_info "Proxy configured"
}

# network_unset_proxy - Remove proxy configuration
network_unset_proxy() {
    log_info "Removing proxy configuration"
    unset http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY 2>/dev/null || true

    proot_exec "$ALICIA_DISTRO_NAME" "sed -i '/proxy/d' /home/alicia/.bashrc" 2>/dev/null || true
}
