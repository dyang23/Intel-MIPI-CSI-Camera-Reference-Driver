#!/bin/bash
# Direct hardware check for MAX96724 GMSL link status
# Bypasses ACPI to detect which physical ports have cameras connected

echo "=== MAX96724 GMSL Link Hardware Detection ==="
echo ""

I2C_BUS=0
DES_ADDR=0x27

# Check if device is accessible
if ! i2cget -y $I2C_BUS $DES_ADDR 0x00 b >/dev/null 2>&1; then
    echo "ERROR: Cannot access MAX96724 at bus $I2C_BUS address $DES_ADDR"
    echo "Device may be locked by driver. Trying to unbind..."

    # Try to unbind driver temporarily
    if [ -d "/sys/bus/i2c/drivers/max96724/i2c-INTC1139:00" ]; then
        echo "1" | sudo -S bash -c "echo 'i2c-INTC1139:00' > /sys/bus/i2c/drivers/max96724/unbind" 2>/dev/null
        sleep 1

        if ! i2cget -y $I2C_BUS $DES_ADDR 0x00 b >/dev/null 2>&1; then
            echo "ERROR: Still cannot access device"
            exit 1
        fi
        echo "✓ Device unbound successfully"
    fi
fi

echo "✓ MAX96724 accessible at I2C $I2C_BUS:0x$DES_ADDR"
echo ""

# Read device ID
DEV_ID=$(i2cget -y $I2C_BUS $DES_ADDR 0x0D b)
DEV_REV=$(i2cget -y $I2C_BUS $DES_ADDR 0x0E b)
echo "Device ID: $DEV_ID, Revision: $DEV_REV"
echo ""

# Read GMSL link lock status (register 0x001A)
# Bit 0: Link A lock
# Bit 1: Link B lock
# Bit 2: Link C lock
# Bit 3: Link D lock
LINK_STATUS_L=$(i2cget -y $I2C_BUS $DES_ADDR 0x1A b)
LINK_STATUS_H=$(i2cget -y $I2C_BUS $DES_ADDR 0x1B b)

echo "GMSL Link Lock Status (0x001A): $LINK_STATUS_L"
echo ""

# Parse link status
link_status=$((LINK_STATUS_L))

echo "Individual Link Status:"
for link in 0 1 2 3; do
    port_letter=$(echo "ABCD" | cut -c$((link+1)))
    if [ $(( (link_status >> link) & 1 )) -eq 1 ]; then
        echo "  ✓ Link $link (Port $port_letter): LOCKED - Camera detected!"
    else
        echo "  ✗ Link $link (Port $port_letter): No lock"
    fi
done
echo ""

# Read video lock status (register 0x0108)
VIDEO_LOCK=$(i2cget -y $I2C_BUS $DES_ADDR 0x0108 b)
echo "Video Lock Status (0x0108): $VIDEO_LOCK"
video_lock=$((VIDEO_LOCK))

echo "Video Pipe Status:"
for link in 0 1 2 3; do
    port_letter=$(echo "ABCD" | cut -c$((link+1)))
    if [ $(( (video_lock >> link) & 1 )) -eq 1 ]; then
        echo "  ✓ Pipe $link (Link $port_letter): Video locked"
    else
        echo "  ✗ Pipe $link (Link $port_letter): No video"
    fi
done
echo ""

# Count locked links
locked_count=0
for link in 0 1 2 3; do
    if [ $(( (link_status >> link) & 1 )) -eq 1 ]; then
        locked_count=$((locked_count + 1))
    fi
done

echo "========================================="
echo "Summary: $locked_count camera(s) detected"
echo "========================================="

# Rebind driver if we unbound it
if [ -d "/sys/bus/i2c/drivers/max96724" ] && [ ! -d "/sys/bus/i2c/drivers/max96724/i2c-INTC1139:00" ]; then
    echo ""
    echo "Rebinding MAX96724 driver..."
    echo "1" | sudo -S bash -c "echo 'i2c-INTC1139:00' > /sys/bus/i2c/drivers/max96724/bind" 2>/dev/null
fi
