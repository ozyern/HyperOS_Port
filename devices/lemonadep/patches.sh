#!/usr/bin/env bash
# =============================================================================
# devices/lemonadep/patches.sh — OnePlus 9 Pro specific patches
# Called by port.sh after base partition merge
# Maintainer: Ozyern
# =============================================================================

patch_build_props() {
    log_step "Patching build.prop (lemonadep / lahaina / Android 16)"
    local PORT_DIR="$1"

    for prop_file in \
        "${PORT_DIR}/system/system/build.prop" \
        "${PORT_DIR}/system/build.prop" \
        "${PORT_DIR}/vendor/build.prop" \
        "${PORT_DIR}/product/build.prop" \
        "${PORT_DIR}/system_ext/build.prop"
    do
        [[ -f "$prop_file" ]] || continue
        log_info "  → $prop_file"

        # ── Device identity ──────────────────────────────────────────────────
        prop_set "$prop_file" ro.product.brand          "OnePlus"
        prop_set "$prop_file" ro.product.manufacturer   "OnePlus"
        prop_set "$prop_file" ro.product.device         "lemonadep"
        prop_set "$prop_file" ro.product.name           "lemonadep"
        prop_set "$prop_file" ro.product.model          "LE2123"
        prop_set "$prop_file" ro.product.vendor.brand   "OnePlus"
        prop_set "$prop_file" ro.product.vendor.device  "lemonadep"
        prop_set "$prop_file" ro.product.vendor.model   "LE2123"
        prop_set "$prop_file" ro.product.odm.brand      "OnePlus"
        prop_set "$prop_file" ro.product.odm.device     "lemonadep"

        # ── SoC ──────────────────────────────────────────────────────────────
        prop_set "$prop_file" ro.board.platform          "lahaina"
        prop_set "$prop_file" ro.hardware                "lahaina"
        prop_set "$prop_file" ro.product.cpu.abi         "arm64-v8a"
        prop_set "$prop_file" ro.product.cpu.abilist     "arm64-v8a,armeabi-v7a,armeabi"
        prop_set "$prop_file" ro.product.cpu.abilist32   "armeabi-v7a,armeabi"
        prop_set "$prop_file" ro.product.cpu.abilist64   "arm64-v8a"
        prop_set "$prop_file" ro.product.cpu.pagesize.max "4096"

        # ── Android 16 / API 36 ──────────────────────────────────────────────
        prop_set "$prop_file" ro.build.version.release   "16"
        prop_set "$prop_file" ro.build.version.sdk       "36"
        prop_set "$prop_file" ro.build.version.codename  "REL"

        # ── VNDK / Treble bridge (vendor = OOS14 → Android 14 = API 34) ─────
        prop_set "$prop_file" ro.vndk.version             "34"
        prop_set "$prop_file" ro.board.api_level           "34"
        prop_set "$prop_file" ro.board.first_api_level     "30"
        prop_set "$prop_file" ro.vendor.api_level          "34"
        prop_set "$prop_file" debug.vintf.enforce_hal      "false"

        # ── Display (525 dpi, 120 Hz LTPO) ───────────────────────────────────
        prop_set "$prop_file" ro.sf.lcd_density            "525"
        prop_set "$prop_file" persist.sys.sf.color_saturation "1.0"
        prop_set "$prop_file" ro.surface_flinger.enable_frame_rate_override "true"
        prop_set "$prop_file" ro.surface_flinger.frame_rate_multiple_threshold "60"

        # ── ADPF (Android 16 Adaptive Performance Framework v3) ──────────────
        prop_set "$prop_file" ro.adpf.fmq_ea_supported    "true"
        prop_set "$prop_file" ro.adpf.use_hints            "true"

        # ── Predictive back / WM extensions (Android 16 requirement) ─────────
        prop_set "$prop_file" persist.wm.extensions.enabled "true"

        # ── Health HAL v3 (Android 16 requirement) ────────────────────────────
        prop_set "$prop_file" ro.hardware.health            "default"

        # ── RIL / Telephony ──────────────────────────────────────────────────
        prop_set "$prop_file" persist.vendor.radio.atfwd.start "true"
        prop_set "$prop_file" persist.radio.multisim.config  "ssss"
        prop_set "$prop_file" persist.vendor.ims.disableADBLogs "3"
        prop_set "$prop_file" persist.dbg.volte_avail_ovr   "1"
        prop_set "$prop_file" persist.dbg.vt_avail_ovr      "1"
        prop_set "$prop_file" persist.dbg.wfc_avail_ovr     "1"
        prop_set "$prop_file" telephony.lteOnCdmaDevice      "1"

        # ── Camera ───────────────────────────────────────────────────────────
        prop_set "$prop_file" persist.vendor.camera.privapp.list "com.oneplus.camera"
        prop_set "$prop_file" ro.vendor.camera.extensions.package "com.qti.camera.extentions"

        # ── Charging (Warp 65T + AirVOOC 50W) ───────────────────────────────
        prop_set "$prop_file" ro.charger.enable_suspend      "1"
        prop_set "$prop_file" persist.vendor.cp.fcc_main     "3300"
        prop_set "$prop_file" vendor.battery.charge.fcc      "4500"

        # ── Fingerprint (Goodix FOD) ──────────────────────────────────────────
        prop_set "$prop_file" ro.hardware.fingerprint        "fpc"
        prop_set "$prop_file" persist.vendor.fingerprint.sensor_type "optical"

        # ── Bluetooth ─────────────────────────────────────────────────────────
        prop_set "$prop_file" persist.bluetooth.a2dp_offload.disabled "false"
        prop_set "$prop_file" persist.vendor.bt.a2dp.aac_whitelist    "true"
        prop_set "$prop_file" persist.vendor.qcom.bluetooth.enable.splita2dp "true"

        # ── Wi-Fi ─────────────────────────────────────────────────────────────
        prop_set "$prop_file" wifi.interface                 "wlan0"
        prop_set "$prop_file" persist.vendor.data.iwlan.enable "true"

        # ── Audio ─────────────────────────────────────────────────────────────
        prop_set "$prop_file" audio.deep_buffer.media        "true"
        prop_set "$prop_file" persist.vendor.audio.fluence.voicecall "true"
        prop_set "$prop_file" persist.vendor.audio.fluence.speaker "true"

        # ── Port branding / credit ────────────────────────────────────────────
        prop_set "$prop_file" ro.port.maintainer            "Ozyern"
        prop_set "$prop_file" ro.port.device                "lemonadep"
        prop_set "$prop_file" ro.port.source                "HyperOS3"

        # ── Remove Xiaomi-specific props that break OP9Pro ────────────────────
        prop_delete "$prop_file" "ro.miui.ui.version.code"
        prop_delete "$prop_file" "ro.miui.ui.version.name"
    done
    log_ok "build.prop patched"
}

