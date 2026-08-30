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

# A sibling checkout is not required, but if it is here it is worth saying
# whether what you are about to build matches it -- the usual surprise is
# building a tag while iterating on unpushed commits next door.
#
# Only massMusicTagger. This once also checked ../discogstagger3, which has
# not been part of this image since massMusicTagger 3.0.0 absorbed its core --
# so it warned that changes there would not reach the image, which was true
# but only because nothing there ever could.
for src in "${MMT_SRC:-../massMusicTagger}"; do
    [[ -d "$src/.git" ]] || continue
    head="$(git -C "$src" rev-parse --short HEAD)"
    if [[ -n "$(git -C "$src" status --porcelain)" ]]; then
        echo "note: ${src} has uncommitted changes at ${head}." >&2
        echo "      They will NOT be in this image -- it builds from a pushed ref." >&2
    fi
done

# Resolve the ref to a commit before building.
#
# Docker keys the pip layer on the build argument. Passing a branch name means
# the argument does not change when the branch moves, so a rebuild after a push
# silently reuses the old layer and produces an image of yesterday's code --
# which looks exactly like a successful build.
REF="${MMT_REF:-}"
if [[ -n "$REF" ]]; then
    SHA="$(git ls-remote https://github.com/sjbrownrigg/massMusicTagger.git "$REF" | cut -f1)"
    if [[ -n "$SHA" ]]; then
        echo "massMusicTagger  $REF -> ${SHA:0:12}"
        export MMT_REF="$SHA"
    else
        echo "note: '$REF' is not a branch or tag on the remote; using it as-is." >&2
    fi
fi

exec docker compose build "$@"
