# docker-mmt

Docker deployment for [massMusicTagger](https://github.com/sjbrownrigg/massMusicTagger),
which builds on [discogstagger3](https://github.com/sjbrownrigg/discogstagger3).

Kept out of the massMusicTagger repo deliberately: a deployment is a different
thing from the tool it deploys. It carries host-specific decisions — NAS
addresses, UID/GID, which directories are mounted where — that have no business
being versioned alongside the source, and it changes on a different rhythm.

## One image, two commands

massMusicTagger installs discogstagger3 as a dependency, and discogstagger3
ships its own `discogstagger` console script. A separate container would be the
same code twice, so both entry points live in one image:

```bash
docker compose run --rm mmt ...                             # massMusicTagger
docker compose run --rm --entrypoint discogstagger mmt ...  # discogstagger3 alone
```

## Quick start

```bash
cp .env.example .env          # then set DISCOGS_USER_TOKEN
./build.sh
docker compose run --rm mmt --new-config
```

That writes `config.yaml`, `formats.ini` and a `credentials/` directory into
`config/`, from the reference configs inside the packages themselves. It never
overwrites anything you have already edited.

Running without a configuration refuses rather than falling back to defaults:
tagging renames and moves files, so it will not run against settings you have
not reviewed.

Set `common.source_dir` to `/incoming` and `common.dest_dir` to `/sorted`, then:

```bash
docker compose up -d          # watch mode
```

## Layout

| Path | Purpose |
|---|---|
| `config/` | Your live configuration, mounted at `/config` |
| `.env` | Credentials and host settings. Never committed |
| `Dockerfile` | Builds massMusicTagger with discogstagger3 from local checkouts |
| `entrypoint.sh` | Seeds samples, drops to PUID/PGID, refuses without a config |
| `build.sh` | Builds from `../massMusicTagger` and `../discogstagger3`, stamping both SHAs |

## Mounts

`/incoming`, `/sorted` and `/archive` are mounted as **separate roots** rather
than the library root, so the container cannot see — let alone rewrite — the
rest of the collection. All must be writable: massMusicTagger writes its done
marker into the source directory and the tagged copy into the destination.

`/cache` holds runtime state: the Discogs and MusicBrainz caches, the OAuth
token, the audit log and the run log.

## Configuration

There is no `-c` switch. A configuration is a directory — `config.yaml`,
`formats.ini` and `credentials/` resolving relative to each other — so the
container points `MMT_CONFIG_DIR` and `DISCOGSTAGGER_CONFIG_DIR` at `/config`.

Nothing inside `config.yaml` names `/config`: `formats.ini` is found because it
sits beside it, and every `credentials/*.yaml` is loaded automatically.

Credentials come from `.env` where possible, so a token never enters a file that
could be committed or copied into an image layer.

See [config/README.md](config/README.md) for the full layout, including the two
AcoustID keys and why they are easy to confuse.

## WSL2

NFS Docker volumes fail here with `operation not permitted` — a WSL2 mount
syscall restriction. Use bind mounts onto an already-mounted share instead.

Set this in `.env` and plain `docker compose up` picks up the override, with no
`-f` flags to remember:

```
COMPOSE_FILE=compose.yaml:compose.wsl.yaml
```

**The mounted paths must be writable.** `docker-mozarr` mounts the music share
read-only on purpose — mozarr only reads — but massMusicTagger writes a done marker into
the source directory and the tagged copy into the destination, so a read-only
mount fails partway through a run.

Mount just the working directories read-write, leaving the rest of the library
protected:

```bash
sudo bash bootstrap/mount-writable-wsl.sh incoming sorted archive
```

Then point `INCOMING_DIR`, `SORTED_DIR` and `ARCHIVE_DIR` in `.env` at those mount
points. The script prints the exact lines.
