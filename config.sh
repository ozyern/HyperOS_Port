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
# Supported source SoCs: SM8350 / SM8450 / SM8550  (all are arm64 + arm32)
# BLOCKED:  SM8650+ (SD 8 Gen 3 / SD 8 Elite) — pure 64-bit, no arm32 compat
#
# The vendor/odm/kernel always come from OxygenOS 14 (SM8350), so the source
# only needs to share the arm64+arm32 ABI contract — same SoC is NOT required.
#
# SoC reference table:
#   SM8350  Snapdragon 888      arm64+32  OnePlus 9 Pro, Mi 11, Poco F3
#   SM8450  Snapdragon 8 Gen 1  arm64+32  Xiaomi 12, OnePlus 10 Pro, Galaxy S22
#   SM8550  Snapdragon 8 Gen 2  arm64+32  Xiaomi 13, OnePlus 11, Galaxy S23
#   ── hard boundary ──────────────────────────────────────────────────────────
#   SM8650  Snapdragon 8 Gen 3  pure 64   Galaxy S24, Xiaomi 14  ← BLOCKED
#   SM8750  Snapdragon 8 Elite  pure 64   Galaxy S25, Xiaomi 15  ← BLOCKED

SOURCE_DEVICE="${SOURCE_DEVICE:-alioth}"   # override via env
SOURCE_ROM_ZIP="${SOURCE_ROM_ZIP:-}"       # path to HyperOS source zip/tgz

# Declare which SoCs are compatible (arm64+32) vs blocked (pure 64)
declare -A SOC_ARCH=(
    # ── Compatible (arm64 + arm32) ─────────────────────────────────────────
    ["SM8350"]="arm64_32"   # SD 888
    ["SM8450"]="arm64_32"   # SD 8 Gen 1
    ["SM8475"]="arm64_32"   # SD 8+ Gen 1
    ["SM8550"]="arm64_32"   # SD 8 Gen 2
    ["SM8475P"]="arm64_32"  # SD 8+ Gen 1 Pro
    # ── Blocked (pure 64-bit — NO arm32 compat) ────────────────────────────
    ["SM8650"]="pure64"     # SD 8 Gen 3
    ["SM8750"]="pure64"     # SD 8 Elite
    ["SM8750P"]="pure64"    # SD 8 Elite (Pro variant)
)

# Codename → SoC map for known HyperOS source devices
declare -A DEVICE_SOC=(
    # SM8350 sources
    ["alioth"]="SM8350"   ["haydn"]="SM8350"   ["venus"]="SM8350"
    ["lemonadep"]="SM8350" ["lisa"]="SM8350"
    # SM8450 sources
    ["cupid"]="SM8450"    ["taro"]="SM8450"    ["devonn"]="SM8450"
    ["yupik"]="SM8450"    ["op10pro"]="SM8450"
    # SM8550 sources
    ["fuxi"]="SM8550"     ["cetus"]="SM8550"   ["salami"]="SM8550"
    ["kalama"]="SM8550"   ["lunaa"]="SM8550"
    # SM8650 — BLOCKED
    ["shennong"]="SM8650" ["houji"]="SM8650"   ["pineapple"]="SM8650"
    # SM8750 — BLOCKED
    ["baklava"]="SM8750"  ["clover"]="SM8750"
)

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
