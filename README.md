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

### 1) Install dependencies (once)
```bash
sudo ./setup.sh
```

### 2) Run the porter (full OTAs only — delta/incremental zips are rejected)
```bash
sudo ./port.sh /path/to/HyperOS3_FULL_OTA.zip /path/to/OOS14_FULL_OTA.zip
# Outputs land in ./out
```

### 3) Flash (pick one)
- Linux/macOS flashable ZIP (includes boot repack):
  ```bash
  bash out/flashable/flash_auto.sh --slot a --wipe-data
  ```
- Linux fastboot images:
  ```bash
  SLOT=a bash out/fastboot_rom/flash_fastboot.sh
  ```
- Windows fastboot images:
  ```bat
  flash_fastboot.bat a
  ```

> If you prefer the combined helper: `sudo ./flash_and_fix.sh --ota out/HyperOS3_OOS14_lemonadep_by_Ozyern_*.zip --slot a --wipe-data` (still supported).

---

## ROM Format Support

Both scripts auto-detect the ZIP format — no flags needed (delta/incremental payloads are refused):

| Format | Detection | Tools used |
|--------|-----------|------------|
| Recovery OTA (payload.bin) | `payload.bin` in ZIP | `payload_dumper.py` or `payload-dumper-go` |
| Fastboot super.img | `super.img` in ZIP | `lpunpack` |
| Raw fastboot | `*.img` files in ZIP | direct unzip |
| Sparse fastboot | `*.new.dat.br` | brotli + sdat2img |

---

## What port.sh does

1. Extracts both ZIPs (auto-detects format; refuses delta/incremental payloads)
2. Extracts partition filesystems (erofs/ext4, WSL-safe)
3. Merges: HyperOS3 system/system_ext/product + OOS14 vendor/odm
4. Applies device patches (build.prop, camera, RIL, display, charging, fingerprint, Wi-Fi, audio)
5. Patches VINTF manifest for VNDK34 ↔ API36 bridge
6. Disables Xiaomi-only services that break OP9 Pro
7. Patches SELinux CIL rules
8. Repacks partitions using the source FS type when known (erofs for system*, ext4 for vendor/odm)
9. Generates flash scripts: `flash_auto.sh` (Linux/macOS), `flash_fastboot.sh` (Linux), `flash_fastboot.bat` (Windows)
10. Packages outputs: flashable ZIP + fastboot ROM ZIP
11. Super size guard (best-effort): warns/fails if repacked logical partitions exceed super group size when lpdump is available

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
| AVB relaxed flash | Uses `--disable-verity --disable-verification` on vbmeta*

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

## Boot expectations & troubleshooting

- Full OTAs only: delta/incremental payloads are refused (they lack full images).
- Fastboot layout and flash scripts are generated for Linux and Windows.
- Super size guard warns/fails if repacked logical partitions overrun the dynamic group size (requires lpdump).
- AVB is flashed with `--disable-verity --disable-verification`; if vbmeta/vbmeta_system are missing, fastboot scripts will warn.
- KernelSU: not injected yet (KSU=1 currently only warns).

If it doesn’t boot:
- Use full OTAs for both base and port, re-run with `VERBOSE=1` and inspect `out/port_*.log`.
- Share `fastboot getvar all`, and if it reaches Android logo, grab `adb logcat -b all` and `adb shell dmesg`.
- Check partition sizes vs super size (step 6b output) and ensure vendor/odm stayed ext4.

---

## Credits

- **Port Maintainer:** Ozyern (github.com/ozyern/ReVork_Ports)
- **Reference:** toraidl/HyperOS-Port-Python
- Tools: magiskboot (topjohnwu/Magisk), erofs-utils, Android OTA tools
