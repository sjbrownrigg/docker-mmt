# docker-mmt

Docker deployment for
[massMusicTagger](https://github.com/sjbrownrigg/massMusicTagger) — a mass
audio tagger that reads metadata from Discogs and MusicBrainz and files your
music by it.

Kept out of the massMusicTagger repo deliberately: a deployment is a different
thing from the tool it deploys. It carries host-specific decisions — NAS
addresses, UID/GID, which directories are mounted where — that have no business
being versioned alongside the source, and it changes on a different rhythm.

**Docker is one of two supported routes.** If you would rather run
massMusicTagger directly on the machine, its README has
[native installation instructions](https://github.com/sjbrownrigg/massMusicTagger#installing)
covering Debian/Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, macOS and WSL.
Nothing here is required to use the tagger — this repository exists because
Docker is the maintainer's own preference, not because it is the only way.

---

> ## ⚠ Breaking changes in massMusicTagger 3.0.0 — read before upgrading
>
> **A 2.x `config.yaml` will not work as written.** `[details]` had grown to
> 28 keys and its contents moved to `[naming]`, `[artwork]`, `[archiving]`,
> `[tags]` and `[source]`. The old names are **not** honoured, so a setting
> that looks present simply does not apply.
>
> ```bash
> git pull
> docker compose build                          # first: the tool comes from here
> docker compose run --rm mmt --migrate-config
> docker compose up -d
> ```
>
> Build first. `docker compose run` uses the image you already have, so
> migrating before the rebuild runs the *old* tool and quietly does less than
> you expect.
>
> See [Upgrading a 2.x deployment](#upgrading-a-2x-deployment) below.
>
> **3.1.0 is a security release** — album metadata could execute code during
> tagging. Do not stay on 3.0.0.

---

## Relationship to discogstagger3

massMusicTagger absorbed the tagging core it used to import, so this image no
longer contains discogstagger3 and no longer ships its `discogstagger` command.
[docker-dt3](https://github.com/sjbrownrigg/docker-dt3) runs discogstagger3 on
its own; it is unaffected by this and continues to work exactly as before.

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
| `Dockerfile` | Installs massMusicTagger from a pushed git ref — nothing is built from a local checkout |
| `entrypoint.sh` | Drops to your PUID/PGID and refuses to run without a config you have reviewed |
| `build.sh` | Resolves `MMT_REF` to a commit before building, so a moved branch cannot reuse a stale layer |

## Mounts

`/incoming`, `/sorted` and `/archive` are mounted as **separate roots** rather
than the library root, so the container cannot see — let alone rewrite — the
rest of the collection. All must be writable: massMusicTagger writes its done
marker into the source directory and the tagged copy into the destination.

`/cache` holds runtime state: the Discogs and MusicBrainz caches, the OAuth
token, the audit log and the run log.

## Upgrading a 2.x deployment

3.0.0 regrouped the configuration: `[details]` had grown to 28 keys, and its
contents now live in `[naming]`, `[artwork]`, `[archiving]`, `[tags]` and
`[source]`. The old names are **not** honoured, so a `config.yaml` carried
over from 2.x must be migrated before the container behaves — settings that
look present will simply not apply.

**Build before migrating.** `docker compose run` uses the image you already
have, so a migration run before the rebuild is performed by the *old* tool —
which is how a configuration ends up reporting "needs no changes" while the
new version still has work to do, and how `--annotate-config` comes back as an
unrecognised argument.

```bash
git pull
docker compose build                            # first: the tool comes from here
docker compose run --rm mmt --migrate-config    # rewrites config/config.yaml
docker compose run --rm mmt --annotate-config   # optional: restore the comments
docker compose up -d
docker compose logs -f mmt
```

**Migrate again after upgrading, even if you migrated before.** Each version
has taught `--migrate-config` something new: 3.0.0 moved and removed keys,
3.3.0 also retires deprecated ones. A configuration migrated by an earlier
version still carried live `format_codes`, `char_substitutions` and
`source_hints_file` keys — each naming a `conf/` path that resolves to
nothing, each warning on every run. It is a no-op once there is nothing left
to do, so it is always safe to run.

`--new-config` now also writes `format_codes.yaml`, `char_substitutions.yaml`
and `source_hints.yaml`, entirely commented out: there to read and edit,
changing nothing until a line is uncommented, and merged over the packaged
table when it is.

`--migrate-config` keeps every comment, leaves the original as
`config.yaml.bak`, and lists what it moved and what it dropped. A clean start
logs no "moved to \[section\]" or "was removed in 3.0.0" warnings; if it
does, that setting is not being applied.

3.1.0 also closes a path where album metadata could execute code during
tagging, so do not stay on 3.0.0.

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

## Moving to another host

Three things need doing on a new host, and the first fails *silently* if you
miss it.

**1. Remove `COMPOSE_FILE` from `.env`.** It is a WSL2 workaround. Carrying it
to a Linux host forces the bind-mount override, whose paths will not exist
there — and Docker's default is to create a missing bind source rather than
complain, so you would get empty directories, nothing to tag, and a container
reporting itself healthy. `compose.wsl.yaml` now sets `create_host_path: false`
so this errors at startup instead, but deleting the line is the actual fix. On
Linux you want the NFS volumes in `compose.yaml`.

**2. Nothing else to clone.** The image is built from a pinned git ref, so this
repo stands on its own:

```bash
git clone https://github.com/sjbrownrigg/docker-mmt.git
cd docker-mmt && ./build.sh
```

Set `MMT_REF` to build a different branch, tag or SHA — it has to be pushed,
since pip fetches it.

**3. Create the shared network**, which is external and owned by no stack:

```bash
docker network create mozarr-net
```

**4. Install an NFS client.** Docker's local NFS volume driver uses the host
kernel's, so without it the volumes fail to mount:

```bash
sudo apt install nfs-common          # Debian, Ubuntu
sudo dnf install nfs-utils           # Fedora, RHEL, Rocky, Alma
sudo pacman -S nfs-utils             # Arch
sudo zypper install nfs-client       # openSUSE
```

Then set `NAS_ADDR` and `NAS_MUSIC_PATH` in `.env` and bring it up. Everything
else — `PUID`/`PGID`, the credentials, the config directory — travels unchanged.

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
