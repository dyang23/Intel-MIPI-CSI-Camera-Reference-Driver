#!/bin/bash
# Scan all GMSL links on MAX96724 to find which port has devices connected
# This script tries to access each link's I2C bus

echo "=== Scanning GMSL Links on MAX96724 ===="
echo "MAX96724 Device: i2c-INTC1139:00"
echo ""

# Check if i2c-7 exists (internal I2C bus created by MAX96724)
if [ -d "/sys/bus/i2c/devices/i2c-7" ]; then
    echo "✓ MAX96724 internal I2C bus (i2c-7) exists"
    echo "  Checking for devices on i2c-7..."
    sudo i2cdetect -y 7 2>&1 | grep -E "^[0-9]|^  "
    echo ""
else
    echo "✗ MAX96724 internal I2C bus not found"
    echo "  This means MAX96724 driver did not create ATR (Address Translator)"
    echo ""
fi

# Check for any channel devices
echo "Checking for GMSL channel devices:"
for ch in 0 1 2 3; do
    if [ -d "/sys/bus/i2c/devices/7-00$((0x44 + ch))" ]; then
        echo "  ✓ Link $ch (Port $( echo ABCD | cut -c$((ch+1)) )): Device found at 0x$((0x44 + ch))"
    else
        echo "  ✗ Link $ch (Port $( echo ABCD | cut -c$((ch+1)) )): No device"
    fi
done
echo ""

# Check kernel messages for link lock status
echo "Checking kernel messages for GMSL link status:"
journalctl -k -b | grep -i "max96724\|link.*lock\|link.*detect\|gmsl" | tail -20
