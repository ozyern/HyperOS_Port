#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-time dependency installer for HyperOS3-Port-lemonadep
# Maintainer: Ozyern  |  https://github.com/ozyern
# Run once:  sudo ./setup.sh
# =============================================================================
set -e

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${SELF_DIR}/bin"
mkdir -p "$BIN_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERR]${NC}   $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root: sudo ./setup.sh"

# ── Clean up Windows Zone.Identifier files (created when extracting zip on Windows) ──
log "Cleaning up Windows Zone.Identifier files..."
find "${SELF_DIR}" -name "*:Zone.Identifier" -delete 2>/dev/null || true
ok "Zone.Identifier files removed"

# ── Make all scripts executable ──────────────────────────────────────────────
log "Setting executable permissions..."
chmod +x \
    "${SELF_DIR}/port.sh" \
    "${SELF_DIR}/flash_and_fix.sh" \
    "${SELF_DIR}/functions.sh" \
    "${SELF_DIR}/payload_dumper.py" \
    "${SELF_DIR}/devices/lemonadep/patches.sh" \
    2>/dev/null || true
ok "All scripts are now executable"

echo ""
echo -e "${BOLD}HyperOS3-Port-lemonadep — Dependency Setup${NC}"
echo -e "Maintainer: ${BOLD}Ozyern${NC}  |  github.com/ozyern"
echo ""

# ──────────────────────────── APT packages ───────────────────────────────────
log "Updating apt..."
apt-get update -qq

PKGS=(
    python3 python3-pip
    unzip zip brotli
    erofs-utils           # fsck.erofs / mkfs.erofs
    e2fsprogs             # mkfs.ext4 / debugfs
    rsync
    curl wget
    android-sdk-libsparse-utils   # img2simg / simg2img
    lz4
    xxd od
    patchelf
    aapt                  # optional, for overlay inspection
)

for pkg in "${PKGS[@]}"; do
    if apt-get install -y --no-install-recommends "$pkg" &>/dev/null 2>&1; then
        ok "  $pkg installed"
    else
        warn "  $pkg — skipped (not found in apt, may not be needed)"
    fi
done

# ──────────────────────────── Python packages ────────────────────────────────
log "Installing Python packages..."
pip3 install --break-system-packages --quiet protobuf brotli 2>/dev/null || \
    pip3 install --quiet protobuf brotli 2>/dev/null || \
    warn "pip3 install failed — payload_dumper will use pure-Python fallback"

# ──────────────────────────── magiskboot ─────────────────────────────────────
if ! command -v magiskboot &>/dev/null && [[ ! -f "${BIN_DIR}/magiskboot" ]]; then
    log "Downloading magiskboot (from Magisk releases)..."
    MAGISK_URL="https://github.com/topjohnwu/Magisk/releases/latest/download/Magisk-v28.0.apk"
    TMP_APK="/tmp/magisk_tmp.apk"
    if curl -sL "$MAGISK_URL" -o "$TMP_APK" 2>/dev/null; then
        unzip -j "$TMP_APK" "lib/x86_64/libmagiskboot.so" -d /tmp 2>/dev/null || true
        unzip -j "$TMP_APK" "lib/arm64-v8a/libmagiskboot.so" -d /tmp 2>/dev/null || true
        if [[ -f "/tmp/libmagiskboot.so" ]]; then
            cp /tmp/libmagiskboot.so "${BIN_DIR}/magiskboot"
            chmod +x "${BIN_DIR}/magiskboot"
            ok "  magiskboot installed to bin/"
        else
            warn "  magiskboot extraction failed — boot patching won't work without it"
        fi
        rm -f "$TMP_APK" /tmp/libmagiskboot.so
    else
        warn "  Could not download magiskboot — install manually into bin/magiskboot"
    fi
else
    ok "  magiskboot already available"
fi

# ──────────────────────────── lpunpack ───────────────────────────────────────
if ! command -v lpunpack &>/dev/null && [[ ! -f "${BIN_DIR}/lpunpack" ]]; then
    log "Checking for lpunpack..."
    # Try apt first
    if apt-get install -y android-sdk-libsparse-utils 2>/dev/null | grep -q "lpunpack"; then
        ok "  lpunpack via apt"
    else
        warn "  lpunpack not found. If your ROM uses super.img format, download it manually"
        warn "  and place it at: ${BIN_DIR}/lpunpack"
    fi
