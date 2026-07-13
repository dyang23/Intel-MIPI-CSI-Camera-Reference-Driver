# ACPI Configuration Directory

## Directory Structure

```
acpi/
├── build/                          # Compiled artifacts (*.aml, *.i) and backups
├── _*.asl                          # Common template files (included by others)
├── max96724_*.asl                  # Platform-specific configurations
├── NDK_unitree_*.asl               # Unitree board specific configurations
├── gen_all_link_configs.sh         # Helper script to generate configs for all links
└── README.md                       # This file
```

## File Types

- **`.asl`** - ACPI Source Language files (human-readable source)
- **`.aml`** - ACPI Machine Language files (compiled binary) → `build/`
- **`.i`** - Preprocessor output (intermediate files) → `build/`
- **`.dsl`** - Disassembled ACPI files → `build/`
- **`.bak`** - Backup files → `build/`

## Build Process

Use the `gen_ssdt.sh` script to compile ASL files:

```bash
cd /media/ndk/Dong_U1/dev/Intel-MIPI-CSI-Camera-Reference-Driver
./script/gen_ssdt.sh acpi/your_config.asl
```

This will:
1. Compile `your_config.asl` to AML
2. Move `.aml` and `.i` files to `acpi/build/`
3. Package the AML into `img_ssdt.img`
4. Copy to `/boot/img_ssdt.img`
5. Reboot required to load new ACPI table

## Unitree Board Configuration Files

### Main Configuration
- **`NDK_unitree_max96724_s36_3H.asl`** - Production config for S36 + 3H cameras
  - Configures S36 on Link 0 (Port A)
  - 3H placeholder (not yet enabled)

### Debug Configuration
- **`NDK_unitree_max96724_s36_scan_all_links.asl`** - Diagnostic config
  - Enables all 4 GMSL links simultaneously
  - Used to identify which physical port cameras are connected to
  - Helps determine the correct link assignment

## Common Template Files

These files are included by platform-specific configs:

- **`_ipu.asl`** - IPU device definition
- **`_des_common_max96724.asl`** - MAX96724 deserializer common config
- **`_des_ch_common_*.asl`** - Deserializer channel templates (per camera type)
- **`_ser_common_*.asl`** - Serializer common config (MAX9295, MAX9295D, etc.)
- **`_cam_common_*.asl`** - Camera sensor templates (ISX031, D457, S36)

## Board Hardware Configuration

### Unitree Board (NODKA)
- **MAX96724 Deserializer**: I2C bus 0, address 0x27
- **IPU MIPI Port**: Port 0 (mipi1 physical connector)
- **PHY Type**: C-PHY (DES_PHY_TYPE = 0)
- **Internal PHY**: TX_PHY0 = 4 ("cphy A")

### GMSL Link Mapping
- Port A = Link 0 → Channel CH00, Serializer SER0, I2C alias 0x44
- Port B = Link 1 → Channel CH01, Serializer SER1, I2C alias 0x45
- Port C = Link 2 → Channel CH02, Serializer SER2, I2C alias 0x46
- Port D = Link 3 → Channel CH03, Serializer SER3, I2C alias 0x47

## Troubleshooting

### Check which ACPI table is loaded
```bash
sudo acpidump -t SSDT -n IMG_IPU
strings /boot/img_ssdt.img | grep -E "DES0|IMG_IPU"
```

### View kernel ACPI messages
```bash
journalctl -k -b | grep -i "acpi.*des0\|acpi.*cam\|acpi.*ser"
```

### Check camera detection
```bash
journalctl -k -b | grep -i "max96724\|isx031\|s36"
media-ctl -d /dev/media0 -p
```

## Reference
- PHY type macros: `_phy_macros_REFERENCE.md`
- Build script: `../script/gen_ssdt.sh`
