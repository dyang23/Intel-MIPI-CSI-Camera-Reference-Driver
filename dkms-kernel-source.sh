#!/bin/bash
#
# Stage selected kernel source paths under ./$major.$minor.0/... so the rest
# of the DKMS build (patches + Makefile fragments in dkms.conf) can reference
# them by that fixed prefix.
#
# Order of preference:
#   1. A local kernel source tree specified via KERNEL_SRC_DIR (env var), or
#      the in-tree ./linux/ checkout maintained alongside this project.
#      Using a local tree is offline-safe and avoids re-downloading the same
#      ~145 MB tarball on every `dkms add` (dkms clears the build dir between
#      runs, so wget-based fetching is not cached).
#   2. Fresh wget from kernel.org — original behaviour, kept as fallback.

set -eu

if [[ -z "${kernelver:-}" ]]; then
  kernelver="$(uname -r)"
fi

major=$(echo "$kernelver" | cut -d- -f1| cut -d. -f1)
minor=$(echo "$kernelver" | cut -d- -f1| cut -d. -f2)
patch=$(echo "$kernelver" | cut -d- -f1| cut -d. -f3)

if ! [[ "$major" =~ ^[0-9]+$ ]]; then major=0; fi
if ! [[ "$minor" =~ ^[0-9]+$ ]]; then minor=0; fi
if ! [[ "$patch" =~ ^[0-9]+$ ]]; then patch=0; fi

echo "Downloading major $major minor $minor patch $patch"
if (( patch != 0 )); then
  kernelprefix="linux-$major.$minor.$patch"
else
  kernelprefix="linux-$major.$minor"
fi

# The rest of dkms.conf expects sources under ./$major.$minor.0/...
staged_root="$major.$minor.0"

# ---------------------------------------------------------------------------
# Path 1: local kernel source tree.
#
# We reference the source tree by ABSOLUTE path (not a CWD-relative ./linux)
# so `dkms add` does not have to copy the 7 GB checkout into /usr/src along
# with this project. Prefer $KERNEL_SRC_DIR, then a known location on the
# U-disk.
# ---------------------------------------------------------------------------
declare -a local_candidates=()
if [[ -n "${KERNEL_SRC_DIR:-}" ]]; then
    local_candidates+=("$KERNEL_SRC_DIR")
fi
local_candidates+=("/media/ndk/Dong_U1/dev/linux-6.17")

local_src=""
for cand in "${local_candidates[@]}"; do
    if [[ -f "$cand/Makefile" && -d "$cand/drivers/media" ]]; then
        local_src="$cand"
        break
    fi
done

if [[ -n "$local_src" ]]; then
    echo "Using local kernel source: $local_src"
    for arg in "$@"; do
        src="$local_src/$arg"
        dst="$staged_root/$arg"
        if [[ ! -e "$src" ]]; then
            echo "ERROR: expected path missing in local kernel tree: $src" >&2
            exit 1
        fi
        echo "Staging: $dst"
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    done
    exit 0
fi

# ---------------------------------------------------------------------------
# Path 2: original wget-based fallback.
# ---------------------------------------------------------------------------
wget --no-check-certificate https://mirrors.edge.kernel.org/pub/linux/kernel/v$major.x/$kernelprefix.tar.xz -O $kernelprefix.tar.xz

for arg in "$@"; do
    echo "Extracting: $kernelprefix/$arg"
    tar -xvf "$kernelprefix.tar.xz" "$kernelprefix/$arg" \
      --xform="s,^${kernelprefix//./\\.}/,$staged_root/,"
done
