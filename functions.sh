#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — functions.sh
# Core utility library — sourced by port.sh
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}[*]${RESET} $*"; }
blue()    { echo -e "${BLUE}[~]${RESET} $*"; }
success() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━ $* ━━${RESET}"; }

trap 'die "Script failed at line $LINENO — command: $BASH_COMMAND"' ERR

# ── Tool verification ─────────────────────────────────────────────────────────
check_tools() {
    local missing=()
    for tool in "${TOOLS_REQUIRED[@]}"; do
        command -v "$tool" &>/dev/null || \
            [[ -f "$SCRIPT_DIR/bin/$tool" ]] || \
            missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing tools: ${missing[*]}"
        die "Run ./setup.sh first to install dependencies"
    fi
    success "All required tools found"
}

# Add project bin/ to PATH so local binaries are found
export PATH="$SCRIPT_DIR/bin:$PATH"

# ── ROM download / resolve ────────────────────────────────────────────────────
# Accepts either a local file path or a direct download URL.
resolve_rom() {
    local input="$1" label="$2" outdir="$3"
    mkdir -p "$outdir"

    if [[ "$input" =~ ^https?:// ]]; then
        local filename; filename=$(basename "$input" | sed 's/?.*//')
        local dest="$outdir/$filename"
        if [[ -f "$dest" ]]; then
            log "$label already downloaded: $dest"
        else
            log "Downloading $label ROM from: $input"
            curl -L --progress-bar -o "$dest" "$input" || \
                die "Download failed: $input"
            success "Downloaded: $dest"
        fi
        echo "$dest"
    elif [[ -f "$input" ]]; then
        echo "$input"
    else
        die "$label ROM not found: $input"
    fi
}

# ── ROM extraction ────────────────────────────────────────────────────────────
extract_rom() {
    local zip="$1" outdir="$2" label="$3"
    mkdir -p "$outdir"
    log "Extracting $label ROM…"

    # xiaomi.eu ROMs ship with pre-built super.img.*
    if 7z l "$zip" 2>/dev/null | grep -q "images/super.img"; then
        blue "Detected xiaomi.eu format (super.img.* files)"
        7z e "$zip" -o"$outdir" "images/super.img*" -y >/dev/null
        if ls "$outdir"/super.img.* &>/dev/null; then
            log "Merging split super.img…"
            simg2img "$outdir"/super.img.* "$outdir/super.img"
            rm -f "$outdir"/super.img.*
        fi
        _unpack_super "$outdir/super.img" "$outdir"
        rm -f "$outdir/super.img"

    # Standard OTA/fastboot: payload.bin
    elif 7z l "$zip" 2>/dev/null | grep -q "payload.bin"; then
        blue "Detected payload.bin format"
        local tmpdir; tmpdir=$(mktemp -d)
        7z e "$zip" -o"$tmpdir" payload.bin -y >/dev/null
        local parts_flag=""
        # Only extract needed partitions for speed
        if [[ "$label" == "HyperOS" ]]; then
            parts_flag="--partitions $(IFS=,; echo "${PORTROM_PARTITIONS[*]},mi_ext")"
        else
            parts_flag="--partitions $(IFS=,; echo "${BASEROM_PARTITIONS[*]},$(IFS=,; echo "${BASE_BOOT_IMAGES[*]}")")"
        fi
        payload-dumper-go $parts_flag --output "$outdir" "$tmpdir/payload.bin" || \
            payload-dumper-go --output "$outdir" "$tmpdir/payload.bin"
        rm -rf "$tmpdir"

    # .tgz format (some CN fastboot packages)
    elif [[ "$zip" == *.tgz ]] || [[ "$zip" == *.tar.gz ]]; then
        blue "Detected tgz format"
        local tmpdir; tmpdir=$(mktemp -d)
        tar -xzf "$zip" -C "$tmpdir"
        local superimg; superimg=$(find "$tmpdir" -name "super.img" | head -1)
        [[ -n "$superimg" ]] || die "No super.img found in tgz"
        _unpack_super "$superimg" "$outdir"
        rm -rf "$tmpdir"

    else
        die "Unrecognised ROM format: $zip"
    fi

    success "Extracted $label ROM → $outdir"
}

# Unpack super.img -> individual partition images using lpunpack
_unpack_super() {
    local super_img="$1" outdir="$2"
    if file "$super_img" | grep -q "Android sparse"; then
        log "Converting sparse super.img → raw"
        simg2img "$super_img" "${super_img%.img}_raw.img"
        mv "${super_img%.img}_raw.img" "$super_img"
    fi
    log "Unpacking super.img…"
    lpunpack "$super_img" "$outdir"
}

# Detect actual partition list in a super.img dump directory
# Returns space-separated list (handles _a/_b slots transparently)
detect_partitions() {
    local dump_dir="$1"
    local parts=()
    for img in "$dump_dir"/*.img; do
        [[ -f "$img" ]] || continue
        local name; name=$(basename "$img" .img)
        # Strip _a / _b slot suffix
        name="${name%_a}"; name="${name%_b}"
        # Deduplicate
        [[ " ${parts[*]:-} " == *" $name "* ]] || parts+=("$name")
    done
    echo "${parts[*]:-}"
}

# ── Partition mounting ────────────────────────────────────────────────────────
mount_partition() {
    local img="$1" mntpoint="$2"
    mkdir -p "$mntpoint"
    if file "$img" | grep -q "Android sparse"; then
        local raw="${img%.img}_raw.img"
        simg2img "$img" "$raw"; img="$raw"
    fi
    e2fsck -fy "$img" 2>/dev/null || true
    resize2fs "$img" 2>/dev/null || true
    mount -o loop,rw "$img" "$mntpoint" || die "Failed to mount $img"
}

unmount_partition() {
    local mntpoint="$1"
    umount "$mntpoint" 2>/dev/null || true
}

# ── Prop manipulation ─────────────────────────────────────────────────────────
strip_props() {
    local build_prop="$1"
    [[ -f "$build_prop" ]] || { warn "build.prop not found: $build_prop"; return; }
    cp "$build_prop" "${build_prop}.bak"
    for prefix in "${PROPS_TO_STRIP[@]}"; do
        sed -i "/^${prefix}/d" "$build_prop" || true
    done
    success "Stripped MIUI/HyperOS props from $(basename "$(dirname "$build_prop")")/build.prop"
}

set_prop() {
    local build_prop="$1" key="$2" value="$3"
    [[ -f "$build_prop" ]] || return
    if grep -q "^${key}=" "$build_prop"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$build_prop"
    else
        echo "${key}=${value}" >> "$build_prop"
    fi
}

apply_prop_overrides() {
    local build_prop="$1"
    for key in "${!PROP_OVERRIDES[@]}"; do
        set_prop "$build_prop" "$key" "${PROP_OVERRIDES[$key]}"
    done
}

# ── HyperOS junk removal ──────────────────────────────────────────────────────
remove_hyperos_junk() {
    local mnt_base="$1"
    step "Removing incompatible HyperOS/MIUI components"

    local priv_apps=(
        MiuiSystemUpdate
        MiCloud
        MiService
        XiaomiAccount
        MiuiCore
        SecurityCenter
        GameTurboService
        MIUIVault
        MiuiBugReport
        MiuiDaemon
        MiuiContentCatcher
    )
    for app in "${priv_apps[@]}"; do
        for search_dir in \
            "$mnt_base/system/priv-app/$app" \
            "$mnt_base/system_ext/priv-app/$app" \
            "$mnt_base/system/app/$app" \
            "$mnt_base/system_ext/app/$app"; do
            [[ -d "$search_dir" ]] && { rm -rf "$search_dir"; log "Removed $app"; }
        done
    done
    success "Removed incompatible components"
}

# ── mi_ext merge ──────────────────────────────────────────────────────────────
handle_mi_ext() {
    local source_dir="$1" system_ext_mnt="$2"
    local mi_ext_img="$source_dir/mi_ext.img"
    [[ -f "$mi_ext_img" ]] || { log "No mi_ext partition — skipping"; return; }

    log "Merging mi_ext into system_ext…"
    local mi_mnt; mi_mnt=$(mktemp -d)
    mount_partition "$mi_ext_img" "$mi_mnt"
    for subdir in app priv-app framework lib lib64 etc; do
        [[ -d "$mi_mnt/$subdir" ]] || continue
        mkdir -p "$system_ext_mnt/$subdir"
        cp -a --preserve=all "$mi_mnt/$subdir/." "$system_ext_mnt/$subdir/"
        log "Merged mi_ext/$subdir → system_ext"
    done
    unmount_partition "$mi_mnt"
    success "mi_ext merged into system_ext"
}

# ── Overlay system ────────────────────────────────────────────────────────────
# Applies device-specific overlay files from devices/<codename>/overlay/
# Mirrors toraidl's approach — copies files on top of merged system
apply_overlay() {
    local overlay_dir="$SCRIPT_DIR/devices/$TARGET_DEVICE/overlay"
    if [[ ! -d "$overlay_dir" ]]; then
        warn "devices/$TARGET_DEVICE/overlay not found — skipping overlay"
        return
    fi
    log "Applying device overlay from $overlay_dir…"
    cp -a --preserve=all "$overlay_dir/." "$1/"
    success "Overlay applied"
}

# ── Custom kernel injection (AnyKernel3) ──────────────────────────────────────
inject_anykernel() {
    local kernel_zip="$1" boot_img="$2"
    [[ -f "$kernel_zip" ]] || return
    blue "Custom kernel detected: $(basename "$kernel_zip")"

    local ak_dir; ak_dir=$(mktemp -d)
    unzip -q "$kernel_zip" -d "$ak_dir"

    local kernel_img; kernel_img=$(find "$ak_dir" -name "Image" | head -1)
    local dtb_file;   dtb_file=$(find "$ak_dir" -name "dtb" | head -1)
    local dtbo_img;   dtbo_img=$(find "$ak_dir" -name "dtbo.img" | head -1)

    [[ -n "$kernel_img" ]] || { warn "No Image found in AnyKernel zip — skipping kernel"; rm -rf "$ak_dir"; return; }

    # Check for KernelSU
    if [[ "$ak_dir" == *"-ksu"* ]] || grep -qr "ksu\|kernelsu" "$ak_dir" 2>/dev/null; then
        blue "KernelSU kernel detected"
    fi

    blue "Injecting kernel into boot.img via magiskboot"
    if command -v magiskboot &>/dev/null; then
        local tmp_boot; tmp_boot=$(mktemp -d)
        cp "$boot_img" "$tmp_boot/boot.img"
        (cd "$tmp_boot" && magiskboot unpack boot.img)
        cp "$kernel_img" "$tmp_boot/kernel"
        [[ -n "$dtb_file" ]] && cp "$dtb_file" "$tmp_boot/dtb"
        (cd "$tmp_boot" && magiskboot repack boot.img)
        cp "$tmp_boot/new-boot.img" "$boot_img"
        rm -rf "$tmp_boot"
        success "Kernel injected into boot.img"
    else
        warn "magiskboot not found — skipping kernel injection"
        warn "Flash AnyKernel zip separately after ROM installation"
    fi

    [[ -n "$dtbo_img" ]] && {
        cp "$dtbo_img" "$(dirname "$boot_img")/dtbo.img"
        success "dtbo.img replaced from kernel zip"
    }
    rm -rf "$ak_dir"
}

# ── Fstab + init patching ─────────────────────────────────────────────────────
patch_fstab() {
    local vendor_mnt="$1"
    local fstab_file; fstab_file=$(find "$vendor_mnt/etc" -name "fstab.*" 2>/dev/null | head -1 || true)
    [[ -z "$fstab_file" ]] && { warn "No fstab found in vendor"; return; }
    sed -i '/mi_ext/d' "$fstab_file" || true
    log "Patched fstab: $(basename "$fstab_file")"
}

patch_init_rc() {
    local mnt="$1"
    find "$mnt" -name "*.rc" 2>/dev/null | while read -r rc; do
        sed -i '/miui\./d; /xiaomi\./d; /mi\.daemon/d' "$rc" 2>/dev/null || true
    done
}

# ── SoC / arch validation ─────────────────────────────────────────────────────
validate_source_arch() {
    local source_dump="$1"
    local build_prop; build_prop=$(find "$source_dump" -name "build.prop" 2>/dev/null | head -1 || true)
    [[ -z "$build_prop" ]] && { warn "Cannot verify source SoC — proceeding"; return; }

    local codename; codename=$(grep "^ro\.product\.device=" "$build_prop" 2>/dev/null \
        | cut -d= -f2 | tr -d '[:space:]') || true

    local soc_id="${DEVICE_SOC[$codename]:-}"
    if [[ -z "$soc_id" ]]; then
        warn "Unknown source device '$codename' — cannot verify arm32 compatibility"
        warn "Continuing, but verify the source ROM has /system/lib/ (32-bit libs)"
        return
    fi

    local arch="${SOC_ARCH[$soc_id]:-unknown}"
    if [[ "$arch" == "pure64" ]]; then
        die "BLOCKED: Source device '$codename' ($soc_id) is pure 64-bit.
     SD 8 Gen 3 / SD 8 Elite ROMs have no arm32 compat layer.
     Porting to SM8350 (lemonadep) would break 32-bit apps and system services.
     Use a source device with SM8350 / SM8450 / SM8550 instead.
     See README.md for a full compatibility table."
    fi

    success "Source: $codename ($soc_id) — arm64+32 compatible ✓"

    # Sanity-check: lib/ should have 32-bit libs
    local lib32_count; lib32_count=$(find "$source_dump" -maxdepth 5 -path "*/system/lib/*.so" 2>/dev/null | wc -l) || true
    if [[ "$lib32_count" -lt 10 ]]; then
        warn "Only $lib32_count 32-bit libs found in source — verify /system/lib/ manually"
    fi
}

# ── Super image packing ────────────────────────────────────────────────────────
pack_super() {
    local workdir="$1" outdir="$2"
    step "Packing super.img"

    # Dynamically build partition list from what's actually present
    local present_parts=()
    for part in $(detect_partitions "$workdir"); do
        [[ -f "$workdir/${part}.img" ]] && present_parts+=("$part")
    done

    local lpmake_args=(
        --metadata-size "$METADATA_SIZE"
        --super-name super
        --block-size "$SUPER_BLOCK_SIZE"
        --metadata-slots 3
        --device "super:$SUPER_SIZE"
        --group "qti_dynamic_partitions_a:$SUPER_SIZE"
        --group "qti_dynamic_partitions_b:$SUPER_SIZE"
    )

    for part in "${present_parts[@]}"; do
        local img="$workdir/${part}.img"
        local sparse_img="$workdir/${part}_sparse.img"
        img2simg "$img" "$sparse_img"
        local size; size=$(stat -c%s "$img")
        lpmake_args+=(
            --partition "${part}_a:readonly:${size}:qti_dynamic_partitions_a"
            --image "${part}_a=$sparse_img"
            --partition "${part}_b:readonly:0:qti_dynamic_partitions_b"
        )
    done

    local super_out="$outdir/super.img"
    lpmake "${lpmake_args[@]}" --output "$super_out" --sparse
    success "super.img → $super_out ($(du -sh "$super_out" | cut -f1))"
}

# ── Flashable zip assembly ─────────────────────────────────────────────────────
build_flashable_zip() {
    local workdir="$1" outdir="$2" version="$3"
    step "Building flashable zip"

    local zip_root="$workdir/zip_root"
    mkdir -p "$zip_root/META-INF/com/google/android" "$zip_root/images"

    cat > "$zip_root/META-INF/com/google/android/updater-script" <<'EOF'
# HyperOS_Port — lemonadep
EOF

    cat > "$zip_root/META-INF/com/google/android/update-binary" <<'FLASHER'
#!/sbin/sh
OUTFD="/proc/self/fd/$2"; ZIPFILE="$3"
ui_print() { echo "ui_print $*" > "$OUTFD"; echo "ui_print" > "$OUTFD"; }
abort()    { ui_print "ERROR: $*"; exit 1; }

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  HyperOS_Port for lemonadep   "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TMPDIR=/tmp/hyperos_port; mkdir -p "$TMPDIR"
unzip -o "$ZIPFILE" 'images/*' -d "$TMPDIR" || abort "Failed to extract"

flash() {
    local part=$1 img="$TMPDIR/images/$2"
    ui_print "  Flashing $part..."
    [ -f "$img" ] || abort "Missing: $2"
    blockdev --setrw "/dev/block/by-name/$part" 2>/dev/null || true
    dd if="$img" of="/dev/block/by-name/$part" bs=4096 || abort "Flash failed: $part"
}

ui_print "[1/4] Boot images..."
flash boot_a boot.img; flash vendor_boot_a vendor_boot.img; flash dtbo_a dtbo.img

ui_print "[2/4] Super partition..."
flash super super.img

ui_print "[3/4] Setting active slot A..."
/sbin/bootctl set-active-boot-slot 0 2>/dev/null || true

ui_print "[4/4] Done!"
ui_print "  Wipe data/factory reset is REQUIRED."
ui_print "  First boot takes 3-5 minutes."
rm -rf "$TMPDIR"
FLASHER

    chmod +x "$zip_root/META-INF/com/google/android/update-binary"

    for img in super.img boot.img vendor_boot.img dtbo.img; do
        [[ -f "$workdir/$img" ]] && cp "$workdir/$img" "$zip_root/images/" || true
    done

    local zip_out="$outdir/HyperOS_Port_lemonadep_${version}.zip"
    (cd "$zip_root" && zip -r9 "$zip_out" .)
    success "Flashable zip → $zip_out ($(du -sh "$zip_out" | cut -f1))"
}

get_version_string() {
    local source_dir="$1"
    local bp; bp=$(find "$source_dir" -name "build.prop" | head -1)
    local ver
    ver=$(grep "^ro.build.version.incremental=" "$bp" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]') || true
    echo "${ver:-$(date +%Y%m%d)}"
}
