# /config

Everything user-configurable lives here, grouped by purpose. This directory is
mounted into the container at `/config`.

```
config.yaml              your settings -- the only file you must create
formats.ini              your file and directory naming (optional)
source_hints.yaml        per-directory source overrides (optional)
credentials/             API tokens, kept apart so they are easy to exclude
  discogs.yaml
  musicbrainz.yaml
```

Create it with `docker compose run --rm mmt --new-config`, which writes these
from the reference configs inside the packages themselves. There is no
`samples/` directory: massMusicTagger and discogstagger3 own the reference
copies, and the deployment does not keep a second set that could drift.

That is the whole list. This directory holds what *you* own. Mako templates for
`.nfo`/`.m3u` and the tagging rule tables belong to discogstagger3, ship inside
the package, and are deliberately not copied here -- so they keep improving with
each upgrade instead of freezing at the version installed on setup day.

`config.yaml` does not reference `formats.ini`; it is found because it sits
beside it under that name.

## Why paths are relative

Every path in `config.yaml` resolves against `config.yaml`'s own directory, so
nothing in here names `/config` explicitly. The same directory therefore works
unchanged as a bind mount in the container, as a Docker volume, or as a plain
directory on a laptop — no absolute paths to rewrite when you move it.

## First run

Starting the container populates `samples/` and then stops, because there is no
`config.yaml` yet:

```bash
docker compose run --rm mmt          # populates samples/, explains what to do

cp config/samples/config.yaml    config/config.yaml
cp config/samples/formats.ini    config/formats.ini
cp config/samples/discogs.yaml   config/credentials/discogs.yaml
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
