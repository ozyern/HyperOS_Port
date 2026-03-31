#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — patches.sh
# Device-specific patches applied after merge — sourced by port.sh
# =============================================================================

# Called after all partition images are mounted in $WORK/mnt/
apply_all_patches() {
    local work="$1"
    step "Applying device-specific patches (lemonadep / SM8350)"

    _patch_system       "$work/mnt/system"
    _patch_system_ext   "$work/mnt/system_ext"
    _patch_product      "$work/mnt/product"
    _patch_vendor       "$work/mnt/vendor"
}

# ── System partition patches ──────────────────────────────────────────────────
_patch_system() {
    local mnt="$1"
    log "Patching system partition"

    # 1. Strip MIUI props, apply OnePlus identity
    strip_props "$mnt/system/build.prop"
    apply_prop_overrides "$mnt/system/build.prop"

    # 2. Force disable MIUI update app (references Xiaomi servers)
    local updater="$mnt/app/MiuiSystemUpdate"
    [[ -d "$updater" ]] && rm -rf "$updater" && log "Removed MiuiSystemUpdate"

    # 3. Disable HyperOS telemetry
    local analytics="$mnt/app/MiuiAnalytics"
    [[ -d "$analytics" ]] && rm -rf "$analytics" && log "Removed MiuiAnalytics"

    # 4. Remove Xiaomi account framework (incompatible, causes ANRs)
    local xiaomi_acct="$mnt/priv-app/XiaomiAccount"
    [[ -d "$xiaomi_acct" ]] && rm -rf "$xiaomi_acct" && log "Removed XiaomiAccount"

    # 5. Add OnePlus-specific props
    local bp="$mnt/system/build.prop"
    set_prop "$bp" "ro.oplus.version.release"      "HyperOS_Port"
    set_prop "$bp" "ro.oplus.build.fingerprint"    "OnePlus/lemonadep/lemonadep:14/UKQ1.230924.001/R.$(date +%Y%m%d):user/release-keys"
    set_prop "$bp" "ro.build.fingerprint"          "OnePlus/lemonadep/lemonadep:14/UKQ1.230924.001/R.$(date +%Y%m%d):user/release-keys"
    set_prop "$bp" "ro.build.description"          "lemonadep-user 14 UKQ1.230924.001 R.$(date +%Y%m%d) release-keys"

    # 6. Ensure ADB & developer options props
    set_prop "$bp" "persist.sys.usb.config"        "adb"
    set_prop "$bp" "ro.adb.secure"                 "0"

    patch_init_rc "$mnt"
    success "System partition patched"
}

# ── system_ext partition patches ──────────────────────────────────────────────
_patch_system_ext() {
    local mnt="$1"
    log "Patching system_ext partition"

    # build.prop exists in system_ext on HyperOS
    local bp="$mnt/build.prop"
    if [[ -f "$bp" ]]; then
        strip_props "$bp"
        apply_prop_overrides "$bp"
    fi

    # Remove Xiaomi-specific permissions that grant capabilities to absent apps
    local perms_dir="$mnt/etc/permissions"
    if [[ -d "$perms_dir" ]]; then
        for f in "$perms_dir"/xiaomi*.xml "$perms_dir"/miui*.xml \
                 "$perms_dir"/com.xiaomi*.xml "$perms_dir"/com.miui*.xml; do
            [[ -f "$f" ]] && { rm -f "$f"; log "Removed $(basename "$f")"; }
        done
    fi

    success "system_ext partition patched"
}

# ── Product partition patches ─────────────────────────────────────────────────
_patch_product() {
    local mnt="$1"
    log "Patching product partition"

    local bp="$mnt/build.prop"
    if [[ -f "$bp" ]]; then
        strip_props "$bp"
        apply_prop_overrides "$bp"
    fi

    # Keep HyperOS overlays but remove Xiaomi device-specific RROs
    # that reference Xiaomi display/sensor HAL features
    local overlay_dir="$mnt/overlay"
    if [[ -d "$overlay_dir" ]]; then
        for f in "$overlay_dir"/*Xiaomi* "$overlay_dir"/*xiaomi* \
                 "$overlay_dir"/*Mi11* "$overlay_dir"/*alioth*; do
            [[ -f "$f" ]] && { rm -f "$f"; log "Removed Xiaomi overlay: $(basename "$f")"; }
        done
    fi

    success "Product partition patched"
}

# ── Vendor partition patches (OxygenOS base) ──────────────────────────────────
_patch_vendor() {
    local mnt="$1"
    log "Patching vendor partition (OxygenOS base)"

    # Patch fstab to remove mi_ext
    patch_fstab "$mnt"

    # The OxygenOS vendor build.prop — update to reflect HyperOS port
    local bp="$mnt/build.prop"
    if [[ -f "$bp" ]]; then
        set_prop "$bp" "ro.vendor.build.fingerprint" \
            "OnePlus/lemonadep/lemonadep:14/UKQ1.230924.001/R.$(date +%Y%m%d):user/release-keys"
    fi

    # Ensure Qualcomm thermal HAL config is present (critical for SM8350)
    local thermal_conf="$mnt/etc/thermal-engine.conf"
    if [[ ! -f "$thermal_conf" ]]; then
        warn "thermal-engine.conf missing from vendor — device may throttle hard"
    fi

    success "Vendor partition patched"
}

# ── Compatibility shims ────────────────────────────────────────────────────────
# HyperOS expects some MIUI-specific binder services that won't be present.
# We add stub property entries so service managers don't crash waiting for them.
install_compat_shims() {
    local system_mnt="$1"
    log "Installing HyperOS→OnePlus compatibility shims"

    local shim_rc="$system_mnt/etc/init/hyperos_compat.rc"
    cat > "$shim_rc" <<'RC'
# HyperOS_Port: stub out MIUI services that won't be present
# Prevents servicemanager from blocking on missing Xiaomi HALs
on property:sys.boot_completed=1
    setprop ro.miui.version.code 0
    setprop persist.miui.extm.enable 0
    setprop persist.sys.miui_optimization 0
RC
    success "Installed compatibility shims"
}
