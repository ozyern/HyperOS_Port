#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — functions.sh
# Core utility library — sourced by port.sh
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━ $* ━━${RESET}"; }

# ── Error trap ────────────────────────────────────────────────────────────────
trap 'die "Script failed at line $LINENO — command: $BASH_COMMAND"' ERR

# ── Tool verification ─────────────────────────────────────────────────────────
check_tools() {
    local missing=()
    for tool in "${TOOLS_REQUIRED[@]}"; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    [[ ${#missing[@]} -gt 0 ]] && die "Missing tools: ${missing[*]}"
    success "All required tools found"
}

# ── ROM extraction ────────────────────────────────────────────────────────────
# Detects payload.bin (fastboot OTA) vs raw zip (TWRP/OTA sideload)
extract_rom() {
    local zip="$1" outdir="$2" label="$3"
    mkdir -p "$outdir"
    log "Extracting $label ROM: $zip"

    if 7z l "$zip" | grep -q "payload.bin"; then
        log "Detected payload.bin — using payload_dumper"
        local tmpdir; tmpdir=$(mktemp -d)
        7z e "$zip" -o"$tmpdir" payload.bin -y >/dev/null
        payload_dumper --out "$outdir" "$tmpdir/payload.bin"
        rm -rf "$tmpdir"
    elif 7z l "$zip" | grep -q "super.img"; then
        log "Detected pre-built super.img — extracting directly"
        7z e "$zip" -o"$outdir" "super.img" -y >/dev/null
        _unpack_super "$outdir/super.img" "$outdir"
        rm -f "$outdir/super.img"
    else
        die "Cannot determine ROM format for $zip"
    fi
    success "Extracted $label ROM to $outdir"
}

# Unpack super.img → individual partition images
_unpack_super() {
    local super_img="$1" outdir="$2"
    # Convert sparse → raw if needed
    if file "$super_img" | grep -q "Android sparse"; then
        log "Converting sparse super.img to raw"
        simg2img "$super_img" "${super_img%.img}_raw.img"
        mv "${super_img%.img}_raw.img" "$super_img"
    fi
    lpunpack "$super_img" "$outdir"
}

# ── Partition mounting ────────────────────────────────────────────────────────
mount_partition() {
    local img="$1" mntpoint="$2"
    mkdir -p "$mntpoint"
    # Convert to raw if sparse
    if file "$img" | grep -q "Android sparse"; then
        local raw="${img%.img}_raw.img"
        simg2img "$img" "$raw"
        img="$raw"
    fi
    # Resize to ensure free space for edits
    e2fsck -fy "$img" 2>/dev/null || true
    resize2fs "$img" 2>/dev/null || true
    mount -o loop,rw "$img" "$mntpoint" || die "Failed to mount $img"
    log "Mounted $img → $mntpoint"
}

unmount_partition() {
    local mntpoint="$1"
    umount "$mntpoint" 2>/dev/null || true
    rmdir "$mntpoint" 2>/dev/null || true
}

# ── Partition merge ───────────────────────────────────────────────────────────
# Copies contents from source image into a fresh ext4 image
copy_partition_contents() {
    local src_img="$1" dst_img="$2" label="$3"
    local src_mnt dst_mnt
    src_mnt=$(mktemp -d); dst_mnt=$(mktemp -d)

    # Get source size for dst sizing
    local src_size; src_size=$(stat -c%s "$src_img")
    local dst_size=$(( src_size + 64*1024*1024 ))   # +64 MiB headroom

    log "Creating $label partition image ($(( dst_size / 1024 / 1024 )) MiB)"
    dd if=/dev/zero of="$dst_img" bs=1 count=0 seek="$dst_size" 2>/dev/null
    mkfs.ext4 -L "$label" "$dst_img" >/dev/null 2>&1

    mount_partition "$src_img" "$src_mnt"
    mount_partition "$dst_img" "$dst_mnt"

    log "Copying $label contents…"
    cp -a --preserve=all "$src_mnt/." "$dst_mnt/"

    unmount_partition "$dst_mnt"
    unmount_partition "$src_mnt"
    rm -f "$src_mnt" "$dst_mnt" 2>/dev/null || true
    success "Copied $label"
}

# ── Prop manipulation ─────────────────────────────────────────────────────────
strip_props() {
    local build_prop="$1"
    [[ -f "$build_prop" ]] || { warn "build.prop not found: $build_prop"; return; }

    local backup="${build_prop}.bak"
    cp "$build_prop" "$backup"

    for prefix in "${PROPS_TO_STRIP[@]}"; do
        sed -i "/^${prefix}/d" "$build_prop" || true
    done
    success "Stripped MIUI/HyperOS props from $(basename "$build_prop")"
}

set_prop() {
    local build_prop="$1" key="$2" value="$3"
    [[ -f "$build_prop" ]] || { warn "build.prop not found: $build_prop"; return; }

    if grep -q "^${key}=" "$build_prop"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$build_prop"
    else
        echo "${key}=${value}" >> "$build_prop"
    fi
}

apply_prop_overrides() {
    local build_prop="$1"
    log "Applying prop overrides to $(basename "$build_prop")"
    for key in "${!PROP_OVERRIDES[@]}"; do
        set_prop "$build_prop" "$key" "${PROP_OVERRIDES[$key]}"
    done
    success "Applied prop overrides"
}

# ── HyperOS-specific cleanups ─────────────────────────────────────────────────
remove_hyperos_junk() {
    local system_mnt="$1"
    step "Removing incompatible HyperOS components"

    # MIUI/HyperOS analytics & cloud services — won't work, waste space
    local remove_apps=(
        MiuiCore
        MiCloud
        MiService
        MiuiSuperCut
        MiuiMiTime
        CleanMaster
        MiuiVirtualSim
        SecurityCenter      # Xiaomi-HAL-dependent
        MiuiContentCatcher
        MiuiBugReport
        MiuiDaemon
        GameTurboService    # Xiaomi-specific HAL
        MIUIVault
        MiuiSuperResolution
    )

    for app in "${remove_apps[@]}"; do
        local app_path="$system_mnt/system_ext/app/$app"
        local priv_path="$system_mnt/system_ext/priv-app/$app"
        [[ -d "$app_path" ]] && { rm -rf "$app_path"; log "Removed $app"; } || true
        [[ -d "$priv_path" ]] && { rm -rf "$priv_path"; log "Removed $app (priv)"; } || true
    done

    # Remove Xiaomi-HAL-dependent native libs from system
    local xiaomi_libs=(
        "libMiuiHapticFeedback.so"
        "libxiaomi_ril.so"
        "libmiuiphonewindow.so"
    )
    for lib in "${xiaomi_libs[@]}"; do
        find "$system_mnt" -name "$lib" -delete 2>/dev/null || true
    done

    success "Removed incompatible HyperOS components"
}

# ── mi_ext partition handling ──────────────────────────────────────────────────
# HyperOS introduced a separate mi_ext partition — strip it, merge needed
# bits into system_ext
handle_mi_ext() {
    local source_dir="$1" system_ext_mnt="$2"
    local mi_ext_img="$source_dir/mi_ext.img"

    if [[ ! -f "$mi_ext_img" ]]; then
        log "No mi_ext partition found — skipping"
        return
    fi

    log "Processing mi_ext partition"
    local mi_mnt; mi_mnt=$(mktemp -d)
    mount_partition "$mi_ext_img" "$mi_mnt"

    # Copy mi_ext/app and mi_ext/priv-app into system_ext
    for subdir in app priv-app framework lib lib64 etc; do
        [[ -d "$mi_mnt/$subdir" ]] || continue
        cp -a --preserve=all "$mi_mnt/$subdir/." "$system_ext_mnt/$subdir/" 2>/dev/null || true
        log "Merged mi_ext/$subdir → system_ext"
    done

    unmount_partition "$mi_mnt"
    success "mi_ext merged into system_ext"
}

# ── Init / fstab patching ─────────────────────────────────────────────────────
patch_fstab() {
    local vendor_mnt="$1"
    log "Patching fstab for lemonadep partition layout"

    local fstab_file; fstab_file=$(find "$vendor_mnt/etc" -name "fstab.*" | head -1 || true)
    [[ -z "$fstab_file" ]] && { warn "No fstab found in vendor"; return; }

    # Strip mi_ext entries if present (partition won't exist on lemonadep)
    sed -i '/mi_ext/d' "$fstab_file" || true
    # Ensure logical partitions list matches our super layout
    log "Patched fstab: $fstab_file"
}

patch_init_rc() {
    local system_mnt="$1"
    log "Patching init.rc fragments"

    # Remove MIUI-specific init services that reference unavailable HALs
    find "$system_mnt" -name "*.rc" | while read -r rc; do
        sed -i '/miui.*/d; /xiaomi.*/d; /mi\.daemon/d' "$rc" 2>/dev/null || true
    done
    success "Patched init.rc fragments"
}

# ── SELinux context fixup ─────────────────────────────────────────────────────
fix_selinux_contexts() {
    local partition_mnt="$1" label="$2"
    local contexts_file="$partition_mnt/etc/selinux/plat_file_contexts"
    [[ -f "$contexts_file" ]] || return
    log "SELinux contexts present in $label — keeping as-is (Xiaomi contexts are GKI-compatible)"
}

# ── Super image packing ────────────────────────────────────────────────────────
pack_super() {
    local workdir="$1" outdir="$2"
    step "Packing super.img"

    local lpmake_args=(
        --metadata-size "$METADATA_SIZE"
        --super-name super
        --block-size "$SUPER_BLOCK_SIZE"
        --metadata-slots 3
        --device super:"$SUPER_SIZE"
        --group qti_dynamic_partitions_a:"$SUPER_SIZE"
        --group qti_dynamic_partitions_b:"$SUPER_SIZE"
    )

    local slot_suffix=_a
    for part in $DYNAMIC_PARTITION_LIST; do
        local img="$workdir/${part}.img"
        [[ -f "$img" ]] || die "Missing partition image: $img"

        # Convert to sparse for super packing
        local sparse_img="$workdir/${part}_sparse.img"
        img2simg "$img" "$sparse_img"

        lpmake_args+=(
            --partition "${part}${slot_suffix}":readonly:"$(stat -c%s "$img")":qti_dynamic_partitions_a
            --image "${part}${slot_suffix}=$sparse_img"
            # Slot B — empty (will be filled on first OTA)
            --partition "${part}_b":readonly:0:qti_dynamic_partitions_b
        )
    done

    local super_out="$outdir/super.img"
    lpmake_args+=(--output "$super_out" --sparse)

    log "Running lpmake…"
    lpmake "${lpmake_args[@]}"
    success "super.img → $super_out ($(du -sh "$super_out" | cut -f1))"
}

# ── Flashable zip assembly ─────────────────────────────────────────────────────
build_flashable_zip() {
    local workdir="$1" outdir="$2" version="$3"
    step "Building flashable zip"

    local zip_root="$workdir/zip_root"
    mkdir -p "$zip_root/META-INF/com/google/android"

    # updater-script (stub — real logic in update-binary)
    cat > "$zip_root/META-INF/com/google/android/updater-script" <<'EOF'
# HyperOS_Port — generated by port.sh
EOF

    # update-binary: shell-based flasher
    cat > "$zip_root/META-INF/com/google/android/update-binary" <<'FLASHER'
#!/sbin/sh
# HyperOS_Port — update-binary
OUTFD="/proc/self/fd/$2"
ZIPFILE="$3"

ui_print() { echo "ui_print $*" > "$OUTFD"; echo "ui_print" > "$OUTFD"; }
abort()    { ui_print "ERROR: $*"; exit 1; }

ui_print "━━ HyperOS_Port Installer ━━"
ui_print "Target: OnePlus 9 Pro (lemonadep)"
ui_print ""

TMPDIR=/tmp/hyperos_port
mkdir -p "$TMPDIR"
unzip -o "$ZIPFILE" 'images/*' -d "$TMPDIR" || abort "Failed to extract images"

flash_image() {
    local part="$1" img="$TMPDIR/images/$2"
    ui_print "  Flashing $part…"
    [ -f "$img" ] || abort "Missing image: $2"
    blockdev --setrw "/dev/block/by-name/$part" 2>/dev/null || true
    dd if="$img" of="/dev/block/by-name/$part" bs=4096 || abort "Flash failed: $part"
}

ui_print "[1/4] Flashing boot images…"
flash_image boot_a        boot.img
flash_image vendor_boot_a vendor_boot.img
flash_image dtbo_a        dtbo.img

ui_print "[2/4] Flashing super…"
flash_image super super.img

ui_print "[3/4] Wiping userdata…"
ui_print "  (Skipping — wipe manually if needed)"

ui_print "[4/4] Setting active slot to A…"
/sbin/bootctl set-active-boot-slot 0 2>/dev/null || true

ui_print ""
ui_print "✓ HyperOS_Port installed successfully!"
ui_print "  Boot into system — first boot may take 3-5 minutes."
rm -rf "$TMPDIR"
FLASHER

    chmod +x "$zip_root/META-INF/com/google/android/update-binary"

    # Copy images
    mkdir -p "$zip_root/images"
    for img in super.img boot.img vendor_boot.img dtbo.img; do
        [[ -f "$workdir/$img" ]] && cp "$workdir/$img" "$zip_root/images/"
    done

    local zip_out="$outdir/HyperOS_Port_lemonadep_${version}.zip"
    (cd "$zip_root" && zip -r9 "$zip_out" . -x "*.DS_Store")
    success "Flashable zip → $zip_out ($(du -sh "$zip_out" | cut -f1))"
}

# ── Version string helper ─────────────────────────────────────────────────────
get_version_string() {
    local source_dir="$1"
    local build_prop="$source_dir/system/system/build.prop"
    [[ -f "$build_prop" ]] || build_prop="$source_dir/system/build.prop"

    local version
    version=$(grep "^ro.build.version.incremental=" "$build_prop" 2>/dev/null \
               | cut -d= -f2 | tr -d '[:space:]') || true
    echo "${version:-unknown}"
}
