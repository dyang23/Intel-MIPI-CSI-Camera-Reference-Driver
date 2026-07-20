#!/bin/bash
# Rebuild and install camera drivers using DKMS
# Usage: ./script/rebuild_camera_driver.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=== Rebuilding Camera Drivers with DKMS ==="
echo "Project root: $PROJECT_ROOT"
echo "Current branch: $(git branch --show-current)"
echo ""

# Remove existing DKMS module
echo "Step 1: Removing existing DKMS module..."
sudo dkms remove ipu-camera-sensor/0.1 --all 2>/dev/null || true
sudo rm -rf /usr/src/ipu-camera-sensor-0.1/ 2>/dev/null || true
echo "✓ Old module removed"
echo ""

# Add current source to DKMS
echo "Step 2: Adding source to DKMS..."
sudo dkms add .
echo "✓ Source added"
echo ""

# Build the module
echo "Step 3: Building modules (this may take a few minutes)..."
sudo dkms build -m ipu-camera-sensor -v 0.1
echo "✓ Build complete"
echo ""

# Install the module
echo "Step 4: Installing modules..."
sudo dkms install -m ipu-camera-sensor -v 0.1 --force
echo "✓ Installation complete"
echo ""

# Verify installation
echo "=== Verification ==="
echo "Installed modules:"
ls -lh /lib/modules/$(uname -r)/updates/dkms/ | grep -E "ipu|max96|isx" | head -10
echo ""

echo "DKMS status:"
dkms status | grep ipu-camera-sensor
echo ""

echo "=== Build Complete ==="
echo "✓ All camera drivers rebuilt and installed"
echo ""
echo "Next steps:"
echo "1. Reboot system: sudo reboot"
echo "2. Or reload modules:"
echo "   sudo modprobe -r max96724 isx031 ipu_acpi"
echo "   sudo modprobe max96724 isx031 ipu_acpi"
echo ""
