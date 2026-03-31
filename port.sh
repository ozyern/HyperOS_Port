#!/usr/bin/env bash
# =============================================================================
# port.sh — HyperOS 3 → OnePlus 9 Pro (lemonadep) ROM porter
#
#   Usage:  sudo ./port.sh <hyperos3.zip> <oos14.zip> [out_dir]
#
#   <hyperos3.zip>  — HyperOS 3 source ROM  (recovery OTA or fastboot)
#   <oos14.zip>     — OxygenOS 14 base ROM   (recovery OTA or fastboot)
#   [out_dir]       — Output directory        (default: ./out)
#
# Maintainer : Ozyern  |  https://github.com/ozyern
# Device     : OnePlus 9 Pro (lemonadep / lahaina)
# Target     : HyperOS 3 (Android 16)
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SELF_DIR}/functions.sh"
source "${SELF_DIR}/devices/lemonadep/patches.sh"

# ──────────────────────────── Args ───────────────────────────────────────────
HYPEROS_ZIP="${1:-}"
OOS_ZIP="${2:-}"
OUT_DIR="${3:-${SELF_DIR}/out}"
VERBOSE="${VERBOSE:-0}"

banner

if [[ -z "$HYPEROS_ZIP" || -z "$OOS_ZIP" ]]; then
    echo -e "Usage:  ${BOLD}sudo ./port.sh <hyperos3.zip> <oos14.zip> [out_dir]${NC}"
    echo ""
    echo "  hyperos3.zip  — HyperOS 3 source ROM (recovery OTA or fastboot ZIP)"
    echo "  oos14.zip     — OxygenOS 14 base ROM  (recovery OTA or fastboot ZIP)"
    echo "  out_dir       — Output directory (default: ./out)"
    echo ""
    exit 1
fi

require_root

[[ -f "$HYPEROS_ZIP" ]] || die "HyperOS3 ZIP not found: $HYPEROS_ZIP"
[[ -f "$OOS_ZIP"     ]] || die "OOS14 ZIP not found:    $OOS_ZIP"

# ──────────────────────────── Directories ────────────────────────────────────
WORK_DIR="${OUT_DIR}/.work"
HYPEROS_WORK="${WORK_DIR}/hyperos_extracted"
OOS_WORK="${WORK_DIR}/oos_extracted"
PORT_DIR="${WORK_DIR}/port"
FLASHABLE_DIR="${OUT_DIR}/flashable"
FASTBOOT_DIR="${OUT_DIR}/fastboot_rom"
FASTBOOT_IMG_DIR="${FASTBOOT_DIR}/images"
DATE_TAG=$(date +%Y%m%d_%H%M)

mkdir -p "$OUT_DIR" "$WORK_DIR" "$HYPEROS_WORK" "$OOS_WORK" "$PORT_DIR" "$FLASHABLE_DIR" "$FASTBOOT_IMG_DIR"

LOG_FILE="${OUT_DIR}/port_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "HyperOS3 ROM : $HYPEROS_ZIP"
log_info "OOS14 ROM    : $OOS_ZIP"
log_info "Output       : $OUT_DIR"
log_info "Log          : $LOG_FILE"
is_wsl && log_warn "Running in WSL — mount-based extraction disabled (using userspace tools)"

# ──────────────────────────── Step 1: Check tools ────────────────────────────
check_all_tools

# Extra sanity: refuse delta OTAs early (payload_properties with SOURCE_*)
if unzip -p "$HYPEROS_ZIP" payload_properties.txt 2>/dev/null | grep -q "SOURCE_"; then
    die "HyperOS ZIP appears to be an incremental OTA (payload_properties contains SOURCE_*). Use a full OTA."
fi
if unzip -p "$OOS_ZIP" payload_properties.txt 2>/dev/null | grep -q "SOURCE_"; then
    die "OOS14 ZIP appears to be an incremental OTA (payload_properties contains SOURCE_*). Use a full OTA."
fi

# ──────────────────────────── Step 2: Extract ROMs ───────────────────────────
log_step "Step 2/10 — Extracting ROMs"