patch_fstab() {
    log_step "Patching fstab (UFS 3.1 / f2fs / A/B)"
    local PORT_DIR="$1"

    local fstab_dst="${PORT_DIR}/vendor/etc/fstab.lemonadep"
    mkdir -p "$(dirname "$fstab_dst")"
    cat > "$fstab_dst" << 'FSTAB'
# fstab.lemonadep — OnePlus 9 Pro  (generated by HyperOS3-Port-lemonadep)
# <dev>                                     <mount>     <type>     <mntflags>                                   <fsmgr>
/dev/block/bootdevice/by-name/system        /system     erofs      ro,barrier=1                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
/dev/block/bootdevice/by-name/system_ext    /system_ext erofs      ro,barrier=1                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
/dev/block/bootdevice/by-name/vendor        /vendor     erofs      ro,barrier=1                                 wait,slotselect,avb,logical,first_stage_mount
/dev/block/bootdevice/by-name/product       /product    erofs      ro,barrier=1                                 wait,slotselect,avb,logical,first_stage_mount
/dev/block/bootdevice/by-name/odm           /odm        erofs      ro,barrier=1                                 wait,slotselect,avb,logical,first_stage_mount
/dev/block/bootdevice/by-name/userdata      /data       f2fs       noatime,nosuid,nodev,discard,reserve_root=32768,resgid=1065,fsync_mode=nobarrier latemount,wait,check,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,keydirectory=/metadata/vold/metadata_encryption,quota,formattable,sysfs_path=/sys/devices/platform/soc/1d84000.ufshc,checkpoint=fs
/dev/block/bootdevice/by-name/metadata      /metadata   ext4       noatime,nosuid,nodev,discard                 wait,formattable,first_stage_mount
/dev/block/bootdevice/by-name/persist       /persist    ext4       noatime,nosuid,nodev,barrier=1               wait,first_stage_mount
/dev/block/bootdevice/by-name/modem         /firmware   vfat       ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337,context=u:object_r:firmware_file:s0 wait,slotselect
/dev/block/bootdevice/by-name/dsp           /dsp        ext4       ro,nosuid,nodev,barrier=1                    wait,slotselect
/dev/block/bootdevice/by-name/bluetooth     /vendor/bt_firmware vfat ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337,context=u:object_r:bt_firmware_file:s0 wait,slotselect
FSTAB
    log_ok "fstab.lemonadep written"
}