else
    ok "  lpunpack available"
fi

# ──────────────────────────── payload-dumper-go (REQUIRED for delta OTAs) ────
log "Installing payload-dumper-go..."
if command -v payload-dumper-go &>/dev/null; then
    ok "  payload-dumper-go already available: $(command -v payload-dumper-go)"
elif [[ -f "${BIN_DIR}/payload-dumper-go" ]]; then
    ok "  payload-dumper-go found in bin/"
else
    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  PDG_ARCH="amd64" ;;
        aarch64) PDG_ARCH="arm64" ;;
        *)       PDG_ARCH="amd64" ;;
    esac

    PDG_URL="https://github.com/ssut/payload-dumper-go/releases/latest/download/payload-dumper-go_linux_${PDG_ARCH}.tar.gz"
    TMP_TGZ="/tmp/payload-dumper-go.tar.gz"

    log "  Downloading payload-dumper-go (${PDG_ARCH})..."
    if curl -sL "$PDG_URL" -o "$TMP_TGZ" 2>/dev/null && [[ -s "$TMP_TGZ" ]]; then
        tar -xzf "$TMP_TGZ" -C "$BIN_DIR" --wildcards "*/payload-dumper-go" --strip-components=1 2>/dev/null || \
            tar -xzf "$TMP_TGZ" -C "$BIN_DIR" 2>/dev/null || true
        # Some releases put the binary directly without a subdir
        find /tmp -name "payload-dumper-go" -type f 2>/dev/null | head -1 | \
            xargs -I{} cp {} "${BIN_DIR}/payload-dumper-go" 2>/dev/null || true
        chmod +x "${BIN_DIR}/payload-dumper-go" 2>/dev/null || true
        rm -f "$TMP_TGZ"

        if [[ -f "${BIN_DIR}/payload-dumper-go" ]]; then
            ok "  payload-dumper-go installed → ${BIN_DIR}/payload-dumper-go"
        else
            warn "  payload-dumper-go download failed — trying alternative URL..."
            # Try the older release naming
            PDG_URL2="https://github.com/ssut/payload-dumper-go/releases/download/1.2.2/payload-dumper-go_1.2.2_linux_${PDG_ARCH}.tar.gz"
            if curl -sL "$PDG_URL2" -o "$TMP_TGZ" 2>/dev/null && [[ -s "$TMP_TGZ" ]]; then
                tar -xzf "$TMP_TGZ" -C "$BIN_DIR" 2>/dev/null || true
                chmod +x "${BIN_DIR}/payload-dumper-go" 2>/dev/null || true
                rm -f "$TMP_TGZ"
                [[ -f "${BIN_DIR}/payload-dumper-go" ]] && \
                    ok "  payload-dumper-go installed (v1.2.2)" || \
                    warn "  payload-dumper-go install failed — delta OTAs will fail. Get it from: https://github.com/ssut/payload-dumper-go/releases"
            fi
        fi
    else
        warn "  Could not download payload-dumper-go. Get it manually from:"
        warn "  https://github.com/ssut/payload-dumper-go/releases"
        warn "  and place the binary at: ${BIN_DIR}/payload-dumper-go"
    fi
fi

# ──────────────────────────── Verify ─────────────────────────────────────────
echo ""
log "Verification:"
ALL_OK=1
for t in python3 unzip zip fsck.erofs mkfs.ext4 debugfs; do
    if command -v "$t" &>/dev/null; then
        ok "  $t → $(command -v "$t")"
    else
        warn "  $t → NOT FOUND"
        ALL_OK=0
    fi
done

echo ""
if [[ $ALL_OK -eq 1 ]]; then
    echo -e "${GREEN}${BOLD}All required tools installed successfully!${NC}"
else
    echo -e "${YELLOW}Some optional tools missing — porting may still work with fallbacks.${NC}"
fi
echo ""
echo -e "Now run:  ${BOLD}sudo ./port.sh /path/to/HyperOS3.zip /path/to/OOS14.zip${NC}"
echo ""