if [[ -d "${HYPEROS_WORK}/system" ]] && [[ "$(ls "${HYPEROS_WORK}" | wc -l)" -gt 2 ]]; then
    log_warn "  HyperOS already extracted — skipping (delete ${HYPEROS_WORK} to re-extract)"
else
    log_info "  Extracting HyperOS 3..."
    extract_rom "hyperos" "$HYPEROS_ZIP" "$HYPEROS_WORK"
fi

if [[ -d "${OOS_WORK}/vendor" ]] && [[ "$(ls "${OOS_WORK}" | wc -l)" -gt 2 ]]; then
    log_warn "  OOS14 already extracted — skipping"
else
    log_info "  Extracting OxygenOS 14..."
    extract_rom "oos" "$OOS_ZIP" "$OOS_WORK"
fi

# ──────────────────────────── Step 3: Extract partition images ───────────────
log_step "Step 3/10 — Extracting partition images into filesystems"

PARTITIONS_HYPEROS=(system system_ext product)
PARTITIONS_OOS=(vendor odm)

for part in "${PARTITIONS_HYPEROS[@]}"; do
    dest="${PORT_DIR}/${part}"
    if [[ -d "$dest" && "$(find "$dest" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]]; then
        log_warn "  ${part}: already extracted, skipping"
        continue
    fi
    img="${HYPEROS_WORK}/${part}.img"
    if [[ ! -f "$img" ]]; then
        img=$(find "$HYPEROS_WORK" -name "${part}.img" 2>/dev/null | head -1)
    fi
    if [[ -z "$img" || ! -f "$img" ]]; then
        log_warn "  ${part}.img not found in HyperOS extraction — skipping"
        continue
    fi
    log_info "  Extracting HyperOS ${part}..."
    set +e
    extract_img "$img" "$dest"
    local_rc=$?
    set -e
    if [[ $local_rc -ne 0 ]]; then
        # Double-check: did we actually get files?
        local fc
        fc=$(find "$dest" -type f 2>/dev/null | wc -l)
        if [[ $fc -gt 10 ]]; then
            log_ok "  ${part}: extracted $fc files (exit code ignored)"
        else
            log_warn "  ${part} extraction may have issues ($fc files found)"
        fi
    fi
done

for part in "${PARTITIONS_OOS[@]}"; do
    dest="${PORT_DIR}/${part}"
    if [[ -d "$dest" && "$(find "$dest" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]]; then
        log_warn "  ${part}: already extracted, skipping"
        continue
    fi
    img=$(find "$OOS_WORK" -name "${part}.img" 2>/dev/null | head -1)
    if [[ -z "$img" || ! -f "$img" ]]; then
        log_warn "  ${part}.img not found in OOS14 extraction — skipping"
        continue
    fi
    log_info "  Extracting OOS14 ${part}..."
    set +e
    extract_img "$img" "$dest"
    local_rc=$?
    set -e
    if [[ $local_rc -ne 0 ]]; then
        local fc
        fc=$(find "$dest" -type f 2>/dev/null | wc -l)
        if [[ $fc -gt 10 ]]; then
            log_ok "  ${part}: extracted $fc files (exit code ignored)"
        else
            log_warn "  ${part} extraction may have issues ($fc files found)"
        fi
    fi
done

# Also grab boot/init_boot images for later patching
for img_name in boot init_boot vendor_boot; do
    src=$(find "$OOS_WORK" -name "${img_name}.img" 2>/dev/null | head -1)
    [[ -n "$src" ]] && cp -f "$src" "${PORT_DIR}/${img_name}.img" && \
        log_info "  Saved ${img_name}.img from OOS14"
done

# ──────────────────────────── Step 4-10: Apply patches ───────────────────────
log_step "Step 4/10 — Applying device patches"

# Temporarily relax strict exit so individual patch failures don't abort the port
set +e
OOS_VENDOR_DIR="${PORT_DIR}/vendor"
run_all_patches "$PORT_DIR" "$OOS_VENDOR_DIR"
set -e

# ──────────────────────────── Step 5: Patch boot image ───────────────────────
log_step "Step 5/10 — Patching boot image"

BOOT_IMG="${PORT_DIR}/boot.img"
INIT_BOOT_IMG="${PORT_DIR}/init_boot.img"
BOOT_WORK="${WORK_DIR}/boot_work"

if [[ -f "$BOOT_IMG" ]] && command -v magiskboot &>/dev/null; then
    mkdir -p "$BOOT_WORK"
    cp "$BOOT_IMG" "${BOOT_WORK}/boot.img"
    ( cd "$BOOT_WORK" && magiskboot unpack boot.img ) && {
        # Keep OOS14 kernel, swap in HyperOS ramdisk if available
        HOS_RAMDISK=$(find "$HYPEROS_WORK" -name "ramdisk.cpio.gz" -o -name "ramdisk.cpio" 2>/dev/null | head -1)
        if [[ -n "$HOS_RAMDISK" ]]; then
            cp "$HOS_RAMDISK" "${BOOT_WORK}/ramdisk.cpio"
            log_info "  HyperOS ramdisk injected"
        fi
        ( cd "$BOOT_WORK" && magiskboot repack boot.img ) && \
            cp "${BOOT_WORK}/new-boot.img" "${FLASHABLE_DIR}/boot.img" && \
            log_ok "  boot.img repacked"
    } || log_warn "  Boot image repack failed — using original OOS14 boot"
    [[ ! -f "${FLASHABLE_DIR}/boot.img" ]] && cp "$BOOT_IMG" "${FLASHABLE_DIR}/boot.img"
else
    [[ -f "$BOOT_IMG" ]] && cp "$BOOT_IMG" "${FLASHABLE_DIR}/boot.img"
    log_warn "  magiskboot not found — boot.img copied as-is"
fi

if [[ "${KSU:-0}" == "1" ]]; then
    log_warn "  KSU=1 requested but KernelSU injection is not wired in this porter yet (skipping)"
fi

[[ -f "${FLASHABLE_DIR}/boot.img" ]] && cp "${FLASHABLE_DIR}/boot.img" "${FASTBOOT_IMG_DIR}/boot.img"
[[ -f "$INIT_BOOT_IMG" ]] && { cp "$INIT_BOOT_IMG" "${FLASHABLE_DIR}/init_boot.img"; cp "$INIT_BOOT_IMG" "${FASTBOOT_IMG_DIR}/init_boot.img"; }

# ──────────────────────────── Step 6: Repack images ─────────────────────────
log_step "Step 6/10 — Repacking partition images"

# Use original filesystem type when possible; fallback to erofs
for part in system system_ext product vendor odm; do
    src="${PORT_DIR}/${part}"
    out_img="${FLASHABLE_DIR}/${part}.img"
    [[ -d "$src" ]] || { log_warn "  Skipping $part (dir missing)"; continue; }

    # Detect filesystem from source image (HyperOS for system*, OOS for vendor/odm)
    orig_img=""
    if [[ "$part" == "system" || "$part" == "system_ext" || "$part" == "product" ]]; then
        orig_img=$(find "$HYPEROS_WORK" -name "${part}.img" 2>/dev/null | head -1)
    else
        orig_img=$(find "$OOS_WORK" -name "${part}.img" 2>/dev/null | head -1)
    fi

    fs_type="erofs"
    [[ -f "$orig_img" ]] && fs_type=$(detect_fs "$orig_img")
    [[ "$fs_type" == "unknown" ]] && fs_type="erofs"

    repack_img "$src" "$out_img" "$fs_type" "$part" || log_warn "  $part repack failed"
    cp -f "$out_img" "${FASTBOOT_IMG_DIR}/${part}.img" 2>/dev/null || true
done

# ──────────────────────────── Step 6b: Super size guard (best-effort) ───────
if command -v lpdump &>/dev/null; then
    SUPER_IMG=""
    SUPER_IMG=$(find "$HYPEROS_WORK" "$OOS_WORK" -maxdepth 2 -name "super.img" 2>/dev/null | head -1)
    if [[ -n "$SUPER_IMG" ]]; then
        log_step "Step 6b — Checking super partition capacity"
        python3 - "$SUPER_IMG" "$FASTBOOT_IMG_DIR" << 'PY'
import json, subprocess, sys, os
super_img, imgs_dir = sys.argv[1], sys.argv[2]

def run(cmd):
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return out
    except Exception:
        return b""

meta = run(["lpdump", "-j", super_img])
if not meta:
    print("[WARN] lpdump could not parse super.img — skipping size guard")
    sys.exit(0)

try:
    data = json.loads(meta)
except Exception:
    print("[WARN] lpdump JSON parse failed — skipping size guard")
    sys.exit(0)

groups = data.get("groups", [])
if not groups:
    print("[WARN] No groups in lpdump — skipping size guard")
    sys.exit(0)

budget = max((g.get("maximum_size", 0) for g in groups), default=0)
if budget <= 0:
    print("[WARN] No usable group size — skipping size guard")
    sys.exit(0)

need = 0
for part in ("system","system_ext","product","vendor","odm"):
    p = os.path.join(imgs_dir, f"{part}.img")
    if os.path.isfile(p):
        need += os.path.getsize(p)

if need == 0:
    print("[WARN] No partition images found for size check")
    sys.exit(0)

ratio = need / budget if budget else 0
print(f"[INFO] Super size guard: need={need/1_048_576:.1f} MiB, budget={budget/1_048_576:.1f} MiB, usage={ratio*100:.1f}%")
if ratio > 0.98:
    print("[ERR] Repacked images exceed super group capacity. Consider trimming or switching pack type.")
    sys.exit(1)
elif ratio > 0.92:
    print("[WARN] Repacked images are close to super capacity (>92%). Flash may fail if partitions expand further.")
PY
        if [[ $? -ne 0 ]]; then
            die "Super size check failed — images likely too large for dynamic partitions"
        fi
    fi
fi

# ──────────────────────────── Step 7: Copy other images ──────────────────────
log_step "Step 7/10 — Copying remaining images"

for img_name in vendor_boot dtbo vbmeta vbmeta_system; do
    src=$(find "$OOS_WORK" -name "${img_name}.img" 2>/dev/null | head -1)
    if [[ -n "$src" ]]; then
        cp -f "$src" "${FLASHABLE_DIR}/${img_name}.img"
        cp -f "$src" "${FASTBOOT_IMG_DIR}/${img_name}.img"
        log_ok "  Copied ${img_name}.img from OOS14"
    fi
done

# ──────────────────────────── Step 8: Write flash scripts ────────────────────
log_step "Step 8/10 — Generating flash scripts"

cat > "${FLASHABLE_DIR}/flash_auto.sh" << 'FLASH'
#!/usr/bin/env bash
# =============================================================================
# flash_auto.sh — HyperOS 3 for OnePlus 9 Pro (lemonadep)
# Generated by HyperOS3-Port-lemonadep  |  Maintainer: Ozyern
#
#   Usage:  ./flash_auto.sh [--slot a|b] [--wipe-data] [--dry-run]
#
# Device must be in bootloader/fastboot mode before running.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${BLUE}[flash]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERR]${NC}   $*" >&2; exit 1; }

SLOT="a"
WIPE_DATA=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slot)    SLOT="$2"; shift 2 ;;
        --slot=*)  SLOT="${1#*=}"; shift ;;
        --wipe-data) WIPE_DATA=1; shift ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)
            echo "Usage: ./flash_auto.sh [--slot a|b] [--wipe-data] [--dry-run]"
            exit 0 ;;
        *) warn "Unknown arg: $1"; shift ;;
    esac
