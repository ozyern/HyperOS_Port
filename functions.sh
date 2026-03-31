#!/usr/bin/env bash
# =============================================================================
# functions.sh — Shared library for HyperOS 3 → OnePlus 9 Pro porting toolkit
# Maintainer : Ozyern  |  https://github.com/ozyern
# Project    : HyperOS3-Port-lemonadep
# =============================================================================

# ──────────────────────────── Colour helpers ─────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()     { echo -e "${RED}[ERR]${NC}   $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
log_debug()   { [[ "${VERBOSE:-0}" == "1" ]] && echo -e "${YELLOW}[DBG]${NC}   $*"; }
die()         { log_err "$*"; exit 1; }

banner() {
cat << 'EOF'
  _   _                  ___  ____    _____           _ _    _ _
 | | | |_   _ _ __   ___|_ _|/ ___|  |_   _|__   ___ | | | _(_) |_
 | |_| | | | | '_ \ / _ \| || |   _____| |/ _ \ / _ \| | |/ / | __|
 |  _  | |_| | |_) |  __/| || |__|_____| | (_) | (_) | |   <| | |_
 |_| |_|\__, | .__/ \___|___|\____|    |_|\___/ \___/|_|_|\_\_|\__|
         |___/|_|
          HyperOS 3  →  OnePlus 9 Pro (lemonadep / lahaina)
          Maintainer: Ozyern  |  github.com/ozyern/ReVork_Ports
EOF
echo ""
}

# ──────────────────────────── Tool resolution ────────────────────────────────
# Prefer bundled bin/ over system PATH
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SELF_DIR}/bin"
export PATH="${BIN_DIR}:${PATH}"

need_tool() {
    local t="$1"
    if ! command -v "$t" &>/dev/null; then
        log_err "Required tool not found: $t"
        log_err "Run:  sudo ./setup.sh   to install all dependencies."
        exit 1
    fi
}

check_all_tools() {
    log_step "Checking required tools"
    local missing=0
    for t in unzip python3 zip; do
        if command -v "$t" &>/dev/null; then
            log_ok "  $t → $(command -v "$t")"
        else
            log_err "  $t → NOT FOUND"
            missing=$((missing+1))
        fi
    done
    # Optional but preferred
    for t in magiskboot fsck.erofs mkfs.erofs debugfs e2fsck brotli 7z lpdump; do
        if command -v "$t" &>/dev/null; then
            log_ok "  $t → $(command -v "$t")"
        else
            log_warn "  $t → not found (will use fallback)"
        fi
    done
    [[ $missing -gt 0 ]] && die "Missing $missing required tools. Run sudo ./setup.sh"
    log_ok "All required tools present"
}

# ──────────────────────────── WSL detection ──────────────────────────────────
is_wsl() {
    grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (sudo ./port.sh ...)"
    fi
}

# ──────────────────────────── ZIP helpers ────────────────────────────────────
zip_contains() {
    local zip="$1" pattern="$2"
    unzip -l "$zip" 2>/dev/null | grep -q "$pattern"
}

detect_zip_type() {
    # Returns: payload | super | raw_img | fastboot_sparse | unknown
    # IMPORTANT: this function echoes its return value — NO log_info/log_warn
    # calls allowed inside (they write to stdout and corrupt the return value).
    # All diagnostic output must go to stderr (&2) only.
    local zip="$1"

    # Print contents to stderr so it shows in terminal but doesn't corrupt $()
    echo "[INFO]  $(basename "$zip") contents (top 15):" >&2
    unzip -l "$zip" 2>/dev/null | tail -n +4 | head -15 | awk '{print "    "$NF}' >&2

    local listing
    listing=$(unzip -l "$zip" 2>/dev/null)

    if echo "$listing" | grep -qi "payload\.bin"; then
        echo "payload"
    elif echo "$listing" | grep -qi "super\.img"; then
        echo "super"
    elif echo "$listing" | grep -qi "system\.img"; then
        echo "raw_img"
    elif echo "$listing" | grep -qi "system\.new\.dat"; then
        echo "fastboot_sparse"
    elif echo "$listing" | grep -qi "\.new\.dat\.br"; then
        echo "fastboot_sparse"
    else
        if command -v 7z &>/dev/null; then
            local listing7z
            listing7z=$(7z l "$zip" 2>/dev/null)
            if echo "$listing7z" | grep -qi "payload\.bin"; then echo "payload"; return; fi
            if echo "$listing7z" | grep -qi "super\.img";   then echo "super";   return; fi
            if echo "$listing7z" | grep -qi "system\.img";  then echo "raw_img"; return; fi
        fi
        echo "unknown"
    fi
}