patch_camera() {
    log_step "Patching Camera HAL (OOS14 blobs + HyperOS3 system)"
    local PORT_DIR="$1"
    local OOS_VENDOR="$2"

    # Remove Xiaomi camera shims that reference miui-only services
    local miui_cam_shims=(
        "libMiCamHAL.so"
        "libMiCamUtils.so"
        "libMiSdkCamera.so"
    )
    for shim in "${miui_cam_shims[@]}"; do
        find "${PORT_DIR}/vendor" -name "$shim" -delete 2>/dev/null && \
            log_info "  Removed Xiaomi shim: $shim"
    done

    # Patch camera provider manifest to @2.7 (what OOS14 ships)
    local manifest="${PORT_DIR}/vendor/etc/vintf/manifest.xml"
    if [[ -f "$manifest" ]]; then
        sed -i 's|android.hardware.camera.provider@[0-9.]*|android.hardware.camera.provider@2.7|g' "$manifest"
        log_ok "  Camera HAL manifest patched → @2.7"
    fi

    # Patch camxoverridesettings for OP9Pro sensors
    local cam_override="${PORT_DIR}/vendor/etc/camera/camxoverridesettings.txt"
    if [[ -f "$cam_override" ]]; then
        grep -q "board_name" "$cam_override" || \
            echo "board_name=lemonadep" >> "$cam_override"
        log_ok "  camxoverridesettings patched"
    fi

    # Copy OP9Pro camera blobs from OOS vendor if available and different from dest
    if [[ -d "$OOS_VENDOR" ]]; then
        for d in camera camera_server; do
            local src64="${OOS_VENDOR}/lib64/${d}"
            local dst64="${PORT_DIR}/vendor/lib64/${d}"
            if [[ -d "$src64" ]] && [[ "$(realpath "$src64")" != "$(realpath "$dst64" 2>/dev/null)" ]]; then
                mkdir -p "$dst64"
                cp -af "${src64}/." "${dst64}/"
                log_ok "  Copied OOS vendor camera blobs: lib64/${d}"
            fi
            local src32="${OOS_VENDOR}/lib/${d}"
            local dst32="${PORT_DIR}/vendor/lib/${d}"
            if [[ -d "$src32" ]] && [[ "$(realpath "$src32")" != "$(realpath "$dst32" 2>/dev/null)" ]]; then
                mkdir -p "$dst32"
                cp -af "${src32}/." "${dst32}/"
            fi
        done
    fi
    log_ok "Camera HAL patched"
}

patch_ril() {
    log_step "Patching RIL / Modem (OOS14 qcrild stack)"
    local PORT_DIR="$1"
    local OOS_VENDOR="$2"

    # Remove MIUI RIL shims
    local miui_ril=(
        "libril-xiaomi.so"
        "libMiuiRil.so"
        "MiuiTelephonyService.apk"
    )
    for f in "${miui_ril[@]}"; do
        find "${PORT_DIR}" -name "$f" -delete 2>/dev/null && \
            log_info "  Removed MIUI RIL component: $f"
    done

    # Copy OOS14 RIL blobs (qcrild, IMS, etc.)
    if [[ -d "$OOS_VENDOR" ]] && [[ "$(realpath "$OOS_VENDOR")" != "$(realpath "${PORT_DIR}/vendor" 2>/dev/null)" ]]; then
        for ril_bin in qcrild qti-telephony-hidl-wrapper; do
            if [[ -f "${OOS_VENDOR}/bin/${ril_bin}" ]]; then
                cp -af "${OOS_VENDOR}/bin/${ril_bin}" "${PORT_DIR}/vendor/bin/" && \
                    log_ok "  Copied RIL binary: $ril_bin"
            fi
        done
    fi

    # Write qcrild init RC
    mkdir -p "${PORT_DIR}/vendor/etc/init"
    cat > "${PORT_DIR}/vendor/etc/init/qcrild.rc" << 'RC'
service qcrild /vendor/bin/qcrild
    class main
    user radio
    group radio cache inet misc audio sdcard_r sdcard_rw diag oem_2901
    disabled

on property:ro.vendor.ril.mbn_copy_completed=1
    start qcrild
RC
    log_ok "RIL patched"
}

