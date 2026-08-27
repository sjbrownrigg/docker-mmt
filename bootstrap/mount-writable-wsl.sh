#!/usr/bin/env bash
#
# WSL2: mount the working directories read-write, leaving the library alone.
#
#   sudo bash bootstrap/mount-writable-wsl.sh
#
# Why this exists
# ---------------
# docker-mozarr's bootstrap/mount-smb-wsl.sh mounts the whole Music share
# READ-ONLY on purpose -- mozarr only ever reads, and making writes impossible
# is the cheapest way to guarantee that.
#
# discogstagger3 writes. It puts a done marker in the source directory and the
# tagged copy in the destination, so a read-only mount fails partway through a
# run rather than at the start.
#
# Rather than remounting the whole library read-write and losing that
# guarantee, this mounts only the two directories that need it. The rest of the
# collection stays read-only, which is the same reasoning behind mounting
# /incoming and /sorted as separate roots in compose.yaml instead of the
# library root.
#
# drvfs delegates to the Windows SMB client rather than mounting in the WSL
# kernel, which is why it works where NFS does not. Windows already has
# credentials for the share, so no password is needed.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

NAS_HOST="${NAS_HOST:-sloth.local}"
SHARE="${SHARE:-Music}"
TARGET_UID="${SUDO_UID:-1000}"
TARGET_GID="${SUDO_GID:-1000}"

mount_rw() {
    local subdir="$1" target="/mnt/nas/$1"

    mkdir -p "$target"
    if mountpoint -q "$target"; then
        echo "already mounted: $target"
        return
    fi

    echo "mounting \\\\${NAS_HOST}\\${SHARE}\\${subdir} -> ${target} (rw)"
    mount -t drvfs "\\\\${NAS_HOST}\\${SHARE}\\${subdir}" "$target" \
        -o "rw,uid=${TARGET_UID},gid=${TARGET_GID},metadata"
}

for subdir in "$@"; do
    mount_rw "$subdir"
done

if [[ $# -eq 0 ]]; then
    mount_rw incoming
    mount_rw sorted
fi

echo
echo "Verifying:"
for subdir in "${@:-incoming sorted}"; do
    target="/mnt/nas/${subdir}"
    if touch "${target}/.write-test" 2>/dev/null; then
        rm -f "${target}/.write-test"
        echo "  ${target}: writable"
    else
        echo "  ${target}: STILL READ-ONLY -- check the share permissions" >&2
    fi
done

echo
echo "Now set these in .env:"
for subdir in "${@:-incoming sorted}"; do
    echo "  ${subdir^^}_DIR=/mnt/nas/${subdir}"
done
