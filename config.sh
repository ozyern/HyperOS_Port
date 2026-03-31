#!/usr/bin/env bash
# =============================================================================
# HyperOS_Port — config.sh
# Device & ROM configuration for OnePlus 9 Pro (lemonadep / SM8350)
# =============================================================================

# ── Target device ─────────────────────────────────────────────────────────────
TARGET_DEVICE="lemonadep"
TARGET_SOC="SM8350"
TARGET_ARCH="arm64"
TARGET_API=34

# ── Super image geometry (lemonadep) ──────────────────────────────────────────
SUPER_SIZE=9126805504
METADATA_SIZE=65536
SUPER_BLOCK_SIZE=4096

# ── Partitions ────────────────────────────────────────────────────────────────
# Pulled from HyperOS source ROM. Script skips any that don't exist in source.
PORTROM_PARTITIONS=(
    system
    system_ext
    system_dlkm
    product
    product_dlkm
    mi_ext
    odm_dlkm
)

# Always from OxygenOS base (hardware layer — never replace these)
BASEROM_PARTITIONS=(
    vendor
    vendor_dlkm
    odm
)

# Boot images always from OxygenOS base
BASE_BOOT_IMAGES=(
    boot
    vendor_boot
    dtbo
)

# ── Build identity ─────────────────────────────────────────────────────────────
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

# Prop prefixes to strip from HyperOS build.prop files
PROPS_TO_STRIP=(
    "ro.miui."
    "ro.xiaomi."
    "persist.miui."
    "ro.mi."
    "persist.sys.miui"
    "ro.build.miui"
    "ro.hyperos."
)

# ── Architecture compatibility table ──────────────────────────────────────────
# SD 888 → SD 8 Gen 2 = arm64+32 (compatible with lemonadep)
# SD 8 Gen 3+ = pure 64-bit → BLOCKED
declare -A SOC_ARCH=(
    ["SM8350"]="arm64_32"   # Snapdragon 888
    ["SM8450"]="arm64_32"   # Snapdragon 8 Gen 1
    ["SM8475"]="arm64_32"   # Snapdragon 8+ Gen 1
    ["SM8550"]="arm64_32"   # Snapdragon 8 Gen 2
    ["SM8650"]="pure64"     # Snapdragon 8 Gen 3   <- BLOCKED
    ["SM8750"]="pure64"     # Snapdragon 8 Elite   <- BLOCKED
    ["SM8750P"]="pure64"    # Snapdragon 8 Elite Pro <- BLOCKED
)

# Codename -> SoC lookup for known source devices
declare -A DEVICE_SOC=(
    # SM8350 — Snapdragon 888
    ["alioth"]="SM8350"    ["haydn"]="SM8350"     ["venus"]="SM8350"
    ["lemonadep"]="SM8350" ["lisa"]="SM8350"      ["umi"]="SM8350"
    ["cmi"]="SM8350"       ["cas"]="SM8350"       ["thyme"]="SM8350"
    # SM8450 — Snapdragon 8 Gen 1
    ["cupid"]="SM8450"     ["taro"]="SM8450"      ["devonn"]="SM8450"
    ["yupik"]="SM8450"     ["op10pro"]="SM8450"   ["ferrari"]="SM8450"
    # SM8550 — Snapdragon 8 Gen 2
    ["fuxi"]="SM8550"      ["cetus"]="SM8550"     ["salami"]="SM8550"
    ["kalama"]="SM8550"    ["lunaa"]="SM8550"     ["marble"]="SM8550"
    # SM8650 — BLOCKED
    ["shennong"]="SM8650"  ["houji"]="SM8650"     ["pineapple"]="SM8650"
    # SM8750 — BLOCKED
    ["baklava"]="SM8750"   ["clover"]="SM8750"
)

# ── Required tools ────────────────────────────────────────────────────────────
TOOLS_REQUIRED=(
    payload-dumper-go
    lpunpack
    lpmake
    img2simg
    simg2img
    resize2fs
    e2fsck
    fsck.erofs
    mkfs.ext4
    python3
    7z
    xmlstarlet
    zip
    curl
)