patch_display_120hz() {
    log_step "Patching display (120 Hz LTPO + HDR10+)"
    local PORT_DIR="$1"

    local overlay_dir="${PORT_DIR}/vendor/overlay"
    mkdir -p "$overlay_dir"

    # Write VRR display config
    local display_cfg="${PORT_DIR}/vendor/etc/displayconfig"
    mkdir -p "$display_cfg"
    cat > "${display_cfg}/display_id_0.xml" << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- OnePlus 9 Pro LTPO 120Hz display config — generated by HyperOS3-Port-lemonadep -->
<DisplayConfiguration>
  <Name>E4 6.7 inch LTPO AMOLED</Name>
  <ColorTransform>0.965 -0.012 0.047 -0.047 1.067 -0.020 0.001 -0.034 1.033</ColorTransform>
  <densityMapping>
    <density>480</density>
  </densityMapping>
  <refreshRateConfigurations>
    <refreshRateConfiguration type="default" refreshRate="120"/>
    <refreshRateConfiguration type="low" refreshRate="60"/>
    <refreshRateConfiguration type="min" refreshRate="1"/>
  </refreshRateConfigurations>
  <vrr>
    <enabled>true</enabled>
    <minRefreshRate>1</minRefreshRate>
    <maxRefreshRate>120</maxRefreshRate>
    <idleTimerMs>250</idleTimerMs>
  </vrr>
  <hdr>
    <hdrCapabilities>
      <HDR_TYPE_HDR10>true</HDR_TYPE_HDR10>
      <HDR_TYPE_HDR10_PLUS>true</HDR_TYPE_HDR10_PLUS>
      <maxLuminance>1000</maxLuminance>
      <maxAverageLuminance>120</maxAverageLuminance>
      <minLuminance>0.0</minLuminance>
    </hdrCapabilities>
  </hdr>
</DisplayConfiguration>
XML
    log_ok "  display_id_0.xml written"

    # Remove Xiaomi overlays that hardcode 60Hz or wrong refresh
    for overlay_search_dir in "${PORT_DIR}/product/overlay" "${PORT_DIR}/system/system/overlay" "${PORT_DIR}/system/overlay"; do
        [[ -d "$overlay_search_dir" ]] || continue
        find "$overlay_search_dir" -name "*.apk" 2>/dev/null | while read -r apk; do
            if strings "$apk" 2>/dev/null | grep -qE "maxRefreshRate.*[^1]60|<integer.*>60<"; then
                log_info "  Removing 60Hz overlay: $(basename "$apk")"
                rm -f "$apk"
            fi
        done
    done
    log_ok "Display 120Hz patched"
}

patch_audio() {
    log_step "Patching Audio HAL"
    local PORT_DIR="$1"

    local audio_policy="${PORT_DIR}/vendor/etc/audio_policy_configuration.xml"
    if [[ -f "$audio_policy" ]]; then
        sed -i 's|audio_hw_info name="[^"]*"|audio_hw_info name="lahaina"|g' "$audio_policy"
        log_ok "  audio_policy: hw_info → lahaina"
    fi
}

patch_charging() {
    log_step "Patching Charging (Warp 65T / AirVOOC 50W)"
    local PORT_DIR="$1"

    mkdir -p "${PORT_DIR}/vendor/etc/init"
    cat > "${PORT_DIR}/vendor/etc/init/charger_lemonadep.rc" << 'RC'
# Warp Charge 65T init
on property:sys.boot_completed=1
    write /sys/class/power_supply/battery/op_disable_charge 0
    write /sys/kernel/oplus_chg/led_status 0

service oplus_chg_warp /vendor/bin/oplus_chg_warp_server
    class main
    user root
    group root
    oneshot
    disabled

on property:persist.sys.warp_charge_version=3
    start oplus_chg_warp
RC

    # Remove Xiaomi charge service if present
    sed -i '/mqsasd\|micharge\|xm_charge/d' \
        "${PORT_DIR}/vendor/etc/init/"*.rc 2>/dev/null || true
    log_ok "Charging patched"
}

