# S36 Camera Detection Diagnosis Report

## Current Status (2026-06-24)

### ✓ What's Working
1. **ACPI Table Loaded**: scan_all_links configuration loaded successfully
2. **Drivers Loaded**: 
   - max96724 (deserializer)
   - max_serdes
   - isx031 (S36 sensor)
3. **MAX96724 Device Detected**: i2c-INTC1139:00 at 0x27 on I2C bus 0
4. **Internal I2C Bus Created**: i2c-7 (MAX96724 ATR bus for GMSL channels)
5. **IPU7 Bound**: `intel_ipu7_isys.isys intel_ipu7.isys.40: bind max96724 0-0027 nlanes is 4 port is 0`

### ❌ What's NOT Working
1. **No Cameras Detected**: No camera entities in media controller topology
2. **Empty I2C-7 Bus**: i2cdetect on i2c-7 shows no devices
3. **ACPI Errors**: Critical ACPI parsing errors preventing device enumeration

## Critical ACPI Errors

```
ACPI: \_SB_.PC00.DES0.CH00.SER0: unknown CSI-2 PHY type 3
ACPI: \_SB_.PC00.DES0.CH01.SER1: unknown CSI-2 PHY type 3
ACPI: \_SB_.PC00.DES0.CH02.SER2: unknown CSI-2 PHY type 3
ACPI: \_SB_.PC00.DES0.CH03.SER3: unknown CSI-2 PHY type 3

ACPI: \_SB_.PC00.DES0.CH00.SER0: MIPI port name too long for port 4294967294
ACPI: \_SB_.PC00.DES0: MIPI port name too long for port 4294967294
```

### Error Analysis

1. **Unknown PHY Type 3**
   - Expected: 0 (CPHY) or 1 (DPHY)
   - Actual: 3 (invalid value)
   - Source: All 4 serializer (SER0-3) CSI2Bus definitions
   - Impact: Prevents serializer device enumeration

2. **Invalid Port 0xFFFFFFFE**
   - Port value is uninitialized/undefined (-2 in unsigned)
   - Affects all levels: SER, CAM devices
   - Impact: MIPI endpoint creation fails

## Root Cause Hypothesis

The ACPI errors suggest a **mismatch between the ASL source code and the compiled AML**, or a **kernel ACPI parser incompatibility** with the S36 camera's special device hierarchy:

```
DES0 (MAX96724)
 └── CH00 (GMSL Link 0)
      └── SER0 (MAX9295D Serializer)
           ├── CH00 (Serializer Internal Channel 0)
           │    └── CAM0 (ISX031 Sensor 0)
           └── CH01 (Serializer Internal Channel 1)
                └── CAM1 (ISX031 Sensor 1)
```

This nested structure (Serializer with internal channels) may not be correctly parsed by the ipu_acpi driver.

## Verification Steps

### Check ASL Source
- `_ser_common_max9295d.asl` line 36: PhyType = 1 (DPHY) ✓ correct
- `_cam_common_s36.asl` line 31: PhyType = 1 (DPHY) ✓ correct

### Check Preprocessed .i File
- `acpi/ndk_unitree_max96724_mipi0_s36_scan_all_links.i` line ~275:
  ```
  CSI2Bus(
      DeviceInitiated,        // SlaveMode
      1,                      // PhyType (1 for DPHY) ✓
      2,                      // LocalPort (MAX9295D's PHY is PRT2) ✓
      "\\_SB.PC00.DES0",      // ResourceSource ✓
      0,                      // ResourceSourceIndex (Link 0) ✓
  ```

### Physical Hardware Status
- **Unknown**: Which GMSL port (A/B/C/D) has the S36 connected
- **Unknown**: Which GMSL port has the 3H connected
- **Test Needed**: Physical link detection independent of ACPI

## Recommended Actions

### Option 1: Debug ACPI Parsing
1. Enable kernel ACPI debug messages
2. Check if ipu_acpi driver supports nested SER->CH->CAM hierarchy
3. May need driver patch

### Option 2: Hardware Link Detection (Bypass ACPI)
1. Use i2c-dev to manually probe MAX96724 registers
2. Read GMSL link lock status registers (0x001A for links 0-3)
3. Identify which physical port has active link
4. Update ACPI configuration with correct link number

### Option 3: Simplify ACPI Hierarchy
1. Check if there's an alternative S36 ACPI template without nested CH devices
2. Some platforms may use flattened hierarchy: DES->SER->CAM directly

## Next Steps

**IMMEDIATE**: Check MAX96724 GMSL link lock status registers to determine physical connectivity

```bash
# Requires i2c-tools and manual register access
# Register 0x001A bits [3:0] = Link lock status for ports A/B/C/D
```

**IF LINK DETECTED**: Focus on fixing ACPI parsing issue
**IF NO LINK**: Check physical cable, power, or hardware issue

## Files to Review
- `drivers/media/platform/intel/ipu-acpi-common.c` - "unknown CSI-2 PHY type" error source
- `include/media/ipu-acpi.h` - PHY type definitions
- `acpi/_des_ch_common_s36.asl` - S36 hierarchy template