done

[[ "$SLOT" != "a" && "$SLOT" != "b" ]] && die "Invalid slot: $SLOT (must be a or b)"

FLASH_DIR="$(cd "$(dirname "$0")" && pwd)"
FB="fastboot"

run_fb() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] fastboot $*"
    else
        "$FB" "$@" || { warn "fastboot $* returned non-zero (may be OK)"; }
    fi
}

echo ""
echo -e "${BOLD}HyperOS 3 — OnePlus 9 Pro Flash Script${NC}"
echo -e "Maintainer: ${BOLD}Ozyern${NC}  |  Slot: ${BOLD}_${SLOT}${NC}"
[[ $DRY_RUN -eq 1 ]] && echo -e "${YELLOW}DRY-RUN MODE — nothing will be flashed${NC}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
log "Checking fastboot connection..."
if [[ $DRY_RUN -eq 0 ]]; then
    "$FB" devices | grep -q "fastboot" || die "No device found in fastboot mode"
fi
ok "Device detected"

# ── Disable AVB ───────────────────────────────────────────────────────────────
log "Disabling AVB verification..."
run_fb oem disable-verification 2>/dev/null || true
run_fb flashing unlock 2>/dev/null || true

# ── Flash vbmeta with disabled verification ────────────────────────────────────
if [[ -f "${FLASH_DIR}/vbmeta.img" ]]; then
    log "Flashing vbmeta (disable-verity + disable-verification)..."
    run_fb --disable-verity --disable-verification flash vbmeta_"${SLOT}" "${FLASH_DIR}/vbmeta.img"
