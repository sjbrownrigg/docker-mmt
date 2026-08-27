#!/usr/bin/env bash
#
# Build massMusicTagger with discogstagger3 from the local checkouts, stamping
# both SHAs into the image so what went in is recoverable later.

set -euo pipefail

cd "$(dirname "$0")"

MMT_SRC="${MMT_SRC:-../massMusicTagger}"
DT3_SRC="${DT3_SRC:-../discogstagger3}"

for src in "$MMT_SRC" "$DT3_SRC"; do
    if [[ -n "$(git -C "$src" status --porcelain)" ]]; then
        echo "warning: ${src} has uncommitted changes; the image will include them." >&2
    fi
done

MMT_REF="$(git -C "$MMT_SRC" rev-parse HEAD)"
DT3_REF="$(git -C "$DT3_SRC" rev-parse HEAD)"

echo "massMusicTagger  ${MMT_REF:0:7}  ($(git -C "$MMT_SRC" branch --show-current))"
echo "discogstagger3   ${DT3_REF:0:7}  ($(git -C "$DT3_SRC" branch --show-current))"

exec docker compose build \
    --build-arg MMT_REF="$MMT_REF" \
    --build-arg DT3_REF="$DT3_REF" \
    "$@"
