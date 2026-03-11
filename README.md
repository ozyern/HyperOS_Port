# HyperOS 3 → OnePlus 9 Pro Porting Toolkit

**Maintainer:** Ozyern  
**GitHub:** https://github.com/ozyern  
**Device:** OnePlus 9 Pro (lemonadep / lahaina)  
**Target:** HyperOS 3 (Android 16) based on OxygenOS 14 vendor

---

## Folder Structure

```
hyperos3_port_tools/
├── port.sh                      ← Main porting script
├── flash_and_fix.sh             ← Boot-fix + flash script
├── setup.sh                     ← One-time dependency installer
├── functions.sh                 ← Shared library (auto-sourced)
├── payload_dumper.py            ← Bundled payload.bin extractor
├── bin/                         ← Place extra binaries here (magiskboot, lpunpack)
├── devices/
│   └── lemonadep/
│       ├── config.json          ← Device config (DPI, SOC, API level, etc.)
│       └── patches.sh           ← All device-specific patches
└── out/                         ← All outputs land here (auto-created)
```

---

## Quick Start

### 1. Install dependencies (once)
```bash
sudo ./setup.sh
```

### 2. Port the ROM
```bash
sudo ./port.sh /path/to/HyperOS3.zip /path/to/OOS14_lemonadep.zip
# Output goes to ./out/
```

### 3. Flash (device in fastboot mode)
```bash
# Uses flash_and_fix.sh which applies boot fixes automatically
sudo ./flash_and_fix.sh --ota ./out/HyperOS3_OOS14_lemonadep_by_Ozyern_*.zip --slot a --wipe-data
```

---

## ROM Format Support

Both scripts auto-detect the ZIP format — no flags needed:

| Format | Detection | Tools used |
|--------|-----------|------------|
| Recovery OTA (payload.bin) | `payload.bin` in ZIP | `payload_dumper.py` or `payload-dumper-go` |
| Fastboot super.img | `super.img` in ZIP | `lpunpack` |
| Raw fastboot | `*.img` files in ZIP | direct unzip |
| Sparse fastboot | `*.new.dat.br` | brotli + sdat2img |

---

## What port.sh does

1. Extracts both ZIPs (auto-detects format)
2. Extracts partition filesystems (erofs/ext4, WSL-safe)
3. Merges: HyperOS3 system/system_ext/product + OOS14 vendor/odm
4. Applies all patches (build.prop, camera, RIL, display, charging, fingerprint, Wi-Fi, audio)
5. Patches VINTF manifest for VNDK34 ↔ API36 bridge
6. Disables broken MIUI services
7. Patches SELinux CIL rules
8. Repacks all partition images as erofs
9. Generates `flash_auto.sh` (standalone fastboot flasher)
10. Packages everything as a flashable ZIP

---

## What flash_and_fix.sh does

On top of flashing, it automatically applies:

| Fix | Purpose |
|-----|---------|
| SELinux permissive | Let device boot without policy crashes |
| SELinux CIL rules | ~20 rules covering all OP9Pro hardware domains |
| VINTF alignment | HAL versions patched for VNDK34↔API36 |
| VNDK bridge props | `ro.vndk.version=34`, `ro.vendor.api_level=34` |
| MIUI service disable | Prevent crash loops from Xiaomi-only services |
| 60Hz overlay removal | Prevent overlays from overriding LTPO 120Hz |

---

## Re-flashing after stable boot (switch to enforcing)

Once the ROM boots stably, re-flash without permissive:
```bash
sudo ./flash_and_fix.sh \
  --ota ./out/HyperOS3_OOS14_lemonadep_by_Ozyern_*.zip \
  --slot a \
  --no-permissive
```

---

## WSL Support

Fully supported. The scripts detect WSL automatically and use userspace-only tools:
- `fsck.erofs --extract` instead of `mount -t erofs`
- `debugfs rdump` instead of `mount -t ext4`
- No `modprobe`, no loop devices needed

---

## Credits

- **Port Maintainer:** Ozyern (github.com/ozyern/ReVork_Ports)
- **Reference:** toraidl/HyperOS-Port-Python
- Tools: magiskboot (topjohnwu/Magisk), erofs-utils, Android OTA tools