fi
if [[ -f "${FLASH_DIR}/vbmeta_system.img" ]]; then
    run_fb --disable-verity --disable-verification flash vbmeta_system_"${SLOT}" "${FLASH_DIR}/vbmeta_system.img"
fi

# ── Reboot to fastbootd for logical partitions ────────────────────────────────
log "Rebooting to fastbootd..."
run_fb reboot fastboot
if [[ $DRY_RUN -eq 0 ]]; then
    sleep 8
    "$FB" devices | grep -q "fastboot" || { warn "fastbootd not detected, continuing anyway..."; sleep 5; }
fi

# ── Delete and recreate logical partitions ────────────────────────────────────
log "Recreating logical partitions..."
for part in system system_ext product vendor odm; do
    run_fb delete-logical-partition "${part}_a" 2>/dev/null || true
    run_fb delete-logical-partition "${part}_b" 2>/dev/null || true
done

# ── Flash logical partitions ──────────────────────────────────────────────────
log "Flashing partitions to slot _${SLOT}..."
LOGICAL_PARTS=(system system_ext product vendor odm)

for part in "${LOGICAL_PARTS[@]}"; do
    img="${FLASH_DIR}/${part}.img"
    if [[ -f "$img" ]]; then
        SIZE=$(wc -c < "$img")
        run_fb create-logical-partition "${part}_${SLOT}" "$SIZE" 2>/dev/null || true
        run_fb flash "${part}_${SLOT}" "$img"
        ok "  Flashed ${part}_${SLOT} ($(du -sh "$img" | cut -f1))"
    else
        warn "  ${part}.img not found — skipping"
    fi
