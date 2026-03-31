# HyperOS_Port

> Port HyperOS (Xiaomi SM8350 source) onto OnePlus 9 Pro — using OxygenOS 14 as the hardware/vendor base.

Built with the same modular architecture as [coloros_port / Rapchick Engine](https://github.com/ozyern/coloros_port).

---

## How it works

| Layer | Source |
|---|---|
| `system` / `system_ext` / `product` / `odm_dlkm` | HyperOS ROM (SM8350 device) |
| `vendor` / `odm` | OxygenOS 14 for lemonadep |
| `boot` / `vendor_boot` / `dtbo` | OxygenOS 14 for lemonadep |

The OxygenOS kernel and vendor blobs stay untouched — this is what makes the port actually boot. HyperOS provides the UI, apps, and framework layers on top.

---

## Supported source devices

Must be SM8350 (same SoC as OnePlus 9 Pro):

| Device | Codename | Notes |
|---|---|---|
| Poco F3 | `alioth` | ✅ Recommended |
| Redmi K40 Pro | `haydn` | ✅ Good |
| Mi 11 Lite 5G NE | `lisa` | ✅ Works |
| Mi 11 | `venus` | ⚠️ Different GPU binaries, needs extra testing |

## Requirements

```bash
# Ubuntu/Debian
sudo apt install p7zip-full python3 e2fsprogs xmlstarlet zip
pip3 install payload-dumper-go   # or build from source

# Android tools (from AOSP)
# lpunpack, lpmake, img2simg, simg2img — must be in PATH
```

## Usage

```bash
export SOURCE_ROM_ZIP="/path/to/HyperOS_alioth_14.0_OTA.zip"
export BASE_ROM_ZIP="/path/to/OnePlus9Pro_OxygenOS14.zip"

sudo ./port.sh
```

Output: `output/HyperOS_Port_lemonadep_YYYYMMDD.zip`

## Flashing

**Fastboot (recommended):**
```bash
adb reboot fastboot
fastboot flash super     output/super.img
fastboot flash boot      output/boot.img
fastboot flash vendor_boot output/vendor_boot.img
fastboot flash dtbo      output/dtbo.img
fastboot -w
fastboot reboot
```

**Or:** Sideload the zip via TWRP/OrangeFox (wipe data first).

---

## Known limitations

- **Camera** — HyperOS camera (Leica tuning) won't work; GCam or AOSP camera recommended
- **Mi Account / MIUI Cloud** — stripped, non-functional
- **Game Turbo** — stripped (Xiaomi HAL dependency)
- **First boot** — takes 3–5 minutes, don't panic

## File structure

```
HyperOS_Port/
├── port.sh        # Main orchestrator
├── functions.sh   # Core utility library
├── config.sh      # Device & ROM configuration
├── patches.sh     # Device-specific patches
└── README.md
```

---

*By [@ozyern](https://github.com/ozyern) — part of the ReVork/Rapchick ecosystem*
