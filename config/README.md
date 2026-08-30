# /config

Everything user-configurable lives here, grouped by purpose. This directory is
mounted into the container at `/config`.

```
config.yaml              your settings -- the only file you must create
formats.ini              your file and directory naming (optional)
credentials/             API tokens, kept apart so they are easy to exclude
  discogs.yaml
  musicbrainz.yaml
templates/               the Mako templates that produce .nfo and .m3u
  info.txt
  m3u.txt
format_codes.yaml        how a release's format becomes a code: CD, DM, 2xLP
char_substitutions.yaml  characters replaced per char_profile
source_hints.yaml        keywords that identify a source from its folder name
```

Create it with `docker compose run --rm mmt --new-config`, which writes these
from the reference copies inside the package itself. It never overwrites a
file that is already there, so it is safe to re-run to pick up anything new.
There is no `samples/` directory: the package owns the reference copies, and
the deployment does not keep a second set that could drift.

Everything here is yours to change, but the last four behave differently from
the first two, and the difference matters:

**The rule tables** — `format_codes.yaml`, `char_substitutions.yaml`,
`source_hints.yaml` — arrive **entirely commented out**, and are **merged over**
the packaged tables. Uncomment one abbreviation and only that abbreviation
changes; everything else keeps coming from the package, and keeps improving
with each upgrade. A table you have not edited changes nothing at all.

**The templates** arrive live, because a commented-out template produces
nothing. They shadow the packaged ones **per file**: editing `info.txt` changes
the `.nfo` and leaves the `.m3u` coming from the package. Delete a file here to
go back to the packaged version.

`config.yaml` does not reference `formats.ini`; it is found because it sits
beside it under that name.

## Why paths are relative

Every path in `config.yaml` resolves against `config.yaml`'s own directory, so
nothing in here names `/config` explicitly. The same directory therefore works
unchanged as a bind mount in the container, as a Docker volume, or as a plain
directory on a laptop — no absolute paths to rewrite when you move it.

## First run

There is nothing to copy by hand. Starting the container without a
`config.yaml` refuses rather than guessing at defaults, because tagging
renames and moves files:

```bash
docker compose run --rm mmt --new-config
```

Then edit `config/config.yaml`. Credentials come from the environment via
`.env` — `DISCOGS_USER_TOKEN` — rather than being written into a file that
could reach an image layer.

Nothing you have edited is ever overwritten. Only `samples/` is refreshed.


## Credentials

`discogs.user_token` in `credentials/discogs.yaml` is deliberately empty:
`DISCOGS_USER_TOKEN` from `.env` overrides it, so the token never enters a file
that could be committed or copied into an image layer.

The AcoustID key has no environment override yet, so it stays in
`credentials/musicbrainz.yaml` — which is gitignored, along with everything
else in this directory except the READMEs.

## Mounts

`/incoming` and `/sorted` are mounted as separate roots rather than the library
root, so this container cannot see the rest of the collection. Both must be
writable: massMusicTagger writes its done marker into the source directory and
the tagged copy into the destination.

`/cache` holds runtime state — the Discogs and MusicBrainz caches, the OAuth
token, the audit log and the run log.
