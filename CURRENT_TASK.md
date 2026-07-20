# Current Task: S36 Camera Detection on Unitree Board

**Date**: 2026-06-24  
**Branch**: s36_from_ChangChing  
**Status**: 🔴 BLOCKED - ACPI parsing errors

---

## Objective
Enable S36 and 3H camera detection on Unitree (NODKA) board via MAX96724 GMSL deserializer

---

## Current Status

### ✅ Completed
1. ACPI table compiled and loaded (scan_all_links configuration)
2. Drivers built and installed:
   - max96724 (deserializer)
   - isx031 (S36 sensor)
   - max_serdes (common)
3. MAX96724 device detected on I2C bus 0 at address 0x27
4. IPU7 successfully bound to MAX96724
5. ACPI directory reorganized (build artifacts → acpi/build/)
6. Project documentation created (PROJECT_GUIDE.md)

### 🔴 Blocked
**Issue**: ACPI parsing errors preventing device enumeration

**Errors**:
```
ACPI: \_SB_.PC00.DES0.CH00.SER0: unknown CSI-2 PHY type 3
ACPI: \_SB_.PC00.DES0.CH00.SER0: MIPI port name too long for port 4294967294
```

**Impact**:
- No GMSL serializers detected on i2c-7 bus
- No camera entities in media controller
- Cameras not enumerated

---

## Next Actions

### IMMEDIATE: Verify Driver Build
```bash
# 1. Rebuild drivers from s36 branch
./script/rebuild_camera_driver.sh

# 2. Reboot
sudo reboot

# 3. Verify loaded modules
lsmod | grep -E "max96724|isx031|ipu_acpi"
modinfo ipu_acpi_common | grep srcversion
```

### THEN: Test DES_INTERNAL_PHY Values
Need to try different PHY configurations:

**Current** (not working):
```c
#define DES_INTERNAL_PHY      4           /* TX_PHY0 */
```

**Try in sequence**:
- DES_INTERNAL_PHY = 5 (TX_PHY1)
- DES_INTERNAL_PHY = 6 (TX_PHY2)  
- DES_INTERNAL_PHY = 7 (TX_PHY3)

**Test procedure for each**:
```bash
# 1. Edit config
vim acpi/NDK_unitree_max96724_s36_3H.asl
# Change DES_INTERNAL_PHY value

# 2. Compile
./script/gen_ssdt.sh acpi/NDK_unitree_max96724_s36_3H.asl

# 3. Reboot
sudo reboot

# 4. Check
journalctl -k -b | grep -E "max96724|link|ser"
./scan_gmsl_links.sh
```

---

## Known Good Configuration (Other Boards)
The following settings are confirmed working on 2 other boards:
- DES_PHY_TYPE = 0 (CPHY) ✓
- DES_I2C_ADDR = 0x0027 ✓
- DES_TO_MIPI_PORT = 0 ✓
- DES_I2C_BUS = I2C0 ✓
- S36 configuration files ✓
- MAX96724 driver ✓

**Unknown**:
- DES_INTERNAL_PHY value (need to try 4/5/6/7)

---

## Investigation Notes

### ACPI Parse Error Analysis
The "unknown CSI-2 PHY type 3" error suggests:
1. Incorrect PHY type value in compiled AML (expected 0 or 1, got 3)
2. Possible driver version mismatch
3. S36-specific hierarchy may need driver support

### Hardware Verification Needed
```bash
# Check if MAX96724 is powered and responsive
./check_gmsl_hardware.sh

# Expected: Device ID and link status registers readable
# If all zeros: Device not powered or wrong I2C address
```

### Driver Source Check
```bash
# Verify current driver is from s36 branch
ls -lh /lib/modules/$(uname -r)/updates/dkms/ipu*.ko.zst
# Should be recent timestamp

# Check source
git log -1 --oneline ipu7-drivers/drivers/media/platform/intel/
```

---

## Test Matrix

| Test | DES_INTERNAL_PHY | DES_PHY_TYPE | Result | Notes |
|------|------------------|--------------|--------|-------|
| 1    | 4                | 0 (CPHY)     | ❌     | ACPI parse error |
| 2    | 5                | 0 (CPHY)     | ⏳     | Pending |
| 3    | 6                | 0 (CPHY)     | ⏳     | Pending |
| 4    | 7                | 0 (CPHY)     | ⏳     | Pending |

---

## Decision Points

### If rebuild fixes ACPI errors:
→ Problem was driver version mismatch  
→ Proceed with PHY testing

### If ACPI errors persist after rebuild:
→ Possible driver bug with S36 hierarchy  
→ May need driver patch or alternative ACPI structure

### If hardware check shows no response:
→ Check physical connections  
→ Verify MAX96724 power and I2C  
→ May need board bring-up

---

## Files Modified Today
- `script/gen_ssdt.sh` - Auto-move build artifacts to acpi/build/
- `acpi/build/` - Created for compiled files
- `PROJECT_GUIDE.md` - Created
- `CURRENT_TASK.md` - Created (this file)
- `diagnosis_report.md` - Created

---

## References
- Diagnosis: [diagnosis_report.md](diagnosis_report.md)
- Project Guide: [PROJECT_GUIDE.md](PROJECT_GUIDE.md)
- ACPI Guide: [acpi/README.md](acpi/README.md)
- S36 Config: [acpi/NDK_unitree_max96724_s36_3H.asl](acpi/NDK_unitree_max96724_s36_3H.asl)

---

**Last Updated**: 2026-06-24 06:30
