#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — port.sh
# Main orchestrator: HyperOS source + OxygenOS vendor → OnePlus 9 Pro ROM
#
# Usage:
#   SOURCE_ROM_ZIP=/path/to/hyperos_alioth.zip \
#   BASE_ROM_ZIP=/path/to/oxygenos14_lemonadep.zip \
#   sudo ./port.sh
#
# Requirements: payload_dumper, lpunpack, lpmake, img2simg, simg2img,
#               resize2fs, e2fsck, 7z, python3, xmlstarlet, zip
# Must be run as root (for loop mounts)
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/functions.sh"
source "$SCRIPT_DIR/patches.sh"

# ── Validate environment ──────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || die "Must run as root (required for loop mounts)"
[[ -n "${SOURCE_ROM_ZIP:-}" ]] || die "SOURCE_ROM_ZIP not set"
[[ -n "${BASE_ROM_ZIP:-}"   ]] || die "BASE_ROM_ZIP not set"
[[ -f "$SOURCE_ROM_ZIP"     ]] || die "Source ROM not found: $SOURCE_ROM_ZIP"
[[ -f "$BASE_ROM_ZIP"       ]] || die "Base ROM not found: $BASE_ROM_ZIP"

check_tools

# ── Workspace setup ───────────────────────────────────────────────────────────
WORK="$SCRIPT_DIR/workdir"
SOURCE_DUMP="$WORK/source_dump"   # HyperOS extracted partitions
BASE_DUMP="$WORK/base_dump"       # OxygenOS extracted partitions
MERGED="$WORK/merged"             # Working merged images
MNT="$WORK/mnt"                   # Mount points
OUT="$SCRIPT_DIR/output"          # Final output

rm -rf "$WORK"
mkdir -p "$SOURCE_DUMP" "$BASE_DUMP" "$MERGED" "$OUT"
mkdir -p "$MNT"/{system,system_ext,product,odm_dlkm,vendor,odm}

VERSION=$(date +%Y%m%d)

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
    log "Cleaning up mount points…"
    for mnt in "$MNT"/*; do
        mountpoint -q "$mnt" && umount "$mnt" 2>/dev/null || true
    done
}
trap cleanup EXIT

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 1 — Extract ROMs"
# ═════════════════════════════════════════════════════════════════════════════

extract_rom "$SOURCE_ROM_ZIP" "$SOURCE_DUMP" "HyperOS"
extract_rom "$BASE_ROM_ZIP"   "$BASE_DUMP"   "OxygenOS"

# Verify expected partitions exist
for part in "${HYPEROS_PARTITIONS[@]}"; do
    [[ -f "$SOURCE_DUMP/${part}.img" ]] || \
        die "Missing HyperOS partition: ${part}.img (check SOURCE_DEVICE compatibility)"
done
for part in "${BASE_PARTITIONS[@]}"; do
    [[ -f "$BASE_DUMP/${part}.img" ]] || \
        die "Missing OxygenOS partition: ${part}.img"
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 2 — Prepare partition images"
# ═════════════════════════════════════════════════════════════════════════════

# Copy HyperOS partitions → workdir
log "Preparing HyperOS partitions"
for part in "${HYPEROS_PARTITIONS[@]}"; do
    cp "$SOURCE_DUMP/${part}.img" "$MERGED/${part}.img"
done

# Copy OxygenOS vendor partitions → workdir
log "Preparing OxygenOS vendor partitions"
for part in "${BASE_PARTITIONS[@]}"; do
    cp "$BASE_DUMP/${part}.img" "$MERGED/${part}.img"
done

# Boot images always from OxygenOS (kernel + vendor_boot must match hardware)
log "Using OxygenOS boot images (kernel must match hardware)"
for img in "${BASE_BOOT_IMAGES[@]}"; do
    src="$BASE_DUMP/${img}.img"
    if [[ -f "$src" ]]; then
        cp "$src" "$MERGED/${img}.img"
        success "Boot image: ${img}.img from OxygenOS base"
    else
        warn "Boot image not found: ${img}.img — flash manually"
    fi
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 3 — Mount partitions"
# ═════════════════════════════════════════════════════════════════════════════

for part in "${HYPEROS_PARTITIONS[@]}" "${BASE_PARTITIONS[@]}"; do
    mount_partition "$MERGED/${part}.img" "$MNT/$part"
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 4 — HyperOS cleanup & mi_ext merge"
# ═════════════════════════════════════════════════════════════════════════════

remove_hyperos_junk "$MNT"
handle_mi_ext "$SOURCE_DUMP" "$MNT/system_ext"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 5 — Apply patches"
# ═════════════════════════════════════════════════════════════════════════════

apply_all_patches "$WORK"
install_compat_shims "$MNT/system"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 6 — Unmount & finalise images"
# ═════════════════════════════════════════════════════════════════════════════

log "Unmounting partitions"
for part in "${HYPEROS_PARTITIONS[@]}" "${BASE_PARTITIONS[@]}"; do
    unmount_partition "$MNT/$part"
done

# Run e2fsck on all modified images
log "Running e2fsck on merged images"
for part in "${HYPEROS_PARTITIONS[@]}" "${BASE_PARTITIONS[@]}"; do
    e2fsck -fy "$MERGED/${part}.img" 2>/dev/null || true
done

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 7 — Pack super.img"
# ═════════════════════════════════════════════════════════════════════════════

pack_super "$MERGED" "$OUT"

# ═════════════════════════════════════════════════════════════════════════════
step "PHASE 8 — Build flashable zip"
# ═════════════════════════════════════════════════════════════════════════════

# Stage boot images
for img in "${BASE_BOOT_IMAGES[@]}"; do
    [[ -f "$MERGED/${img}.img" ]] && cp "$MERGED/${img}.img" "$OUT/"
done

build_flashable_zip "$OUT" "$OUT" "$VERSION"

# ═════════════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  HyperOS_Port build complete!${RESET}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Output: ${CYAN}$OUT/${RESET}"
echo -e "  Zip:    ${CYAN}HyperOS_Port_lemonadep_${VERSION}.zip${RESET}"
echo -e ""
echo -e "${YELLOW}Flash instructions:${RESET}"
echo -e "  1. Boot to fastboot: adb reboot fastboot"
echo -e "  2. fastboot flash super output/super.img"
echo -e "  3. fastboot flash boot output/boot.img"
echo -e "  4. fastboot flash vendor_boot output/vendor_boot.img"
echo -e "  5. fastboot flash dtbo output/dtbo.img"
echo -e "  6. fastboot -w  (wipe userdata)"
echo -e "  7. fastboot reboot"
echo -e ""
echo -e "${YELLOW}Or use TWRP/OrangeFox to sideload the zip.${RESET}"
