#!/usr/bin/env bash
# =============================================================================
# flash_and_fix.sh — Auto-fix boot issues then flash to OnePlus 9 Pro
#
#   Usage:  sudo ./flash_and_fix.sh --ota <ported_zip> [--slot a|b] [--wipe-data]
#
# Fixes applied before flashing:
#   1. SELinux permissive (first boot safety net)
#   2. SELinux CIL policy (enforcing-safe rules)
#   3. VINTF / HAL version alignment
#   4. VNDK 34 bridge props
#   5. Broken MIUI init services disabled
#   6. Missing library stubs generated
#   7. 60Hz overlays removed
#
# Maintainer : Ozyern  |  https://github.com/ozyern
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SELF_DIR}/functions.sh"

# ──────────────────────────── Args ───────────────────────────────────────────
OTA_ZIP=""
SLOT="a"
WIPE_DATA=0
DRY_RUN=0
NO_PERMISSIVE=0
SKIP_FIX=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ota)         OTA_ZIP="$2"; shift 2 ;;
        --ota=*)       OTA_ZIP="${1#*=}"; shift ;;
        --slot)        SLOT="$2"; shift 2 ;;
        --slot=*)      SLOT="${1#*=}"; shift ;;
        --wipe-data)   WIPE_DATA=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --no-permissive) NO_PERMISSIVE=1; shift ;;
        --skip-fix)    SKIP_FIX=1; shift ;;
        -v|--verbose)  VERBOSE=1; shift ;;
        -h|--help)
            echo "Usage: sudo ./flash_and_fix.sh --ota <zip> [--slot a|b] [--wipe-data] [--dry-run]"
            echo ""
            echo "  --ota <zip>       Path to ported ZIP from port.sh"
            echo "  --slot a|b        Target A/B slot (default: a)"
            echo "  --wipe-data       Wipe userdata before flashing"
            echo "  --dry-run         Print commands without flashing"
            echo "  --no-permissive   Don't set SELinux permissive (for re-flash after stable)"
            echo "  --skip-fix        Skip all boot fixes (just flash)"
            exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

banner

[[ -z "$OTA_ZIP" ]] && die "No OTA ZIP specified. Use: --ota <path/to/ported.zip>"
[[ -f "$OTA_ZIP" ]] || die "OTA ZIP not found: $OTA_ZIP"
[[ "$SLOT" != "a" && "$SLOT" != "b" ]] && die "Invalid slot: $SLOT (must be a or b)"

require_root

# ──────────────────────────── Workspace ──────────────────────────────────────
DATE_TAG=$(date +%Y%m%d_%H%M)
WORK_DIR="/tmp/flash_fix_${DATE_TAG}"
EXTRACT_DIR="${WORK_DIR}/extracted"
FIXED_DIR="${WORK_DIR}/fixed"
LOG_FILE="${SELF_DIR}/flash_fix_${DATE_TAG}.log"

mkdir -p "$EXTRACT_DIR" "$FIXED_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "OTA ZIP  : $OTA_ZIP"
log_info "Slot     : _${SLOT}"
log_info "Log      : $LOG_FILE"
is_wsl && log_warn "WSL detected — using userspace extraction"

# ──────────────────────────── Extract OTA ────────────────────────────────────
log_step "Extracting OTA ZIP"
unzip -o "$OTA_ZIP" -d "$EXTRACT_DIR" || die "Failed to extract OTA ZIP"
log_ok "OTA extracted → $EXTRACT_DIR"

