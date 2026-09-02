# massMusicTagger, and discogstagger3 with it.
#
# The build context is this directory. massMusicTagger is installed from a
# pinned git ref and carries its own tagging core -- there is no longer a
# second package whose version has to be paired with it.
#
# It used to build from ../massMusicTagger with ../discogstagger3 and this
# directory supplied as extra build contexts. That needed `additional_contexts`,
# which requires Compose v2.17+ and fails outright on older ones ("Additional
# property additional_contexts is not allowed"), and it meant two source repos
# had to be cloned alongside this one. Installing from a ref removes both: this
# repo now builds on its own.
#
# massMusicTagger now carries the tagging core itself, so discogstagger3 is no
# longer installed here and the `discogstagger` entry point is gone with it.
# For discogstagger3 on its own, use docker-dt3.

FROM python:3.12-slim

# compose.yaml passes the real value; this default only applies to a bare
# "docker build" with no --build-arg. It said v2.0.0 long after that stopped
# being current, so anyone building this file directly got a two-major-version
# old tagger and no hint of it.
ARG MMT_REF=v3.18.1

LABEL org.opencontainers.image.source="https://github.com/sjbrownrigg/massMusicTagger"
LABEL org.opencontainers.image.description="Multi-source mass audio tagger (Discogs -> MusicBrainz -> existing tags)"
LABEL org.opencontainers.image.revision="${MMT_REF}"

#   git                  pip installs from git+https URLs
#   ffmpeg               decoding, ReplayGain (r128gain wraps it), CUE splitting
#   shntool              CUE sheet splitting, fallback for non-FLAC
#   flac                 FLAC encode/decode
#   libdiscid0           DiscID computation, MusicBrainz tier 5
#   libchromaprint-tools fpcalc, for AcoustID tiers 6 and 7
#   gosu                 drop from root to PUID/PGID in the entrypoint
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        shntool \
        flac \
        libdiscid0 \
        libchromaprint-tools \
        gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN pip install --no-cache-dir \
    "massmusictagger[fingerprint] @ git+https://github.com/sjbrownrigg/massMusicTagger.git@${MMT_REF}"

# No sample files are staged here on purpose.
#
# massMusicTagger and discogstagger3 ship their own reference configs inside
# their packages, and `--new-config` writes from those. Staging copies in the
# image made the deployment a second source of truth for something the package
# already owns, and the two could drift.
#
#   docker compose run --rm mmt --new-config

# Configuration is a directory, which is why there is no -c switch. Both tools
# read the same one: mmt loads config.yaml and the credentials beside it, and
# hands the same path to discogstagger3.
ENV MMT_CONFIG_DIR=/config
ENV DISCOGSTAGGER_CONFIG_DIR=/config

# Mutable runtime state: the OAuth token, the API caches, the audit and run
# logs. Without these they default under HOME, which for the mmt user is /app
# and is not writable.
ENV DISCOGSTAGGER_STATE_DIR=/cache
ENV MMT_CACHE_DIR=/cache

RUN mkdir -p /cache

VOLUME ["/incoming", "/sorted", "/archive", "/config", "/cache"]

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "mmt"]
CMD ["-w"]
