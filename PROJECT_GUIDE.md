# Intel MIPI CSI Camera Driver - Project Guide

## Quick Reference

### Current Working Directory
```
/media/ndk/Dong_U1/dev/Intel-MIPI-CSI-Camera-Reference-Driver
```

### Active Branch
- **s36_from_ChangChing** - S36 camera support branch

### Current Task
**Debugging S36 camera detection on Unitree (NODKA) board**
- Status: ACPI errors preventing camera enumeration
- Location: See [CURRENT_TASK.md](CURRENT_TASK.md)

---

## Directory Structure

```
├── script/                         # Build and utility scripts
│   ├── rebuild_camera_driver.sh    # ⭐ REBUILD DRIVERS (use this!)
│   ├── gen_ssdt.sh                 # Compile ACPI ASL → img_ssdt.img
│   └── acpi/mc-setup.sh            # Media controller setup
│
├── acpi/                           # ACPI configuration files
│   ├── build/                      # Compiled artifacts (*.aml, *.i)
│   ├── NDK_unitree_*.asl           # Unitree board configs
│   ├── max96724_*.asl              # Platform configs
│   ├── _*.asl                      # Common templates
│   └── README.md                   # ACPI directory guide
│
├── drivers/                        # Local driver sources
├── ipu7-drivers/                   # IPU7 driver submodule
├── ipu6-drivers/                   # IPU6 driver submodule
│
├── diagnosis_report.md             # Current issue diagnosis
├── PROJECT_GUIDE.md                # This file
└── CURRENT_TASK.md                 # Current task status
```

---

## Essential Scripts and Tools

### 1. **Build & Install Drivers**
```bash
./script/rebuild_camera_driver.sh
```
**Purpose**: Clean, compile, and install all camera drivers
**When to use**: After any source code changes or branch switch
**Output**: Drivers installed to `/lib/modules/$(uname -r)/updates/dkms/`

### 2. **Compile ACPI Configuration**
```bash
./script/gen_ssdt.sh acpi/<config>.asl
```
**Purpose**: Compile ASL → AML → img_ssdt.img → /boot/
**Output**: `/boot/img_ssdt.img` (requires reboot to take effect)
**Artifacts**: Saved to `acpi/build/`

### 3. **Check GMSL Hardware Status**
```bash
./check_gmsl_hardware.sh
```
**Purpose**: Direct hardware check of MAX96724 GMSL link status
**When to use**: Verify physical camera connections

### 4. **Scan GMSL Links**
```bash
./scan_gmsl_links.sh
```
**Purpose**: Check which GMSL ports have devices
**When to use**: Identify which physical port cameras are connected to

---

## Common Workflows

### Workflow 1: Modify and Test ACPI Configuration
```bash
# 1. Edit ASL file
vim acpi/NDK_unitree_max96724_s36_3H.asl

# 2. Compile and install
./script/gen_ssdt.sh acpi/NDK_unitree_max96724_s36_3H.asl

# 3. Reboot
sudo reboot

# 4. Check results
journalctl -k -b | grep -i "max96724\|s36\|cam"
media-ctl -d /dev/media0 -p
```

### Workflow 2: Rebuild Drivers After Code Change
```bash
# 1. Make code changes
vim ipu7-drivers/drivers/media/platform/intel/ipu-acpi-common.c

# 2. Rebuild and install
./script/rebuild_camera_driver.sh

# 3. Reboot (or reload modules)
sudo reboot
```

### Workflow 3: Debug Camera Detection
```bash
# 1. Check current branch
git branch

# 2. Check loaded drivers
lsmod | grep -E "max96|isx|ipu"

# 3. Check ACPI errors
journalctl -k -b | grep -i acpi | grep -i "des0\|ser\|cam"

# 4. Check hardware
./check_gmsl_hardware.sh

# 5. Check media devices
media-ctl -d /dev/media0 -p
v4l2-ctl --list-devices
```

---

## Key Configuration Files

### Unitree Board ACPI Configs
1. **NDK_unitree_max96724_s36_3H.asl**
   - Production config for S36 + 3H cameras
   - S36 on Link 0 (Port A)
   - Board-specific settings (I2C, MIPI port, PHY type)

2. **ndk_unitree_max96724_mipi0_s36_scan_all_links.asl**
   - Debug config enabling all 4 GMSL links
   - Use to identify which ports have cameras

### Critical Board-Level Settings
Located in ASL files under `// ---- DES-level configuration`:
```c
#define DES_PHY_TYPE          0           // 0=CPHY, 1=DPHY
#define DES_I2C_ADDR          0x0027      // MAX96724 address
#define DES_INTERNAL_PHY      4           // 4-7: TX_PHY0-3
#define DES_TO_MIPI_PORT      0           // IPU MIPI port 0-3
#define DES_I2C_BUS           "\\_SB.PC00.I2C0"
```

---

## Current Known Issues

### Issue 1: ACPI Parsing Errors (ACTIVE)
**Symptoms**:
```
ACPI: \_SB_.PC00.DES0.CH00.SER0: unknown CSI-2 PHY type 3
ACPI: MIPI port name too long for port 4294967294
```

**Impact**: Prevents camera device enumeration

**Status**: Under investigation
- Drivers loaded: ✓
- MAX96724 detected: ✓
- GMSL links: ✗ No devices on i2c-7
- Cameras: ✗ Not enumerated

**Next Steps**: 
1. Verify drivers are from s36 branch
2. Try different DES_INTERNAL_PHY values (4, 5, 6, 7)
3. Check if PHY type mismatch

See [diagnosis_report.md](diagnosis_report.md) for details

---

## Important Notes

### ACPI Workflow
- ASL source files (`.asl`) → human-readable
- Compiled to AML (`.aml`) → machine code
- Packaged into `img_ssdt.img` → initramfs format
- Loaded at boot from `/boot/img_ssdt.img`
- **Changes require reboot to take effect**

### Driver Development
- Use DKMS for automatic rebuild on kernel updates
- Test changes with `./script/rebuild_camera_driver.sh`
- Check `dkms status` to verify installation

### Hardware Constraints
- MAX96724: 4 GMSL input ports (A/B/C/D = Link 0/1/2/3)
- Physical port label may differ from software link number
- S36 module: 1 serializer → 2 ISX031 sensors
- 3H module: 1 serializer → 1 ISX031 sensor

---

## Troubleshooting Quick Reference

| Symptom | Check Command | Possible Cause |
|---------|--------------|----------------|
| Driver not loaded | `lsmod \| grep max96724` | Not compiled/installed |
| ACPI errors | `journalctl -k \| grep ACPI.*DES0` | Wrong config or parse error |
| No cameras | `media-ctl -d /dev/media0 -p` | GMSL link not established |
| I2C errors | `journalctl -k \| grep i2c` | Wrong address or bus |
| Link timeout | `./check_gmsl_hardware.sh` | Cable not connected |

---

## Documentation Files

- **PROJECT_GUIDE.md** (this file) - Project overview and quick reference
- **CURRENT_TASK.md** - Current debugging task status
- **diagnosis_report.md** - Detailed issue analysis
- **acpi/README.md** - ACPI configuration guide
- **acpi/_phy_macros_REFERENCE.md** - PHY type reference

---

## Git Workflow

### Branches
- **main** - Stable release
- **s36_from_ChangChing** - S36 camera support (CURRENT)

### Check Status
```bash
git status
git branch
git log --oneline -5
```

---

## Contact & Resources

- S36 configuration verified on 2 other boards
- Common templates in `acpi/_*.asl` are proven to work
- Board-specific changes limited to DES-level configuration

**Last Updated**: 2026-06-24
