#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — port.sh
# Usage: sudo ./port.sh <baserom> <portrom> [anykernel.zip]
#
#   baserom   — OxygenOS 14 for lemonadep (path or URL)
#   portrom   — HyperOS ROM from SM8350/SM8450/SM8550 device (path or URL)
#   anykernel — (optional) AnyKernel3 zip to inject a custom kernel
#
# Both ROM paths accept direct download URLs.
# Must be run as root (required for loop mounts).
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/functions.sh"
source "$SCRIPT_DIR/patches.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║          H y p e r O S _ P o r t         ║
  ║   OnePlus 9 Pro (lemonadep / SM8350)      ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ── Args ──────────────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]]  || die "Run as root (sudo ./port.sh)"
[[ $# -ge 2 ]]       || die "Usage: sudo ./port.sh <baserom> <portrom> [anykernel.zip]"

BASE_ROM_INPUT="$1"
PORT_ROM_INPUT="$2"
CUSTOM_KERNEL="${3:-}"

# ── Workspace ─────────────────────────────────────────────────────────────────
WORK="$SCRIPT_DIR/workdir"
SOURCE_DUMP="$WORK/portrom_dump"
BASE_DUMP="$WORK/baserom_dump"
MERGED="$WORK/merged"
MNT="$WORK/mnt"
OUT="$SCRIPT_DIR/output"

rm -rf "$WORK"
mkdir -p "$SOURCE_DUMP" "$BASE_DUMP" "$MERGED" "$OUT"
mkdir -p "$MNT"/{system,system_ext,product,odm_dlkm,vendor,odm}

cleanup() {
    for mnt in "$MNT"/*; do
        mountpoint -q "$mnt" 2>/dev/null && umount "$mnt" || true
    done
}
trap cleanup EXIT

check_tools

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 1 — Resolve & extract ROMs"
# ═════════════════════════════════════════════════════════════════════════════

BASE_ROM=$(resolve_rom "$BASE_ROM_INPUT" "OxygenOS" "$WORK/downloads")
PORT_ROM=$(resolve_rom "$PORT_ROM_INPUT" "HyperOS"  "$WORK/downloads")

extract_rom "$PORT_ROM" "$SOURCE_DUMP" "HyperOS"
extract_rom "$BASE_ROM" "$BASE_DUMP"   "OxygenOS"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 2 — Validate source architecture"
# ═════════════════════════════════════════════════════════════════════════════

validate_source_arch "$SOURCE_DUMP"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 3 — Prepare partition images"
# ═════════════════════════════════════════════════════════════════════════════

log "Staging HyperOS partitions (skipping missing ones)…"
for part in "${PORTROM_PARTITIONS[@]}"; do
    src="$SOURCE_DUMP/${part}.img"
    if [[ -f "$src" ]]; then
        cp "$src" "$MERGED/${part}.img"
        success "  ✓ $part"
    else
        warn "  - $part (not found in source — skipping)"
    fi
done

log "Staging OxygenOS vendor partitions…"
for part in "${BASEROM_PARTITIONS[@]}"; do
    src="$BASE_DUMP/${part}.img"
    if [[ -f "$src" ]]; then
        cp "$src" "$MERGED/${part}.img"
        success "  ✓ $part (from OxygenOS)"
    else
        warn "  - $part (not in base ROM)"
    fi
done

log "Staging boot images from OxygenOS…"
for img in "${BASE_BOOT_IMAGES[@]}"; do
    src="$BASE_DUMP/${img}.img"
    if [[ -f "$src" ]]; then
        cp "$src" "$MERGED/${img}.img"
        success "  ✓ ${img}.img"
    else
        warn "  - ${img}.img (not found — flash manually)"
    fi
done

# vbmeta family (AVB). Not strictly required but improves boot success.
for img in vbmeta vbmeta_system; do
    src="$BASE_DUMP/${img}.img"
    if [[ -f "$src" ]]; then
        cp "$src" "$MERGED/${img}.img"
        success "  ✓ ${img}.img"
    else
        warn "  - ${img}.img (not found — AVB may block boot if not flashed)"
    fi
done

# Optional: custom kernel injection
if [[ -n "$CUSTOM_KERNEL" ]]; then
    inject_anykernel "$CUSTOM_KERNEL" "$MERGED/boot.img"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 4 — Mount partitions"
# ═════════════════════════════════════════════════════════════════════════════

for part in system system_ext product odm_dlkm vendor odm; do
    [[ -f "$MERGED/${part}.img" ]] && mount_partition "$MERGED/${part}.img" "$MNT/$part"
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 5 — HyperOS cleanup"
# ═════════════════════════════════════════════════════════════════════════════

remove_hyperos_junk "$MNT"
handle_mi_ext "$SOURCE_DUMP" "$MNT/system_ext"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 6 — Apply patches"
# ═════════════════════════════════════════════════════════════════════════════

apply_all_patches "$WORK"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 7 — Apply device overlay"
# ═════════════════════════════════════════════════════════════════════════════

apply_overlay "$MNT"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 8 — Unmount & finalise"
# ═════════════════════════════════════════════════════════════════════════════

for part in system system_ext product odm_dlkm vendor odm; do
    mountpoint -q "$MNT/$part" 2>/dev/null && unmount_partition "$MNT/$part" || true
done
for part in system system_ext product odm_dlkm vendor odm; do
    [[ -f "$MERGED/${part}.img" ]] && { e2fsck -fy "$MERGED/${part}.img" 2>/dev/null || true; }
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 9 — Pack super.img"
# ═════════════════════════════════════════════════════════════════════════════

pack_super "$MERGED" "$OUT"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 10 — Build flashable zip"
# ═════════════════════════════════════════════════════════════════════════════

for img in "${BASE_BOOT_IMAGES[@]}" vbmeta vbmeta_system; do
    [[ -f "$MERGED/${img}.img" ]] && cp "$MERGED/${img}.img" "$OUT/" || true
done

VERSION=$(get_version_string "$SOURCE_DUMP")
build_flashable_zip "$OUT" "$OUT" "$VERSION"

# ═════════════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Build complete!${RESET}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Output: ${CYAN}$OUT/${RESET}"
echo -e "  Zip:    ${CYAN}HyperOS_Port_lemonadep_${VERSION}.zip${RESET}"
echo ""
echo -e "${YELLOW}Flash via fastboot:${RESET}"
echo "  adb reboot fastboot"
echo "  fastboot --disable-verity --disable-verification flash vbmeta         output/vbmeta.img"
echo "  fastboot --disable-verity --disable-verification flash vbmeta_system  output/vbmeta_system.img"
echo "  fastboot reboot fastboot    # enter fastbootd for logical partitions"
echo "  fastboot flash super        output/super.img"
echo "  fastboot flash boot         output/boot.img"
echo "  fastboot flash vendor_boot  output/vendor_boot.img"
echo "  fastboot flash dtbo         output/dtbo.img"
echo "  fastboot -w && fastboot reboot"
echo ""
echo -e "${YELLOW}Or sideload the zip via TWRP/OrangeFox (wipe data first).${RESET}"