# ──────────────────────────── Filesystem detection ───────────────────────────
detect_fs() {
    # Uses dd+od to read magic bytes — works in WSL (no 'file' command needed)
    local img="$1"
    [[ ! -f "$img" ]] && { echo "missing"; return; }

    # erofs magic: 0xE0F5E1E2 at offset 1024 → LE bytes: e2 e1 f5 e0
    local erofs_magic
    erofs_magic=$(dd if="$img" bs=1 skip=1024 count=4 2>/dev/null | od -A n -t x1 | tr -d ' \n')
    if [[ "$erofs_magic" == "e2e1f5e0" ]]; then
        echo "erofs"; return
    fi

    # ext4 magic: 0xEF53 at offset 1080 → LE bytes: 53 ef
    local ext4_magic
    ext4_magic=$(dd if="$img" bs=1 skip=1080 count=2 2>/dev/null | od -A n -t x1 | tr -d ' \n')
    if [[ "$ext4_magic" == "53ef" ]]; then
        echo "ext4"; return
    fi

    echo "unknown"
}

# ──────────────────────────── Image extraction ───────────────────────────────
extract_img() {
    local img="$1" dest="$2"
    mkdir -p "$dest"

    local fs
    fs=$(detect_fs "$img")
    log_debug "  detect_fs($img) → $fs"

    case "$fs" in
        erofs)
            log_info "  Extracting erofs: $(basename "$img") → $dest"
            fsck.erofs --extract="$dest" "$img" 2>/dev/null || true
            if [[ "$(find "$dest" -mindepth 1 | wc -l)" -gt 0 ]]; then
                log_ok "  erofs extracted (--extract=DIR)"
                return 0
            fi
            fsck.erofs --extract "$dest" "$img" 2>/dev/null || true
            if [[ "$(find "$dest" -mindepth 1 | wc -l)" -gt 0 ]]; then
                log_ok "  erofs extracted (--extract DIR)"
                return 0
            fi
            if command -v dump.erofs &>/dev/null; then
                dump.erofs --extract="$dest" "$img" 2>/dev/null || true
                if [[ "$(find "$dest" -mindepth 1 | wc -l)" -gt 0 ]]; then
                    log_ok "  erofs extracted (dump.erofs)"
                    return 0
                fi
            fi
            log_err "  erofs extraction failed for $(basename "$img")"
            return 1
            ;;
        ext4)
            log_info "  Extracting ext4: $(basename "$img") → $dest"
            if command -v debugfs &>/dev/null; then
                debugfs -R "rdump / $dest" "$img" 2>/dev/null
                log_ok "  ext4 extracted (debugfs)"
            else
                log_err "  debugfs not found, cannot extract ext4 image"
                return 1
            fi
            ;;
        *)
            # Last-ditch: try both tools and see which one doesn't produce empty dir
            log_warn "  Unknown FS for $(basename "$img"), trying brute-force..."
            fsck.erofs --extract="$dest" "$img" 2>/dev/null || true
            if [[ "$(find "$dest" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]]; then
                log_ok "  brute-force erofs worked"
                return 0
            fi
            if command -v debugfs &>/dev/null; then
                debugfs -R "rdump / $dest" "$img" 2>/dev/null || true
            fi
            if [[ "$(find "$dest" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ]]; then
                log_err "  Brute-force extraction also failed for $(basename "$img")"
                return 1
            fi
            ;;
    esac
    log_debug "  Extracted $(find "$dest" -type f | wc -l) files from $(basename "$img")"
}

# ──────────────────────────── payload.bin extraction ─────────────────────────
extract_payload() {
    local zip="$1" out_dir="$2"
    log_info "  Detected payload.bin OTA format"
    mkdir -p "$out_dir"

    # Extract payload.bin from zip
    unzip -j "$zip" "payload.bin" -d "$out_dir" || die "Failed to extract payload.bin from $zip"

    local payload="${out_dir}/payload.bin"
    local dumper="${SELF_DIR}/payload_dumper.py"
    local pdg="${BIN_DIR}/payload-dumper-go"

    # Also extract payload_properties.txt (needed by some tools)
    unzip -j "$zip" "payload_properties.txt" -d "$out_dir" 2>/dev/null || true

    # ── Check if this is a delta (incremental) OTA ───────────────────────────
    # Delta OTAs have FILE_HASH / SOURCE_* in properties, full OTAs have only FILE_SIZE
    local props_file="${out_dir}/payload_properties.txt"
    if [[ -f "$props_file" ]] && grep -q "SOURCE_BUILD" "$props_file" 2>/dev/null; then
        log_err "  ╔══════════════════════════════════════════════════════════╗"
        log_err "  ║  DELTA (INCREMENTAL) OTA DETECTED — CANNOT USE THIS ROM ║"
        log_err "  ╚══════════════════════════════════════════════════════════╝"
        log_err "  This is a differential OTA that patches an existing device."
        log_err "  It CANNOT be extracted standalone — it needs the source build."
        log_err ""
        log_err "  You need a FULL OTA (also called 'full package' or 'factory OTA')."
        log_err "  For HyperOS 3: download from xiaomifirmwareupdater.com"
        log_err "  For OOS14: download from oxygenos.plus or OnePlus community"
        log_err "  Look for 'Full OTA' or files >3GB (delta OTAs are usually <1GB)"
        rm -f "$payload" "$props_file"
        die "Please re-download a FULL OTA ROM and try again"
    fi

    # ── Check payload size — delta OTAs are tiny, full OTAs are large ────────
    local payload_size
    payload_size=$(stat -c%s "$payload" 2>/dev/null || echo 0)
    if [[ $payload_size -lt 104857600 ]]; then  # < 100MB is suspicious
        log_warn "  payload.bin is only $(( payload_size / 1048576 ))MB — this may be a delta OTA"
        log_warn "  If extraction produces 0-byte images, you need a FULL OTA ROM"
    fi

    # ── Try payload-dumper-go first (handles all OTA types best) ─────────────
    if [[ -f "$pdg" ]] || command -v payload-dumper-go &>/dev/null; then
        local pdg_bin="${pdg}"
        command -v payload-dumper-go &>/dev/null && pdg_bin="payload-dumper-go"
        log_info "  Using payload-dumper-go"
        "$pdg_bin" -output-dir "$out_dir" "$payload" 2>/dev/null || \
        "$pdg_bin" -o "$out_dir" "$payload" 2>/dev/null || \
        "$pdg_bin" "$payload" "$out_dir" 2>/dev/null || {
            log_warn "  payload-dumper-go failed, falling back to payload_dumper.py"
        }
        # Verify we got real images
        local img_count non_empty
        img_count=$(find "$out_dir" -name "*.img" | wc -l)
        non_empty=$(find "$out_dir" -name "*.img" -size +1k | wc -l)
        if [[ $non_empty -gt 5 ]]; then
            log_ok "  payload-dumper-go: $non_empty/$img_count images extracted with data"
            rm -f "$payload" "$props_file"
            return 0
        fi
        log_warn "  payload-dumper-go produced $non_empty non-empty images — falling back"
    fi

    # ── Fallback: bundled payload_dumper.py ───────────────────────────────────
    if [[ -f "$dumper" ]]; then
        log_info "  Using bundled payload_dumper.py"
        python3 "$dumper" "$payload" --out "$out_dir" || {
            local got non_empty2
            got=$(find "$out_dir" -name "*.img" | wc -l)
            non_empty2=$(find "$out_dir" -name "*.img" -size +1k | wc -l)
            if [[ $non_empty2 -lt 3 ]]; then
                log_err "  Only $non_empty2 non-empty images extracted out of $got"
                log_err "  This is almost certainly a DELTA OTA — you need a FULL OTA ROM"
                rm -f "$payload" "$props_file"
                die "Extraction failed — download a FULL OTA ROM (>3GB) and retry"
            fi
            log_warn "  payload_dumper.py had warnings but got $non_empty2 images — continuing"
        }
        # Final check
        local final_empty
        final_empty=$(find "$out_dir" -name "system.img" -size +1k | wc -l)
        if [[ $final_empty -eq 0 ]]; then
            log_err "  system.img is empty — this is a DELTA OTA, not a full OTA"
            die "Download a FULL OTA ROM from xiaomifirmwareupdater.com / oxygenos.plus"
        fi
    else
        die "No payload dumper found. payload_dumper.py must be next to port.sh"
    fi

    rm -f "$payload" "$props_file"
    log_ok "  payload.bin extracted → $out_dir"
}

# ──────────────────────────── super.img handling ─────────────────────────────
extract_super() {
    local zip="$1" work="$2"
    log_info "  Detected super.img format"
    mkdir -p "$work"
    unzip -j "$zip" "super.img" -d "$work" 2>/dev/null || true
    unzip -j "$zip" "super.img.br" -d "$work" 2>/dev/null || true

    if [[ -f "${work}/super.img.br" ]]; then
        log_info "  Decompressing super.img.br"
        brotli -d "${work}/super.img.br" -o "${work}/super.img" || die "brotli decompression failed"
    fi

    [[ ! -f "${work}/super.img" ]] && die "super.img not found after extraction"

    local lpunpack_bin
    lpunpack_bin="${BIN_DIR}/lpunpack"
    if ! command -v lpunpack &>/dev/null && [[ ! -f "$lpunpack_bin" ]]; then
        die "lpunpack not found. Run sudo ./setup.sh"
    fi

    log_info "  Running lpunpack on super.img"
    lpunpack "${work}/super.img" "$work" || die "lpunpack failed"
    log_ok "  super.img split into partitions"
}

# ──────────────────────────── ROM extraction dispatcher ──────────────────────
extract_rom() {
    local label="$1"
    local zip="$2"
    local work="$3"
    mkdir -p "$work"

    local zip_type
    zip_type=$(detect_zip_type "$zip")   # detect_zip_type logs to stderr internally
    log_info "[$label] ROM format detected: ${BOLD}${zip_type}${NC}"

    case "$zip_type" in
        payload)
            extract_payload "$zip" "$work"
            ;;
        super)
            extract_super "$zip" "$work"
            ;;
        raw_img|fastboot_sparse)
            log_info "  Extracting raw images from zip"
            unzip -o "$zip" "*.img" -d "$work" 2>/dev/null || true
            # Handle .new.dat.br sparse format
            if zip_contains "$zip" ".new.dat.br"; then
                unzip -o "$zip" "*.new.dat.br" "*.transfer.list" -d "$work" 2>/dev/null || true
                for br_file in "$work"/*.new.dat.br; do
                    [[ -f "$br_file" ]] || continue
                    local base="${br_file%.new.dat.br}"
                    brotli -d "$br_file" -o "${base}.new.dat" 2>/dev/null || true
                    local part_name
                    part_name=$(basename "$base")
                    if [[ -f "${base}.transfer.list" && -f "${base}.new.dat" ]]; then
                        python3 "${SELF_DIR}/payload_dumper.py" --sdat2img \
                            "${base}.transfer.list" "${base}.new.dat" "${base}.img" 2>/dev/null || true
                    fi
                done
            fi
            log_ok "  Raw images extracted → $work"
            ;;
        *)
            log_err "[$label] Cannot determine ZIP format for: $(basename "$zip")"
            log_err "  Expected one of: payload.bin / super.img / system.img / system.new.dat.br"
            log_err "  Actual ZIP listing above — check if the file is corrupt or a different format"
            log_err "  Try:  unzip -l \"$zip\" | head -30"
            die "Unknown ZIP format — aborting"
            ;;
    esac
}

# ──────────────────────────── Image repack ───────────────────────────────────
repack_img() {
    local source_dir="$1"
    local output_img="$2"
    local fs_type="${3:-erofs}"    # erofs | ext4
    local label="${4:-partition}"

    log_info "  Repacking $label → $(basename "$output_img") ($fs_type)"

    if [[ "$(find "$source_dir" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ]]; then
        log_warn "  Skipping $label — source dir is empty"
        return 1
    fi

    case "$fs_type" in
        erofs)
            if command -v mkfs.erofs &>/dev/null; then
                mkfs.erofs -zlz4hc "$output_img" "$source_dir" 2>/dev/null \
                    || mkfs.erofs "$output_img" "$source_dir" 2>/dev/null \
                    || { log_err "mkfs.erofs failed for $label"; return 1; }
            else
                log_warn "  mkfs.erofs not found — falling back to ext4 for $label"
                make_ext4_img "$source_dir" "$output_img" "$label"
            fi
            ;;
        ext4)
            make_ext4_img "$source_dir" "$output_img" "$label"
            ;;
    esac
    log_ok "  Repacked $label ($(du -sh "$output_img" | cut -f1))"
}

make_ext4_img() {
    local source_dir="$1" output_img="$2" label="$3"
    local size_bytes
    size_bytes=$(du -sb "$source_dir" | cut -f1)
    local size_mb=$(( (size_bytes / 1048576) + 256 ))
    dd if=/dev/zero of="$output_img" bs=1M count="$size_mb" 2>/dev/null
    mkfs.ext4 -L "$label" -d "$source_dir" "$output_img" 2>/dev/null \
        || { log_err "mkfs.ext4 failed for $label"; return 1; }
}

# ──────────────────────────── build.prop helpers ─────────────────────────────
prop_set() {
    local file="$1" key="$2" val="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

prop_delete() {
    local file="$1" key="$2"
    sed -i "/^${key}=/d" "$file"
}

# ──────────────────────────── XML helpers ────────────────────────────────────
xml_set_attr() {
    # xml_set_attr file.xml tagname attrname newvalue
    local file="$1" tag="$2" attr="$3" val="$4"
    python3 - "$file" "$tag" "$attr" "$val" << 'PY'
import sys, re
f,tag,attr,val = sys.argv[1:]
txt = open(f).read()
def rep(m):
    inner = re.sub(r'(?<=\s)' + re.escape(attr) + r'="[^"]*"', attr+'="'+val+'"', m.group(0))
    if attr+'="' not in inner:
        inner = inner.rstrip('>').rstrip('/') + ' ' + attr + '="' + val + '">'
    return inner
txt = re.sub(r'<' + re.escape(tag) + r'[^>]*>', rep, txt)
open(f,'w').write(txt)
PY
}

# ──────────────────────────── SELinux CIL helpers ────────────────────────────
append_cil_rules() {
    local cil_file="$1"
    shift
    # Each arg is a CIL allow rule
    for rule in "$@"; do
        grep -qF "$rule" "$cil_file" 2>/dev/null || echo "$rule" >> "$cil_file"
    done
}

# ──────────────────────────── Boot image helpers ─────────────────────────────
unpack_boot() {
    local img="$1" work="$2"
    mkdir -p "$work"
    if command -v magiskboot &>/dev/null; then
        cp "$img" "${work}/boot.img"
        ( cd "$work" && magiskboot unpack boot.img ) || die "magiskboot unpack failed"
    else
        die "magiskboot not found — cannot unpack boot image"
    fi
}

repack_boot() {
    local work="$1" output="$2"
    if command -v magiskboot &>/dev/null; then
        ( cd "$work" && magiskboot repack boot.img ) || die "magiskboot repack failed"
        cp "${work}/new-boot.img" "$output"
    else
        die "magiskboot not found — cannot repack boot image"
    fi
}

patch_boot_cmdline() {
    local work="$1" extra="$2"
    local cmdline_file="${work}/header"
    if [[ -f "${work}/cmdline" ]]; then
        echo -n " $extra" >> "${work}/cmdline"
    elif [[ -f "$cmdline_file" ]]; then
        sed -i "s|cmdline=|cmdline= $extra |" "$cmdline_file" 2>/dev/null || true
    fi
}

# ──────────────────────────── File copy helpers ──────────────────────────────
safe_copy() {
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { log_warn "  Source not found: $src"; return 1; }
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst" && log_debug "  Copied: $src → $dst"
}

safe_rsync() {
    local src="$1" dst="$2"
    [[ ! -d "$src" ]] && { log_warn "  Rsync source not found: $src"; return 1; }
    mkdir -p "$dst"
    rsync -aHAX --no-specials --no-devices "$src/" "$dst/" 2>/dev/null || \
        cp -a "$src/." "$dst/"
}

# ──────────────────────────── Timing helpers ─────────────────────────────────
SECONDS=0
elapsed() {
    local s=$SECONDS
    printf "%dm%02ds" $((s/60)) $((s%60))
}
