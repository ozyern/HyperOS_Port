#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — setup.sh
# Dependency installer for Linux (apt), macOS (brew), and Termux
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
mkdir -p "$BIN_DIR"

detect_platform() {
    if [[ -f /data/data/com.termux/files/usr/bin/pkg ]]; then
        echo "termux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

install_debian() {
    log "Installing dependencies via apt…"
    sudo apt-get update -qq
    sudo apt-get install -y \
        git curl wget python3 python3-pip \
        p7zip-full zip unzip \
        e2fsprogs \
        xmlstarlet \
        adb fastboot \
        openjdk-17-jre-headless
    success "apt packages installed"
}

install_macos() {
    command -v brew &>/dev/null || \
        die "Homebrew not found. Install it: https://brew.sh"
    log "Installing dependencies via brew…"
    brew install \
        git python3 p7zip \
        e2fsprogs xmlstarlet \
        android-platform-tools \
        openjdk@17 || true
    success "brew packages installed"
}

install_termux() {
    log "Installing dependencies via pkg…"
    pkg update -y
    pkg install -y \
        git curl python \
        p7zip zip unzip \
        e2fsprogs xmlstarlet
    success "Termux packages installed"
}

install_python_deps() {
    log "Installing Python dependencies…"
    pip3 install --quiet --break-system-packages \
        protobuf bsdiff4 six 2>/dev/null || \
    pip3 install --quiet \
        protobuf bsdiff4 six 2>/dev/null || true
    success "Python deps installed"
}

install_payload_dumper() {
    if command -v payload-dumper-go &>/dev/null; then
        success "payload-dumper-go already installed"
        return
    fi
    log "Installing payload-dumper-go…"
    local os arch url
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "aarch64" ]] && arch="arm64"

    # Fetch latest release from GitHub
    local latest_url="https://api.github.com/repos/ssut/payload-dumper-go/releases/latest"
    url=$(curl -s "$latest_url" \
          | python3 -c "import sys,json; \
            rels=[r['browser_download_url'] for r in json.load(sys.stdin)['assets'] \
            if '${os}' in r['name'] and '${arch}' in r['name']]; \
            print(rels[0] if rels else '')" 2>/dev/null) || true

    if [[ -n "$url" ]]; then
        local tmp; tmp=$(mktemp -d)
        curl -L -o "$tmp/pd.tar.gz" "$url"
        tar -xzf "$tmp/pd.tar.gz" -C "$tmp"
        cp "$tmp/payload-dumper-go" "$BIN_DIR/" 2>/dev/null || \
            cp "$tmp"/*/payload-dumper-go "$BIN_DIR/" 2>/dev/null || true
        chmod +x "$BIN_DIR/payload-dumper-go"
        rm -rf "$tmp"
        success "payload-dumper-go installed → $BIN_DIR/"
    else
        warn "Could not auto-install payload-dumper-go."
        warn "Download manually from: https://github.com/ssut/payload-dumper-go/releases"
        warn "Place binary in: $BIN_DIR/"
    fi
}

install_android_tools() {
    log "Checking Android build tools (lpunpack, lpmake, img2simg, simg2img)…"
    local tools=(lpunpack lpmake img2simg simg2img)
    local missing=()
    for t in "${tools[@]}"; do
        command -v "$t" &>/dev/null || [[ -f "$BIN_DIR/$t" ]] || missing+=("$t")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "Android tools already in PATH"
        return
    fi

    warn "Missing Android tools: ${missing[*]}"
    warn "These come from AOSP build system or can be extracted from:"
    warn "  https://github.com/AndroidDumps/android-tools (prebuilts)"
    warn "Place binaries in: $BIN_DIR/"
    warn "Or add to PATH manually."
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════╗"
echo "  ║    HyperOS_Port  setup.sh        ║"
echo "  ╚══════════════════════════════════╝"
echo -e "${RESET}"

PLATFORM=$(detect_platform)
log "Detected platform: $PLATFORM"

case "$PLATFORM" in
    debian)     install_debian ;;
    macos)      install_macos ;;
    termux)     install_termux ;;
    redhat)     warn "Red Hat/Fedora detected — install deps manually (see README)" ;;
    *)          warn "Unknown platform — install deps manually (see README)" ;;
esac

install_python_deps
install_payload_dumper
install_android_tools

# Make project scripts executable
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}Setup complete!${RESET}"
echo -e "Run: ${CYAN}sudo ./port.sh <baserom> <portrom>${RESET}"
echo -e "     (paths or direct download URLs are both accepted)"
