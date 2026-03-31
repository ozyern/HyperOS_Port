#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — config.sh
# Device & ROM configuration for OnePlus 9 Pro (lemonadep / SM8350)
# =============================================================================

# ── Target device ─────────────────────────────────────────────────────────────
TARGET_DEVICE="lemonadep"
TARGET_CODENAME="OnePlus9Pro"
TARGET_SOC="SM8350"
TARGET_ARCH="arm64"
TARGET_API=34                         # Android 14 base

# ── Source HyperOS ROM ────────────────────────────────────────────────────────
# Must be an SM8350 device for vendor HAL compatibility
# Supported sources: Mi 11 (venus), Poco F3 (alioth), Redmi K40 Pro (haydn)
SOURCE_DEVICE="${SOURCE_DEVICE:-alioth}"   # override via env
SOURCE_ROM_ZIP="${SOURCE_ROM_ZIP:-}"       # path to HyperOS source zip/tgz

# ── Base OxygenOS ROM (vendor blobs) ──────────────────────────────────────────
# OxygenOS 14.x for OnePlus 9 Pro — provides vendor/odm/kernel
BASE_ROM_ZIP="${BASE_ROM_ZIP:-}"           # path to OxygenOS 14 zip

# ── Partition layout ──────────────────────────────────────────────────────────
# Partitions pulled from HyperOS source
HYPEROS_PARTITIONS=(
    system
    system_ext
    product
    odm_dlkm
)

# Partitions pulled from OxygenOS base (hardware layer)
BASE_PARTITIONS=(
    vendor
    odm
)

# Boot images pulled from OxygenOS base
BASE_BOOT_IMAGES=(
    boot
    vendor_boot
    dtbo
)

# ── Super image geometry (lemonadep) ──────────────────────────────────────────
SUPER_SIZE=9126805504
METADATA_SIZE=65536
SUPER_BLOCK_SIZE=4096
DYNAMIC_PARTITION_LIST="system system_ext product odm_dlkm vendor odm"

# ── Build identity override ───────────────────────────────────────────────────
# Shown in Settings > About phone
BRAND_OVERRIDE="OnePlus"
MODEL_OVERRIDE="OnePlus 9 Pro"
DEVICE_OVERRIDE="lemonadep"
MANUFACTURER_OVERRIDE="OnePlus"

# ── Prop patches ──────────────────────────────────────────────────────────────
# Props to forcibly add/override in system/build.prop after merge
declare -A PROP_OVERRIDES=(
    ["ro.product.brand"]="OnePlus"
    ["ro.product.device"]="lemonadep"
    ["ro.product.manufacturer"]="OnePlus"
    ["ro.product.model"]="LE2123"
    ["ro.product.name"]="lemonadep"
    ["ro.product.system.brand"]="OnePlus"
    ["ro.product.system.device"]="lemonadep"
    ["ro.product.system.manufacturer"]="OnePlus"
    ["ro.product.system.model"]="LE2123"
    ["ro.product.system.name"]="lemonadep"
    ["ro.build.product"]="lemonadep"
    ["ro.vendor.oplus.regionmark"]="IN"
)

# Props to strip from HyperOS system/build.prop (MIUI/HyperOS-specific junk)
PROPS_TO_STRIP=(
    "ro.miui."
    "ro.xiaomi."
    "persist.miui."
    "ro.mi."
    "persist.sys.miui"
    "ro.build.miui"
    "ro.hyperos."
)

# ── Tools ─────────────────────────────────────────────────────────────────────
TOOLS_REQUIRED=(
    payload_dumper
    lpunpack
    lpmake
    img2simg
    simg2img
    resize2fs
    e2fsck
    7z
    python3
    xmlstarlet
    zip
)
