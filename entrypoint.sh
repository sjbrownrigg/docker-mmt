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

    wants_info_only "$@" || require_config

    exec gosu mmt "$@"
fi
wants_info_only "$@" || require_config

exec "$@"
