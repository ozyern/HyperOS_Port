# HyperOS_Port

> Port HyperOS onto OnePlus 9 Pro (lemonadep / SM8350) using OxygenOS 14 as the hardware base.

Inspired by [toraidl/hyperos_port](https://github.com/toraidl/hyperos_port).

---

## How it works

The porting strategy is simple: take HyperOS's **system layers** from a compatible source device, keep the **hardware layer** (vendor, odm, kernel) from OxygenOS 14 untouched. Since both use SM8350-class hardware, the vendor HAL ABI contract is maintained — this is what makes the port actually boot and function.

| Layer | Source | Reason |
|---|---|---|
| `system` / `system_ext` / `product` | HyperOS ROM | UI, apps, framework |
| `system_dlkm` / `odm_dlkm` | HyperOS ROM | Kernel module userspace |
| `mi_ext` | HyperOS ROM (merged into system_ext) | Xiaomi extras |
| `vendor` / `vendor_dlkm` / `odm` | OxygenOS 14 | Hardware HALs — **never replace** |
| `boot` / `vendor_boot` / `dtbo` | OxygenOS 14 | Kernel must match hardware |

---

## Architecture compatibility

| SoC | Chip | Architecture | Compatible? |
|---|---|---|---|
| SM8350 | Snapdragon 888 | arm64 + arm32 | ✅ |
| SM8450 | Snapdragon 8 Gen 1 | arm64 + arm32 | ✅ |
| SM8475 | Snapdragon 8+ Gen 1 | arm64 + arm32 | ✅ |
| SM8550 | Snapdragon 8 Gen 2 | arm64 + arm32 | ✅ |
| **SM8650** | **Snapdragon 8 Gen 3** | **pure 64-bit** | **🚫 BLOCKED** |
| **SM8750** | **Snapdragon 8 Elite** | **pure 64-bit** | **🚫 BLOCKED** |

SD 8 Gen 3 and newer dropped the arm32 compatibility layer. Porting those ROMs to SM8350 would break all 32-bit apps and several system services. The script hard-blocks these sources automatically.

---

## Tested source devices

| Device | Codename | SoC | Notes |
|---|---|---|---|
| Poco F3 | `alioth` | SM8350 | ✅ Recommended |
| Redmi K40 Pro | `haydn` | SM8350 | ✅ |
| Mi 11 Lite 5G NE | `lisa` | SM8350 | ✅ |
| Xiaomi 12 | `cupid` | SM8450 | ✅ |
| Xiaomi 13 | `fuxi` | SM8550 | ✅ |
| Mi 11 | `venus` | SM8350 | ⚠️ Different GPU binaries, needs testing |

---

## Requirements

### Linux (Ubuntu/Debian)
```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/ozyern/HyperOS_Port.git
cd HyperOS_Port
sudo ./setup.sh
```

### macOS
```bash
# Install Homebrew first: https://brew.sh
git clone https://github.com/ozyern/HyperOS_Port.git
cd HyperOS_Port
./setup.sh
```

### Termux (Android, untested)
```bash
pkg update && pkg install git tsu -y
git clone https://github.com/ozyern/HyperOS_Port.git
cd HyperOS_Port
./setup.sh
tsu  # enter root
```

---

## Usage

```bash
sudo ./port.sh <baserom> <portrom> [anykernel.zip]
```

Both `baserom` and `portrom` accept a **local file path or a direct download URL**.

```bash
# Local files
sudo ./port.sh \
    ~/roms/OnePlus9Pro_OxygenOS14.zip \
    ~/roms/HyperOS_alioth_14.0.zip

# Direct URLs
sudo ./port.sh \
    https://oxygenos.oneplus.net/.../lemonadep_OxygenOS14.zip \
    https://bigota.d.miui.com/.../alioth_HyperOS.zip

# With custom kernel (AnyKernel3 zip)
sudo ./port.sh <baserom> <portrom> ~/kernels/mykernel-ksu.zip
```

Output: `output/HyperOS_Port_lemonadep_<version>.zip`

---

## Flashing

**Fastboot (recommended):**
```bash
adb reboot fastboot
fastboot flash super        output/super.img
fastboot flash boot         output/boot.img
fastboot flash vendor_boot  output/vendor_boot.img
fastboot flash dtbo         output/dtbo.img
fastboot -w
fastboot reboot
```

**TWRP / OrangeFox:**  
Sideload `HyperOS_Port_lemonadep_*.zip`. Wipe data first.

---

## Device overlay system

Place device-specific files in `devices/lemonadep/overlay/` — they get copied on top of the merged system after all patches. Useful for swapping APKs, adding config files, or patching permissions without touching the main scripts.

```
devices/
└── lemonadep/
    └── overlay/
        └── product/
            └── priv-app/
                └── MiuiCamera/
                    └── MiuiCamera.apk   ← custom camera build
```

---

## Known issues

| Issue | Status |
|---|---|
| Camera (Leica ISP) | ❌ Not functional — use GCam or AOSP cam |
| Mi Account / MIUI Cloud | ❌ Stripped (incompatible) |
| Game Turbo | ❌ Stripped (Xiaomi HAL dependency) |
| Face unlock | ⚠️ Depends on source device support |
| NFC | ✅ Works (OxygenOS vendor) |
| Fingerprint | ✅ Works |
| RIL / calls / data | ✅ Works (OxygenOS vendor) |
| First boot time | ⚠️ 3–5 minutes — normal |

---

## File structure

```
HyperOS_Port/
├── port.sh          # Main orchestrator
├── functions.sh     # Core utility library
├── config.sh        # Device & ROM configuration
├── patches.sh       # Device-specific patches
├── setup.sh         # Dependency installer
├── devices/
│   └── lemonadep/
│       └── overlay/ # Device-specific file overrides
└── README.md
```

---

## Credits

- [toraidl/hyperos_port](https://github.com/toraidl/hyperos_port) — original HyperOS porting approach

---

*By [@ozyern](https://github.com/ozyern)*