# List what we got
log_info "Contents:"
ls -lh "$EXTRACT_DIR"/*.img 2>/dev/null | awk '{print "  ",$NF,"(",$5,")"}' || true

if [[ $SKIP_FIX -eq 1 ]]; then
    log_warn "--skip-fix set, skipping all boot fixes"
    FIXED_DIR="$EXTRACT_DIR"
else

# ──────────────────────────── Fix 1: Extract & patch system images ───────────
log_step "Fix 1 — Extracting partition images for patching"

FIX_WORKDIR="${WORK_DIR}/partitions"
mkdir -p "$FIX_WORKDIR"

for part in system vendor odm product system_ext; do
    img="${EXTRACT_DIR}/${part}.img"
    [[ -f "$img" ]] || continue
    dest="${FIX_WORKDIR}/${part}"
    log_info "  Extracting $part for patching..."
    extract_img "$img" "$dest" || { log_warn "  Could not extract $part — will use as-is"; continue; }
done

# ──────────────────────────── Fix 2: SELinux permissive boot ─────────────────
if [[ $NO_PERMISSIVE -eq 0 ]]; then
    log_step "Fix 2 — SELinux permissive (first boot safety net)"
    BOOT_IMG="${EXTRACT_DIR}/boot.img"
    INIT_BOOT_IMG="${EXTRACT_DIR}/init_boot.img"

    patch_boot_permissive() {
        local img="$1"
        [[ -f "$img" ]] || return 0
        local work="${WORK_DIR}/boot_perm_$(basename "$img" .img)"
        mkdir -p "$work"
        cp "$img" "${work}/boot.img"

        if command -v magiskboot &>/dev/null; then
            ( cd "$work" && magiskboot unpack boot.img ) || { log_warn "  magiskboot unpack failed for $(basename "$img")"; return; }

            # Patch kernel cmdline
            if [[ -f "${work}/header" ]]; then
                sed -i 's|androidboot.selinux=enforcing||g' "${work}/header" 2>/dev/null || true
                if grep -q "cmdline" "${work}/header"; then
                    sed -i 's|cmdline=\(.*\)|cmdline=\1 androidboot.selinux=permissive|' "${work}/header"
                fi
            fi

            # Patch default.prop in ramdisk
            if [[ -f "${work}/ramdisk.cpio" ]]; then
                local ramdisk_dir="${work}/ramdisk_extracted"
                mkdir -p "$ramdisk_dir"
                ( cd "$ramdisk_dir" && cpio -i < "${work}/ramdisk.cpio" ) 2>/dev/null || true
                for prop in "${ramdisk_dir}/default.prop" "${ramdisk_dir}/system/etc/prop.default"; do
                    [[ -f "$prop" ]] && prop_set "$prop" "ro.boot.selinux" "permissive"
                done
                # Patch init.rc to enforce permissive
                if [[ -f "${ramdisk_dir}/init.rc" ]]; then
                    grep -q "selinux.enforce" "${ramdisk_dir}/init.rc" || \
                        sed -i '/on early-init/a\    write /sys/fs/selinux/enforce 0' "${ramdisk_dir}/init.rc"
                fi
                ( cd "$ramdisk_dir" && find . | cpio -o -H newc > "${work}/ramdisk.cpio" ) 2>/dev/null || true
            fi

            ( cd "$work" && magiskboot repack boot.img ) && \
                cp "${work}/new-boot.img" "${FIXED_DIR}/$(basename "$img")" && \
                log_ok "  $(basename "$img") patched — SELinux permissive" || \
                { log_warn "  Repack failed, using original"; cp "$img" "${FIXED_DIR}/$(basename "$img")"; }
        else
            log_warn "  magiskboot not found — copying boot as-is (no permissive patch)"
            cp "$img" "${FIXED_DIR}/$(basename "$img")"
        fi
    }

    patch_boot_permissive "$BOOT_IMG"
    patch_boot_permissive "$INIT_BOOT_IMG"
else
    log_warn "--no-permissive: skipping SELinux permissive boot patch"
    [[ -f "${EXTRACT_DIR}/boot.img" ]] && cp "${EXTRACT_DIR}/boot.img" "${FIXED_DIR}/boot.img"
    [[ -f "${EXTRACT_DIR}/init_boot.img" ]] && cp "${EXTRACT_DIR}/init_boot.img" "${FIXED_DIR}/init_boot.img"
fi

# ──────────────────────────── Fix 3: SELinux CIL ─────────────────────────────
log_step "Fix 3 — SELinux CIL policy (enforcing-safe rules)"

CIL_FILE=$(find "${FIX_WORKDIR}/vendor" -name "*.cil" 2>/dev/null | head -1)
if [[ -n "$CIL_FILE" ]]; then
    append_cil_rules "$CIL_FILE" \
        "(allow untrusted_app goodix_fp_device (chr_file (read write open ioctl)))" \
        "(allow system_server oplus_charger_device (chr_file (read write open ioctl)))" \
        "(allow hal_thermal_default thermal_data_file (file (read open getattr)))" \
        "(allow qcrild rild_socket (sock_file (write)))" \
        "(allow hal_camera_default vendor_data_file (dir (search)))" \
        "(allow hal_fingerprint_default goodix_fp_device (chr_file (read write open ioctl)))" \
        "(allow hal_health_default sysfs_battery_supply (file (read open getattr)))" \
        "(allow init oplus_chg_service (service_manager (add)))" \
        "(allow hal_bluetooth_default bt_firmware_file (file (read open execute)))" \
        "(allow wpa wpa_socket (sock_file (create unlink)))" \
        "(allow hal_nfc_default nfc_prop (property_service (set)))" \
        "(allow shell vendor_file (dir (search read)))" \
        "(allow adbd shell_data_file (dir (search write create)))" \
        "(allow system_app audio_prop (property_service (set)))" \
        "(allow qti_init_shell vendor_file (dir (search read execute)))" \
        "(allow hal_graphics_composer_default vendor_file (dir (search read)))" \
        "(allow mediaserver vendor_file (dir (search read)))" \
        "(allow audioserver vendor_file (dir (search read)))" \
        "(allow cameraserver vendor_file (dir (search read)))"
    log_ok "  SELinux CIL patched: $CIL_FILE"
else
    log_warn "  No .cil file found in vendor partition"
fi

# ──────────────────────────── Fix 4: VINTF alignment ─────────────────────────
log_step "Fix 4 — VINTF manifest alignment (VNDK34 ↔ API36)"

VENDOR_MANIFEST="${FIX_WORKDIR}/vendor/etc/vintf/manifest.xml"
if [[ -f "$VENDOR_MANIFEST" ]]; then
    python3 - "$VENDOR_MANIFEST" << 'PY'
import sys, re
path = sys.argv[1]
txt = open(path).read()

fixes = [
    # Camera provider
    (r'android\.hardware\.camera\.provider@\d+\.\d+',
     'android.hardware.camera.provider@2.7'),
    # Composer
    (r'android\.hardware\.graphics\.composer@\d+\.\d+',
     'android.hardware.graphics.composer@2.4'),
    # VNDK version
    (r'<vendor-ndk>\s*<version>\d+</version>',
     '<vendor-ndk>\n        <version>34</version>'),
]

for pattern, replacement in fixes:
    txt = re.sub(pattern, replacement, txt)

# Remove dead HIDL blocks
for dead in ['android.hardware.health@3.0',
             'android.hardware.drm@1.4',
             'android.hardware.memtrack@1.0']:
    txt = re.sub(
        r'<hal format="hidl">.*?' + re.escape(dead) + r'.*?</hal>\s*',
        '', txt, flags=re.DOTALL)

open(path, 'w').write(txt)
print(f"  VINTF patched: {path}")
PY
    log_ok "  VINTF manifest aligned"
else
    log_warn "  vendor manifest not found"
fi

# ──────────────────────────── Fix 5: VNDK bridge props ───────────────────────
log_step "Fix 5 — VNDK 34 bridge props"

for prop_file in \
    "${FIX_WORKDIR}/vendor/build.prop" \
    "${FIX_WORKDIR}/system/build.prop" \
    "${FIX_WORKDIR}/system/system/build.prop"
do
    [[ -f "$prop_file" ]] || continue
    prop_set "$prop_file" ro.vndk.version            "34"
    prop_set "$prop_file" ro.board.api_level          "34"
    prop_set "$prop_file" ro.board.first_api_level    "30"
    prop_set "$prop_file" ro.vendor.api_level         "34"
    prop_set "$prop_file" debug.vintf.enforce_hal     "false"
    log_ok "  Props patched: $prop_file"
done

# ──────────────────────────── Fix 6: Disable bad MIUI services ───────────────
log_step "Fix 6 — Disabling broken MIUI init services"

DEAD_SERVICES=(
    "mimdump" "mqsasd" "mcd" "misight" "miui_log"
    "mi_disp" "mi_thermald" "milogs" "miperf" "minetd"
    "vendor.xiaomi" "xiaomi.hardware"
)

find "${FIX_WORKDIR}" -name "*.rc" 2>/dev/null | while read -r rc; do
    modified=0
    for svc in "${DEAD_SERVICES[@]}"; do
        if grep -q "$svc" "$rc" 2>/dev/null; then
            # Add disabled + oneshot to prevent crash loops
            python3 - "$rc" "$svc" << 'PY'
import sys, re
path, svc = sys.argv[1], sys.argv[2]
txt = open(path).read()

def patch_service(m):
    block = m.group(0)
    if 'disabled' not in block:
        block = block.rstrip() + '\n    disabled\n'
    if 'oneshot' not in block:
        block = block.rstrip() + '\n    oneshot\n'
    return block

pattern = r'(service\s+\S*' + re.escape(svc) + r'[^\n]*\n(?:(?!^service\s).*\n)*)'
txt = re.sub(pattern, patch_service, txt, flags=re.MULTILINE)
open(path, 'w').write(txt)
PY
            modified=$((modified + 1))
        fi
    done
    [[ $modified -gt 0 ]] && log_info "  Patched RC: $(basename "$rc") ($modified services)"
done
log_ok "MIUI services disabled"

# ──────────────────────────── Fix 7: 60Hz overlay cleanup ────────────────────
log_step "Fix 7 — Removing 60Hz display overlays"

REMOVED=0
find "${FIX_WORKDIR}" -name "*.apk" 2>/dev/null | while read -r apk; do
    if command -v strings &>/dev/null; then
        if strings "$apk" 2>/dev/null | grep -qE "maxRefreshRate.*[^1]60|<refreshRate>60"; then
            log_info "  Removing 60Hz overlay: $(basename "$apk")"
            rm -f "$apk"
            REMOVED=$((REMOVED + 1))
        fi
    fi
done
log_ok "60Hz overlay cleanup done"

# ──────────────────────────── Repack fixed images ────────────────────────────
log_step "Repacking fixed partition images"

for part in system system_ext product vendor odm; do
    src="${FIX_WORKDIR}/${part}"
    [[ -d "$src" ]] || continue
    [[ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ]] && continue
    out_img="${FIXED_DIR}/${part}.img"
    log_info "  Repacking ${part}..."
    repack_img "$src" "$out_img" "erofs" "$part" || {
        log_warn "  erofs repack failed for $part, trying ext4..."
        repack_img "$src" "$out_img" "ext4" "$part" || log_warn "  ${part} repack failed — will use original"
    }
done

# Copy any images not repacked from extract dir
for img in "${EXTRACT_DIR}"/*.img; do
    base=$(basename "$img")
    [[ -f "${FIXED_DIR}/${base}" ]] || cp -f "$img" "${FIXED_DIR}/${base}"
done

fi  # end SKIP_FIX

# ──────────────────────────── Flash ──────────────────────────────────────────
log_step "Flashing to device (slot _${SLOT})"

FB="fastboot"

run_fb() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} fastboot $*"
    else
        "$FB" "$@" || warn "fastboot $* returned non-zero (may be OK)"
    fi
}

# Check device
if [[ $DRY_RUN -eq 0 ]]; then
    "$FB" devices | grep -q "fastboot" || die "No device found in fastboot mode. Connect device and run: fastboot devices"
    log_ok "Device detected in fastboot"
fi

# Disable AVB
log_info "Disabling AVB verification..."
run_fb oem disable-verification 2>/dev/null || true
run_fb flashing unlock 2>/dev/null || true

# Flash vbmeta
for vb in vbmeta vbmeta_system; do
    img="${FIXED_DIR}/${vb}.img"
    [[ -f "$img" ]] || img="${EXTRACT_DIR}/${vb}.img"
    if [[ -f "$img" ]]; then
        run_fb --disable-verity --disable-verification flash "${vb}_${SLOT}" "$img"
        log_ok "  Flashed ${vb}_${SLOT}"
    fi
done

# Reboot to fastbootd
log_info "Rebooting to fastbootd..."
run_fb reboot fastboot
if [[ $DRY_RUN -eq 0 ]]; then
    sleep 10
fi

# Delete logical partitions
log_info "Removing old logical partitions..."
for part in system system_ext product vendor odm; do
    run_fb delete-logical-partition "${part}_a" 2>/dev/null || true
    run_fb delete-logical-partition "${part}_b" 2>/dev/null || true
done

# Flash logical partitions
log_info "Flashing logical partitions → slot _${SLOT}..."
for part in system system_ext product vendor odm; do
    img="${FIXED_DIR}/${part}.img"
    [[ -f "$img" ]] || img="${EXTRACT_DIR}/${part}.img"
    if [[ -f "$img" ]]; then
        SIZE=$(wc -c < "$img")
        run_fb create-logical-partition "${part}_${SLOT}" "$SIZE" 2>/dev/null || true
        run_fb flash "${part}_${SLOT}" "$img"
        log_ok "  ✓ ${part}_${SLOT} ($(du -sh "$img" | cut -f1))"
    else
        warn "  ${part}.img not found — skipping"
    fi
done

# Flash raw partitions
log_info "Flashing boot partitions..."
for part in boot init_boot vendor_boot dtbo; do
    img="${FIXED_DIR}/${part}.img"
    [[ -f "$img" ]] || img="${EXTRACT_DIR}/${part}.img"
    if [[ -f "$img" ]]; then
        run_fb flash "${part}_${SLOT}" "$img"
        log_ok "  ✓ ${part}_${SLOT}"
    fi
done

# Wipe data
if [[ $WIPE_DATA -eq 1 ]]; then
    warn "Wiping userdata..."
    run_fb -w
    log_ok "  Userdata wiped"
fi

# Set active slot
log_info "Setting active slot → _${SLOT}..."
run_fb set_active "$SLOT"

# Reboot
log_info "Rebooting to system..."
run_fb reboot

# ──────────────────────────── Cleanup ────────────────────────────────────────
rm -rf "$WORK_DIR"

# ──────────────────────────── Done ───────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  FLASH COMPLETE!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "  Slot   : ${BOLD}_${SLOT}${NC}"
echo -e "  Log    : ${BOLD}$LOG_FILE${NC}"
echo ""
echo -e "${YELLOW}First boot takes 3-5 minutes — this is normal.${NC}"
echo ""
echo -e "  If you hit a bootloop, after stable boot switch to enforcing:"
echo -e "  ${BOLD}sudo ./flash_and_fix.sh --ota $OTA_ZIP --slot $SLOT --no-permissive${NC}"
echo ""
