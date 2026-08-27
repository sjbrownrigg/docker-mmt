#!/usr/bin/env bash
#
# Build the massMusicTagger image.
#
#   ./build.sh                      # the ref in .env, or the Dockerfile default
#   MMT_REF=some-branch ./build.sh  # a branch, tag or SHA
#
# massMusicTagger is installed from a git ref rather than a local checkout, and
# brings discogstagger3 with it at the commit its pyproject pins. This repo
# builds on its own -- nothing needs cloning alongside it. The ref must be
# pushed, since pip fetches it.

set -euo pipefail
cd "$(dirname "$0")"

# Sibling checkouts are not required, but if they are here it is worth saying
# whether what you are about to build matches them -- the usual surprise is
# building a tag while iterating on unpushed commits next door.
for src in "${MMT_SRC:-../massMusicTagger}" "${DT3_SRC:-../discogstagger3}"; do
    [[ -d "$src/.git" ]] || continue
    head="$(git -C "$src" rev-parse --short HEAD)"
    if [[ -n "$(git -C "$src" status --porcelain)" ]]; then
        echo "note: ${src} has uncommitted changes at ${head}." >&2
        echo "      They will NOT be in this image -- it builds from a pushed ref." >&2
    fi
done

exec docker compose build "$@"
