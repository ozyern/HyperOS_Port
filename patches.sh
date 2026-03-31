#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — patches.sh
# Device-specific patches applied after merge — sourced by port.sh
# =============================================================================

apply_all_patches() {
    local work="$1"
    step "Applying patches (lemonadep / SM8350)"
    _patch_system     "$work/mnt/system"
    _patch_system_ext "$work/mnt/system_ext"
    _patch_product    "$work/mnt/product"
    _patch_vendor     "$work/mnt/vendor"
}

_patch_system() {
    local mnt="$1"
    log "Patching system"

    strip_props "$mnt/system/build.prop"
    apply_prop_overrides "$mnt/system/build.prop"

    local DATE; DATE=$(date +%Y%m%d)
    local bp="$mnt/system/build.prop"
    set_prop "$bp" "ro.oplus.version.release"   "HyperOS_Port"
    set_prop "$bp" "ro.build.fingerprint"       "OnePlus/lemonadep/lemonadep:14/UKQ1.230924.001/R.${DATE}:user/release-keys"
    set_prop "$bp" "ro.build.description"       "lemonadep-user 14 UKQ1.230924.001 R.${DATE} release-keys"
    set_prop "$bp" "persist.sys.usb.config"     "adb"
    set_prop "$bp" "ro.adb.secure"              "0"

    # Silence MIUI service waits on first boot
    local shim="$mnt/etc/init/hyperos_compat.rc"
    mkdir -p "$(dirname "$shim")"
    cat > "$shim" << 'RC'
# HyperOS_Port: stub MIUI services absent on lemonadep
on property:sys.boot_completed=1
    setprop ro.miui.version.code 0
    setprop persist.miui.extm.enable 0
    setprop persist.sys.miui_optimization 0
RC

    patch_init_rc "$mnt"
    success "System patched"
}

_patch_system_ext() {
    local mnt="$1"
    [[ -f "$mnt/build.prop" ]] && {
        strip_props "$mnt/build.prop"
        apply_prop_overrides "$mnt/build.prop"
    }
    # Remove Xiaomi-only permission grants (cause SELinux denials on lemonadep)
    local perms="$mnt/etc/permissions"
    if [[ -d "$perms" ]]; then
        for f in "$perms"/xiaomi*.xml "$perms"/miui*.xml \
                 "$perms"/com.xiaomi*.xml "$perms"/com.miui*.xml; do
            [[ -f "$f" ]] && { rm -f "$f"; log "Removed perm: $(basename "$f")"; }
        done
    fi
    success "system_ext patched"
}

_patch_product() {
    local mnt="$1"
    [[ -f "$mnt/build.prop" ]] && {
        strip_props "$mnt/build.prop"
        apply_prop_overrides "$mnt/build.prop"
    }
    # Remove Xiaomi device-specific RRO overlays that reference absent HALs
    local overlay="$mnt/overlay"
    if [[ -d "$overlay" ]]; then
        for f in "$overlay"/*Xiaomi* "$overlay"/*xiaomi* \
                 "$overlay"/*alioth*  "$overlay"/*haydn*  "$overlay"/*fuxi*; do
            [[ -f "$f" ]] && { rm -f "$f"; log "Removed overlay: $(basename "$f")"; }
        done
    fi
    success "product patched"
}

_patch_vendor() {
    local mnt="$1"
    patch_fstab "$mnt"
    [[ -f "$mnt/build.prop" ]] && \
        set_prop "$mnt/build.prop" "ro.vendor.build.fingerprint" \
            "OnePlus/lemonadep/lemonadep:14/UKQ1.230924.001/R.$(date +%Y%m%d):user/release-keys"
    success "vendor patched"
}