done

# ── Flash raw partitions ──────────────────────────────────────────────────────
log "Flashing boot partitions..."
for part in boot init_boot vendor_boot dtbo; do
    img="${FLASH_DIR}/${part}.img"
    if [[ -f "$img" ]]; then
        run_fb flash "${part}_${SLOT}" "$img"
        ok "  Flashed ${part}_${SLOT}"
    fi
done

# ── Wipe data ─────────────────────────────────────────────────────────────────
if [[ $WIPE_DATA -eq 1 ]]; then
    warn "Wiping userdata..."
    run_fb -w
    ok "  Userdata wiped"
fi

# ── Set active slot ───────────────────────────────────────────────────────────
log "Setting active slot to _${SLOT}..."
run_fb set_active "$SLOT"

# ── Reboot ────────────────────────────────────────────────────────────────────
log "Rebooting to system..."
run_fb reboot

echo ""
ok "Flash complete! First boot may take 3-5 minutes."
echo -e "${YELLOW}Note: If device bootloops, run flash_and_fix.sh for automatic repair.${NC}"
echo ""
FLASH

chmod +x "${FLASHABLE_DIR}/flash_auto.sh"
log_ok "flash_auto.sh generated"

cat > "${FASTBOOT_DIR}/flash_fastboot.sh" << 'FAST'
#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[fastboot]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

IMAGES_DIR="$(cd "$(dirname "$0")" && pwd)/images"
FB="${FB:-fastboot}"
SLOT="${SLOT:-a}"

[[ "$SLOT" == "a" || "$SLOT" == "b" ]] || die "Invalid slot: $SLOT"

