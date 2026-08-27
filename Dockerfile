# massMusicTagger, and discogstagger3 with it.
#
# One image, two commands. mmt is a wrapper around dt3 and installs it as a
# dependency, and dt3 ships a `discogstagger` console script -- so a separate
# dt3 container would be the same code twice:
#
#   docker compose run --rm mmt ...                              # mmt
#   docker compose run --rm --entrypoint discogstagger mmt ...    # dt3 alone
#
# Build context is ../massMusicTagger, with ../discogstagger3 as a second
# context so both can be iterated locally -- they are expected to keep evolving
# as Mozarr's requirements land.

FROM python:3.12-slim

ARG MMT_REF=unknown
ARG DT3_REF=unknown

LABEL org.opencontainers.image.source="https://github.com/sjbrownrigg/massMusicTagger"
LABEL org.opencontainers.image.description="Multi-source mass audio tagger (Discogs -> MusicBrainz -> existing tags)"
LABEL org.opencontainers.image.revision="${MMT_REF}"
LABEL uk.co.mozarr.discogstagger3.revision="${DT3_REF}"

# From massMusicTagger's own Dockerfile, which documents each one:
#   git                  pip installs from git+https URLs
#   ffmpeg               decoding, ReplayGain (r128gain wraps it), CUE splitting
#   shntool              CUE sheet splitting, fallback for non-FLAC
#   flac                 FLAC encode/decode
#   libdiscid0           DiscID computation, MusicBrainz tier 5
#   libchromaprint-tools fpcalc, for AcoustID tiers 6 and 7
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

# discogstagger3 from the local checkout, first.
#
# This used to install mmt first and then overwrite dt3. That made pip resolve
# mmt's "discogstagger3 @ git+https://...@<sha>" dependency over the network --
# so a build from two local checkouts still failed whenever that SHA had not
# been pushed yet ("upload-pack: not our ref"), even though the very next layer
# threw the downloaded copy away.
COPY --from=dt3 . /src/dt3
RUN pip install --no-cache-dir /src/dt3

# Then mmt, with its dependency list still the source of truth.
#
# Everything mmt declares is installed except discogstagger3 itself, which is
# already present from the checkout above. Generating the list from
# pyproject.toml rather than restating it here means a new dependency added to
# mmt is picked up automatically instead of being silently missed.
COPY . /src/mmt
RUN python - <<'EOF' > /tmp/requirements.txt
import tomllib

with open("/src/mmt/pyproject.toml", "rb") as fh:
    project = tomllib.load(fh)["project"]

deps = list(project.get("dependencies", []))
deps += project.get("optional-dependencies", {}).get("fingerprint", [])

for dep in deps:
    # dt3 comes from the local checkout, not from git.
    if dep.split("@")[0].strip().lower().replace("_", "-") == "discogstagger3":
        continue
    print(dep)
EOF
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && pip install --no-cache-dir --no-deps /src/mmt \
 && rm -f /tmp/requirements.txt

# No sample files are staged here on purpose.
#
# massMusicTagger and discogstagger3 ship their own reference configs inside
# their packages, and `--new-config` writes from those. Staging copies in the
# image made the deployment a second source of truth for something the package
# already owns, and the two could drift.
#
#   docker compose run --rm mmt --new-config

ENV DISCOGSTAGGER_STATE_DIR=/cache

# Where discogstagger3 looks for its configuration. Naming the directory rather
# than a file is what removed the -c switch: a configuration is config.yaml and
# formats.ini resolving relative to each other, so it moves as a unit.
ENV DISCOGSTAGGER_CONFIG_DIR=/config

# massMusicTagger's own config directory. Same directory: mmt loads config.yaml
# and the credentials beside it, and hands the same path to discogstagger3.
ENV MMT_CONFIG_DIR=/config

# massMusicTagger's MusicBrainz / Cover Art Archive cache. Without this it
# defaults under HOME, which for the mmt user is /app -- not writable, so the
# run died on startup.
ENV MMT_CACHE_DIR=/cache

# Pre-created so the named volume initialises with a usable mode.
RUN mkdir -p /cache

VOLUME ["/music", "/config", "/cache"]

COPY --chmod=0755 --from=deploy entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "mmt"]
CMD ["-w"]