patch_fingerprint() {
    log_step "Patching Fingerprint (Goodix FOD @2.3)"
    local PORT_DIR="$1"

    mkdir -p "${PORT_DIR}/vendor/etc/init"
    cat > "${PORT_DIR}/vendor/etc/init/android.hardware.biometrics.fingerprint@2.3-service.rc" << 'RC'
service vendor.fingerprint-default /vendor/bin/hw/android.hardware.biometrics.fingerprint@2.3-service
    class hal
    user system
    group system input uhid
    writepid /dev/cpuset/system-background/tasks

on property:sys.boot_completed=1
    # HBM for in-display fingerprint illumination
    write /sys/kernel/oplus_display/hbm_mode 0
RC
    log_ok "Fingerprint service RC written"
}

patch_wifi() {
    log_step "Patching Wi-Fi (QCA CLD3 / iWLAN)"
    local PORT_DIR="$1"
    local OOS_VENDOR="$2"

    # Copy OOS14 WCNSS ini if available and not same dir
    if [[ -d "$OOS_VENDOR" ]] && [[ "$(realpath "$OOS_VENDOR")" != "$(realpath "${PORT_DIR}/vendor" 2>/dev/null)" ]]; then
        for ini in WCNSS_qcom_cfg.ini wlan_mac.bin; do
            find "$OOS_VENDOR" -name "$ini" 2>/dev/null | head -1 | while read -r src; do
                local dst="${PORT_DIR}/vendor/etc/wifi/${ini}"
                mkdir -p "$(dirname "$dst")"
                cp -af "$src" "$dst" && log_ok "  Copied Wi-Fi config: $ini"
            done
        done
    fi
    log_ok "Wi-Fi patched"
}

patch_selinux() {
    log_step "Patching SELinux CIL policy"
    local PORT_DIR="$1"

    # Find the precompiled CIL file
    local cil
    cil=$(find "${PORT_DIR}/vendor" -name "*.cil" 2>/dev/null | head -1)
    if [[ -z "$cil" ]]; then
        log_warn "  No .cil file found in vendor — skipping SELinux CIL patch"
        return
    fi
    log_info "  Patching $cil"

    append_cil_rules "$cil" \
        "(allow untrusted_app goodix_fp_device (chr_file (read write open ioctl)))" \
        "(allow system_server oplus_charger_device (chr_file (read write open ioctl)))" \
        "(allow hal_thermal_default thermal_data_file (file (read open getattr)))" \
        "(allow qcrild rild_socket (sock_file (write)))" \
        "(allow system_server wlan_service (service_manager (find)))" \
        "(allow hal_camera_default vendor_data_file (dir (search)))" \
        "(allow hal_fingerprint_default goodix_fp_device (chr_file (read write open ioctl)))" \
        "(allow hal_health_default sysfs_battery_supply (file (read open getattr)))" \
        "(allow init oplus_chg_service (service_manager (add)))" \
        "(allow hal_bluetooth_default bt_firmware_file (file (read open execute)))" \
        "(allow system_app audio_prop (property_service (set)))" \
        "(allow untrusted_app proc_net (file (read open getattr)))" \
        "(allow shell vendor_file (dir (search read)))" \
        "(allow adbd shell_data_file (dir (search write create)))" \
        "(allow wpa wpa_socket (sock_file (create unlink)))" \
        "(allow hal_nfc_default nfc_prop (property_service (set)))" \
        "(allow qti_init_shell vendor_file (dir (search read execute)))"

    log_ok "SELinux CIL patched ($(wc -l < "$cil") rules)"
}