log "Flashing HyperOS 3 fastboot ROM → slot _${SLOT}"
$FB devices | grep -q "fastboot" || die "No device detected in fastboot mode"

log "Disabling AVB and flashing vbmeta"
for part in vbmeta vbmeta_system; do
    img="${IMAGES_DIR}/${part}.img"
    [[ -f "$img" ]] || continue
    $FB --disable-verity --disable-verification flash "${part}_${SLOT}" "$img" || warn "${part} flash returned non-zero"
done

log "Rebooting to fastbootd"
$FB reboot fastboot
sleep 6

log "Flashing logical partitions"
for part in system system_ext product vendor odm; do
    img="${IMAGES_DIR}/${part}.img"
    [[ -f "$img" ]] || { warn "  ${part}.img missing"; continue; }
    size=$(wc -c < "$img")
    $FB delete-logical-partition "${part}_a" 2>/dev/null || true
    $FB delete-logical-partition "${part}_b" 2>/dev/null || true
    $FB create-logical-partition "${part}_${SLOT}" "$size" 2>/dev/null || true
    $FB flash "${part}_${SLOT}" "$img"
done

log "Flashing bootable partitions"
for part in boot init_boot vendor_boot dtbo; do
    img="${IMAGES_DIR}/${part}.img"
    [[ -f "$img" ]] || continue
    $FB flash "${part}_${SLOT}" "$img"
done

log "Setting active slot"
$FB set_active "$SLOT"
ok "Flashing complete — rebooting"
$FB reboot
FAST
chmod +x "${FASTBOOT_DIR}/flash_fastboot.sh"

cat > "${FASTBOOT_DIR}/flash_fastboot.bat" << 'BAT'
@echo off
setlocal
set FB=fastboot
set SLOT=a
if not "%1"=="" set SLOT=%1
set IMAGES=%~dp0images

echo HyperOS 3 fastboot flash (slot _%SLOT%)
%FB% devices | find "fastboot" >NUL || (
  echo No device detected in fastboot mode
  exit /b 1
)

echo Disabling AVB and flashing vbmeta
if exist "%IMAGES%\vbmeta.img" %FB% --disable-verity --disable-verification flash vbmeta_%SLOT% "%IMAGES%\vbmeta.img"
if exist "%IMAGES%\vbmeta_system.img" %FB% --disable-verity --disable-verification flash vbmeta_system_%SLOT% "%IMAGES%\vbmeta_system.img"

echo Rebooting to fastbootd
%FB% reboot fastboot
timeout /t 6 >nul

echo Flashing logical partitions
for %%p in (system system_ext product vendor odm) do (
  if exist "%IMAGES%\%%p.img" (
    %FB% delete-logical-partition %%p_a 2>nul
    %FB% delete-logical-partition %%p_b 2>nul
    for /f %%s in ('powershell -nologo -command "(Get-Item \"%IMAGES%\\%%p.img\").Length"') do set SIZE=%%s
    %FB% create-logical-partition %%p_%SLOT% %SIZE% 2>nul
    %FB% flash %%p_%SLOT% "%IMAGES%\%%p.img"
  ) else (
    echo Skipping %%p.img (missing)
  )
)

echo Flashing bootable partitions
for %%p in (boot init_boot vendor_boot dtbo) do (
  if exist "%IMAGES%\%%p.img" %FB% flash %%p_%SLOT% "%IMAGES%\%%p.img"
)

echo Setting active slot
%FB% set_active %SLOT%
echo Done. Rebooting...
%FB% reboot
BAT

log_ok "flash_fastboot.sh and flash_fastboot.bat generated"

