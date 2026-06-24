#!/bin/bash
set -ex
shopt -s nullglob

DIR="kernel/firmware/acpi"
BUILD_DIR="acpi/build"

if [ -z "$1" ]; then
    echo "Usage: $0 <asl file>"
    exit 1
fi

# Create build directory for intermediate files
mkdir -p "$BUILD_DIR"

# Derive the AML path next to the input ASL (iasl writes the AML in the
# same directory as the input file, not in $PWD).
AML="${1%.asl}.aml"
PREPROCESSED="${1%.asl}.i"

# Remove any stale outputs from a previous run so a failed recompile
# cannot leave the old AML in place to be packaged below.
rm -f "$AML" "$PREPROCESSED" ./img_ssdt.img

iasl -li "$1"

# iasl can return 0 with warnings but skip writing the AML on errors;
# guard against that as well.
if [ ! -f "$AML" ]; then
    echo "ERROR: iasl did not produce '$AML'" >&2
    exit 1
fi

# Move intermediate files to build directory
[ -f "$AML" ] && mv "$AML" "$BUILD_DIR/"
[ -f "$PREPROCESSED" ] && mv "$PREPROCESSED" "$BUILD_DIR/"

mkdir -p "$DIR"
rm -f "$DIR"/*
cp "$BUILD_DIR/$(basename $AML)" "$DIR"
find kernel | cpio -H newc --create > img_ssdt.img

sudo cp img_ssdt.img /boot
