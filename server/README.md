# Server

Fabric 1.21.11 on [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server).
The mod list is **not** written here — it is generated into `mods.generated.env` from
`../mods.json` by `../scripts/generate`.

## Layout

| File | Committed | What it is |
| --- | --- | --- |
| `docker-compose.yml` | yes | The server and the backup sidecar, exactly as they run. Contains no secrets. |
| `bootstrap` | yes | Restore the world from Backblaze B2 if this machine has none, then start. Run this first on a fresh machine. |
| `restart` | yes | Save the world, recreate the containers, report. The deploy step. |
| `.env.example` | yes | Template for `.env`. |
| `.env` | **no** — gitignored | `RCON_PASSWORD` plus the four Backblaze B2 backup values. This repo is public; the real values live only here and on the VM. |
| `mods.generated.env` | yes | `MODRINTH_PROJECTS=...`, generated. Never hand-edit. |
| `data/` | no — gitignored | World, logs, and the mods the container downloads. |
| `.restore-stage/` | no — gitignored | Scratch space `bootstrap` downloads a snapshot into. Deleted on exit. |

`docker-compose.yml` pulls both env files:

```yaml
env_file:
  - ./.env
  - ./mods.generated.env
```

so `RCON_PASSWORD` is only ever the `${RCON_PASSWORD}` reference in the compose file, and
the mod list is only ever the generated file.

## First run on a fresh VM

```sh
git clone https://github.com/Adarsh077/minecraft.git /root/mc-repo
cd /root/mc-repo/server
cp .env.example .env
$EDITOR .env          # RCON_PASSWORD + the four Backblaze B2 values
./bootstrap --logs
```

**Use `bootstrap`, not `docker compose up -d`, the first time.** It asks the B2
repository named in `.env` whether a world is already backed up there. If one is, it
downloads it into `data/` *before* the server starts, so the container boots the real
world. If the repository is empty — a genuinely new server — it just starts and the world
generates.

That is the whole disaster-recovery story: this repo plus the four B2 values in `.env`
is enough to rebuild the server from nothing on any machine. Nothing else on the old box
is load-bearing.

`bootstrap` is safe to re-run. Once `data/world` exists it never touches it again, so it
also works as the everyday "start the stack" command.

If it cannot read the repository — wrong key, wrong `RESTIC_PASSWORD`, B2 unreachable —
it **refuses to start** rather than generating a fresh world on top of a perfectly good
backup. Fix `.env` and re-run.

The container downloads every mod in `MODRINTH_PROJECTS` on boot, plus their required
dependencies (`MODRINTH_DOWNLOAD_DEPENDENCIES: required`). First boot takes a few minutes.

## Deploying a mod change

From your machine:

```sh
$EDITOR mods.json          # add, remove, or re-pin a mod
scripts/generate
git add mods.json server/mods.generated.env client/mods.generated.tsv client/purge.generated.txt
git commit -m "Add <mod>"
git push
```

On the VM:

```sh
cd /root/mc-repo
git pull
./server/restart          # flush the world, recreate the containers, report
```

`server/restart` is the safe way to do the last step: it broadcasts a warning to anyone
online, forces a `save-all flush` over RCON so no progress is lost, then runs
`compose down` + `compose up -d` so the new `mods.generated.env` takes effect. Add
`--logs` to follow the server log afterwards. It refuses to run if `.env` is missing, and
refuses to stop an online server whose save could not be confirmed unless you pass
`--force`. Running it twice is safe.

The manual equivalent is `docker compose up -d` from this directory — compose recreates
the container when an env file changes, so a `git pull` followed by `up -d` is the whole
deploy. `restart` just adds the save and the guards. Nothing else on the VM needs editing — in
particular, never edit `MODRINTH_PROJECTS` by hand on the server, because the next
`git pull` would overwrite it and the client would silently drift out of sync.

Removing a mod from `mods.json` stops the container downloading it, but does not delete
the jar already sitting in `data/mods/`. Delete it there too, then restart.

## Server-only vs shared mods

`side` in `mods.json` decides this and nothing else does. A mod marked `server` never
reaches a friend's client, and the client installers actively remove server-only jars
from `mods/` (their filename prefixes are generated into `client/purge.generated.txt`).
A mod marked `both` must be present on both sides at the same version or clients will be
rejected at login.

## Common operations

```sh
./bootstrap                          # restore-if-needed, then start (fresh machine, or just start)
./restart                            # save the world, recreate, report (see above)
./restart --logs                     # same, then follow the log
docker compose ps                    # is it up
docker compose logs -f mc            # tail the server log
docker compose logs -f backup        # tail the backup sidecar
docker compose restart               # restart without re-reading compose changes
docker compose exec mc rcon-cli      # console; reads RCON_PASSWORD from the env
```

## Backups

Automated, off-box, and hands-off. The `backup` service in `docker-compose.yml` is
[`itzg/mc-backup`](https://github.com/itzg/docker-mc-backup); it uploads the world
straight to **Backblaze B2** through [restic](https://restic.net/). Nothing is written to
this VM's disk, so a dead disk does not take the backup with it.

| | |
| --- | --- |
| When | **00:00 UTC daily** (`CRON_SCHEDULE: "0 0 * * *"` — always UTC, `TZ` only affects log timestamps) |
| Retention | **one snapshot** (`PRUNE_RESTIC_RETENTION: "--keep-last 1"`) |
| Where | The restic repository in `RESTIC_REPOSITORY`, on B2's S3-compatible endpoint |
| What | All of `/data` except `*.jar`, `cache`, `logs`, `*.tmp`, `libraries`, `versions`, `.fabric`, `downloads`, `world.fresh-bak` — everything excluded is re-downloaded on boot |
| Consistency | The sidecar issues `save-all` over RCON and syncs the filesystem before reading, so the snapshot is not a torn mid-write copy |
| Mount | `./data:/data:**ro**` — the sidecar can never write the world |

It does **not** back up on container start (`BACKUP_ON_STARTUP: "false"`). That is
deliberate: `restart` recreates the containers on every deploy, and with a
one-snapshot retention an on-start backup would replace the good snapshot with a
just-deployed one each time.

### Two things to know about a one-snapshot retention

1. **There is no history.** The snapshot is replaced every night, so a problem you do
   not notice within 24 hours — a griefed base, a corrupted region, a mod that ate a
   chunk — is permanent once the next backup runs. To keep more, widen one value in
   `docker-compose.yml`: `PRUNE_RESTIC_RETENTION: "--keep-last 7"`. restic deduplicates,
   so seven snapshots of one world cost far less than seven copies.
2. **`RESTIC_PASSWORD` is as critical as the world.** restic encrypts the repository
   with it. There is no reset and no recovery: lose it and the bytes in B2 are
   permanently unreadable. Keep a copy somewhere that is not this VM.

### Check on it

```sh
docker compose logs --tail=100 backup                  # did last night's run work
docker compose exec backup backup now                  # run one immediately
docker run --rm --env-file "$(pwd)/.env" restic/restic:latest snapshots   # what is in B2
```

### Restore

On a new machine, or after losing `data/`, that is just the fresh-VM flow above —
`bootstrap` restores automatically when no local world is present.

To deliberately roll the current world back to the B2 snapshot:

```sh
docker compose down          # bootstrap refuses to overwrite a running server
./bootstrap --force-restore  # deletes data/world, restores the snapshot, starts
```

`--force-restore` is destructive and says so before acting. Without it, `bootstrap`
never touches an existing world.