patch_init_rc() {
    log_step "Writing init.lemonadep.rc"
    local PORT_DIR="$1"

    mkdir -p "${PORT_DIR}/vendor/etc/init"
    cat > "${PORT_DIR}/vendor/etc/init/init.lemonadep.rc" << 'RC'
# init.lemonadep.rc — OnePlus 9 Pro (lahaina)
# Generated by HyperOS3-Port-lemonadep  |  Maintainer: Ozyern

on early-init
    # UFS power management (Samsung KLUFG8RHDC-B0E1)
    write /sys/bus/platform/devices/1d84000.ufshc/clkscale_enable 1
    write /sys/bus/platform/devices/1d84000.ufshc/clkgate_enable 1
    write /sys/bus/platform/devices/1d84000.ufshc/hibern8_on_idle_enable 1

on init
    # Alert slider keymapping
    write /sys/devices/platform/soc/884000.i2c/i2c-2/2-0044/alert_slider/enable 1

on boot
    # CPU boost governor
    write /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor schedutil
    write /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor schedutil
    write /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor schedutil

    # GPU default governor
    write /sys/class/kgsl/kgsl-3d0/devfreq/governor msm-adreno-tz

    # Haptics (DRV2624)
    write /sys/bus/i2c/devices/0-005a/haptics_enable 1

    # Fingerprint HBM perms
    chown system system /sys/kernel/oplus_display/hbm_mode
    chmod 0666         /sys/kernel/oplus_display/hbm_mode

on property:sys.boot_completed=1
    # CPU sched boost off after boot
    write /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq 0
    # Idle power savings
    write /proc/sys/kernel/sched_upmigrate 95
    write /proc/sys/kernel/sched_downmigrate 85
RC
    log_ok "init.lemonadep.rc written"
}

patch_vintf() {
    log_step "Patching VINTF manifest (VNDK 34 ↔ API 36 bridge)"
    local PORT_DIR="$1"

    local vendor_manifest="${PORT_DIR}/vendor/etc/vintf/manifest.xml"
    [[ ! -f "$vendor_manifest" ]] && { log_warn "  vendor manifest not found"; return; }

    python3 - "$vendor_manifest" << 'PY'
import sys, re

path = sys.argv[1]
txt  = open(path).read()

# Fix camera HAL version
txt = re.sub(r'android\.hardware\.camera\.provider@\d+\.\d+',
             'android.hardware.camera.provider@2.7', txt)

# Fix graphics composer
txt = re.sub(r'android\.hardware\.graphics\.composer@\d+\.\d+',
             'android.hardware.graphics.composer@2.4', txt)

# Remove HIDL blocks that Android 16 dropped
for dead in ['android.hardware.health@3.0',
             'android.hardware.drm@1.4',
             'android.hardware.memtrack@1.0']:
    txt = re.sub(
        r'<hal format="hidl">.*?' + re.escape(dead) + r'.*?</hal>\s*',
        '', txt, flags=re.DOTALL)

# Patch VNDK version in compatibility matrix reference
txt = re.sub(r'<vendor-ndk>\s*<version>\d+</version>',
             '<vendor-ndk>\n        <version>34</version>', txt)

open(path, 'w').write(txt)
print(f"  VINTF manifest patched: {path}")
PY
    log_ok "VINTF manifest patched"
}

patch_disable_miui_services() {
    log_step "Disabling MIUI/HyperOS services that break on OP9Pro"
    local PORT_DIR="$1"

    local dead_services=(
        "mimdump" "mqsasd" "mcd" "misight" "miui_log"
        "vendor.xiaomi" "mi_disp" "mi_thermald"
        "milogs" "miperf" "minetd"
    )

    find "${PORT_DIR}/vendor/etc/init" "${PORT_DIR}/system/system/etc/init" \
         -name "*.rc" 2>/dev/null | while read -r rc; do
        local modified=0
        for svc in "${dead_services[@]}"; do
            if grep -q "$svc" "$rc"; then
                sed -i "/service.*${svc}/,/^$/{ /^$/!{/oneshot/!s/$/\n    oneshot\n    disabled/} }" "$rc" 2>/dev/null || true
                modified=1
            fi
        done
        [[ $modified -eq 1 ]] && log_info "  Disabled MIUI services in: $(basename "$rc")"
    done
    log_ok "MIUI services disabled"
}

# ─── Run all patches ──────────────────────────────────────────────────────────
run_all_patches() {
    local PORT_DIR="$1"
    local OOS_VENDOR="${2:-}"

    patch_build_props    "$PORT_DIR"
    patch_fstab          "$PORT_DIR"
    patch_camera         "$PORT_DIR" "$OOS_VENDOR"
    patch_ril            "$PORT_DIR" "$OOS_VENDOR"
    patch_display_120hz  "$PORT_DIR"
    patch_audio          "$PORT_DIR"
    patch_charging       "$PORT_DIR"
    patch_fingerprint    "$PORT_DIR"
    patch_wifi           "$PORT_DIR" "$OOS_VENDOR"
    patch_vintf          "$PORT_DIR"
    patch_disable_miui_services "$PORT_DIR"
    patch_selinux        "$PORT_DIR"
    patch_init_rc        "$PORT_DIR"
}