# ──────────────────────────── Step 9: Prepare fastboot ROM dir ───────────────
log_step "Step 9/10 — Preparing fastboot ROM layout"
cp -af "${FLASHABLE_DIR}"/*.img "${FASTBOOT_IMG_DIR}/" 2>/dev/null || true
log_ok "Fastboot ROM ready at ${FASTBOOT_DIR}"

# ──────────────────────────── Step 10: Package output ───────────────────────
log_step "Step 10/10 — Packaging output"

OUTPUT_ZIP="${OUT_DIR}/HyperOS3_OOS14_lemonadep_by_Ozyern_${DATE_TAG}.zip"
FASTBOOT_ZIP="${OUT_DIR}/HyperOS3_OOS14_lemonadep_fastboot_${DATE_TAG}.zip"
( cd "$FLASHABLE_DIR" && zip -r9 "$OUTPUT_ZIP" . ) && \
    log_ok "Output ZIP: $OUTPUT_ZIP ($(du -sh "$OUTPUT_ZIP" | cut -f1))"
( cd "$FASTBOOT_DIR" && zip -r9 "$FASTBOOT_ZIP" . ) && \
    log_ok "Fastboot ZIP: $FASTBOOT_ZIP ($(du -sh "$FASTBOOT_ZIP" | cut -f1))"

# ──────────────────────────── Porting notes ──────────────────────────────────
cat > "${OUT_DIR}/PORTING_NOTES.md" << MD
# HyperOS 3 → OnePlus 9 Pro (lemonadep) — Porting Notes
**Maintainer:** Ozyern  
**Date:** $(date +"%Y-%m-%d %H:%M")  
**Source ROM:** $(basename "$HYPEROS_ZIP")  
**Base ROM:** $(basename "$OOS_ZIP")

## What was ported
- HyperOS 3 system / system_ext / product partitions
- OxygenOS 14 vendor / ODM partitions (for hardware compatibility)
- OOS14 kernel (boot.img) with HyperOS ramdisk

## Patches applied
- build.prop: device identity, Android 16, VNDK34 bridge, 525 DPI
- fstab: UFS 3.1 + f2fs userdata + A/B dynamic layout
- Camera HAL: MIUI shims removed, manifest @2.7, OOS14 blobs
- RIL: MIUI shims removed, qcrild RC, VoLTE/VT/WFC enabled
- Display: 120Hz LTPO VRR config, 60Hz overlays removed
- Audio: HAL → lahaina, fluence/aptX/LDAC props
- Charging: Warp 65T / AirVOOC init RC
- Fingerprint: Goodix FOD @2.3 service RC
- Wi-Fi: QCA CLD3 ini from OOS14
- VINTF: manifest patched for VNDK 34 ↔ API 36 bridge
- SELinux: CIL rules for all OP9Pro hardware domains
- init RC: UFS, alert slider, CPU/GPU governor, haptics

## First boot checklist
- [ ] Flash with \`./flash_auto.sh --slot a --wipe-data\`
- [ ] First boot may take 3-5 minutes
- [ ] If bootloop → run \`sudo ./flash_and_fix.sh --ota HyperOS3_OOS14_lemonadep_by_Ozyern_${DATE_TAG}.zip --slot a\`

## Known limitations (need manual fix)
- [ ] Widevine L1 — need OOS14 Widevine blobs
- [ ] VoLTE — test on carrier, may need IMS APKs from OOS14
- [ ] Alert slider — test all 3 positions
- [ ] Haptics calibration — may need oplus_haptics tuning
- [ ] HyperOS AI features — may not work without Xiaomi account services

## Credits
- **Port Maintainer:** Ozyern (github.com/ozyern)
- **Reference:** toraidl/HyperOS-Port-Python, ozyern/ReVork_Ports
MD

log_ok "PORTING_NOTES.md written"

# ──────────────────────────── Done ───────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  PORT COMPLETE — Time: $(elapsed)${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "  Output ZIP : ${BOLD}$OUTPUT_ZIP${NC}"
echo -e "  Fastboot   : ${BOLD}$FASTBOOT_ZIP${NC}"
echo -e "  Flash log  : ${BOLD}$LOG_FILE${NC}"
echo -e "  Notes      : ${BOLD}${OUT_DIR}/PORTING_NOTES.md${NC}"
echo ""
echo -e "  To flash:  ${BOLD}bash ${FLASHABLE_DIR}/flash_auto.sh --slot a --wipe-data${NC}"
echo -e "  Or use:    ${BOLD}sudo ./flash_and_fix.sh --ota $OUTPUT_ZIP --slot a${NC}"
echo ""
