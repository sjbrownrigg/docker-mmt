#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

CONFIG_DIR="${CONFIG_DIR:-/config}"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"

# ── Refuse to run without a config the operator has actually reviewed ────────
#
# Tagging renames and moves files in the music library, so running against
# defaults nobody chose is not a reasonable fallback. Seeding happens first, so
# by the time this message is printed the files it names already exist.
# Informational flags need no configuration -- refusing to print --help
# because there is no config yet is unhelpful, and --version is how you check
# what an image contains before configuring it at all.
wants_info_only() {
    for arg in "$@"; do
        case "$arg" in
            -h|--help|--version|--new-config|--force-new-config) return 0 ;;
        esac
    done
    return 1
}

require_config() {
    [ -f "${CONFIG_FILE}" ] && return 0

    cat >&2 <<EOF

No configuration found at ${CONFIG_FILE}

  Create one:

    docker compose run --rm mmt --new-config

  That writes config.yaml, formats.ini and a credentials/ directory here,
  from the reference configs inside the packages themselves. It never
  overwrites anything you have already edited.

  Then edit ${CONFIG_DIR}/config.yaml. Nothing in it needs to name another
  file: formats.ini is found because it sits beside it, and every
  ${CONFIG_DIR}/credentials/*.yaml is loaded automatically.

  Credentials can also come from the environment, which overrides the
  file -- set DISCOGS_USER_TOKEN in .env rather than committing a token.

Refusing to run: tagging renames and moves files, so it will not run
against settings you have not reviewed.

EOF
    exit 78  # EX_CONFIG
}

# ── Refuse to run when a share is not actually mounted ──────────────────────
#
# compose.wsl.yaml sets create_host_path: false on the data binds, and its
# comment claims that stops an absent path mounting an empty directory. It does
# not. That setting refuses a bind source that does not *exist*; it says nothing
# about one that exists and is empty because the share behind it was never
# mounted. On WSL2 /mnt/nas/incoming is an ordinary directory until the mount
# script runs, so the bind succeeds, the container reports itself healthy, and a
# run finds nothing to do.
#
# Observed 2026-10-26: all three of /incoming, /sorted and /archive were empty
# inside a container that had started cleanly, because nothing but C: was
# mounted in WSL.
#
# Emptiness alone cannot be the test -- an incoming directory is legitimately
# empty once everything has been tagged. A sentinel file can: it lives on the
# share, so it is present exactly when the share is mounted and absent exactly
# when it is not.
#
# Create them once, through the mountpoints and only while the shares are
# mounted -- written while unmounted they land on the host and the share hides
# them on mount, giving a sentinel that is present precisely when the share is
# not:
#
#   touch /mnt/nas/{incoming,sorted,archive}/.mmt-mounted
#
# Set MMT_REQUIRE_SENTINEL=0 to skip the check -- for a deployment whose data
# directories are local, or an image being exercised without the library.
MOUNT_SENTINEL="${MMT_MOUNT_SENTINEL:-.mmt-mounted}"

require_mounts() {
    [ "${MMT_REQUIRE_SENTINEL:-1}" = "0" ] && return 0

    local missing=()
    local dir
    for dir in /incoming /sorted /archive; do
        [ -d "$dir" ] || continue
        [ -e "${dir}/${MOUNT_SENTINEL}" ] || missing+=("$dir")
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    cat >&2 <<EOF

Not mounted: ${missing[*]}

  Each of these should carry a ${MOUNT_SENTINEL} file. None was found, which
  means the share behind the bind mount is not mounted on the host -- the
  directory exists, so Docker mounted it happily, and it is empty.

  On WSL2:

    sudo bash bootstrap/mount-writable-wsl.sh incoming sorted archive

  Then start the container again.

  Refusing to run: a tagger pointed at an empty directory finds nothing, exits
  successfully and looks like it worked. That is worse than not starting.

  If these directories really are local and not mounted shares, create the
  sentinels once (touch <dir>/${MOUNT_SENTINEL}) or set
  MMT_REQUIRE_SENTINEL=0.

EOF
    exit 69  # EX_UNAVAILABLE
}


if [ "$(id -u)" = "0" ]; then
    getent group mmt >/dev/null 2>&1 \
        && groupmod -o -g "$PGID" mmt \
        || groupadd -o -g "$PGID" mmt

    id -u mmt >/dev/null 2>&1 \
        && usermod -o -u "$PUID" -g "$PGID" mmt \
        || useradd -o -u "$PUID" -g "$PGID" -M -d /app -s /usr/sbin/nologin mmt

    # Not /music: this container does write there, but a recursive chown across
    # the library would be slow and is not this container's decision to make.
    #
    # Not /app either, any more. That was only ever needed because the Discogs
    # OAuth .token was written to the working directory; it now goes to the
    # state directory, which is /cache here (DISCOGSTAGGER_STATE_DIR).
    for dir in /config /cache; do
        [ -d "$dir" ] && chown -R mmt:mmt "$dir" 2>/dev/null || true
    done

    wants_info_only "$@" || { require_config; require_mounts; }

    exec gosu mmt "$@"
fi
wants_info_only "$@" || { require_config; require_mounts; }

exec "$@"
