# Server

NeoForge 1.21.1 (21.1.265, Java 21) on [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server).
The mod list is **not** written here — it is generated into `mods.generated.env` from
`../mods.json` by `../scripts/generate`.

## Layout

| File                 | Committed           | What it is                                                                                                                   |
| -------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `docker-compose.yml` | yes                 | The server and the lazymc proxy that sleeps/wakes it, exactly as they run. Contains no secrets.                              |
| `bootstrap`          | yes                 | Restore the world from Backblaze B2 if this machine has none, then start. Run this first on a fresh machine.                 |
| `restart`            | yes                 | Save the world, recreate the containers, report. The deploy step.                                                            |
| `check-world`        | yes                 | Refuses to start unless `data/world` is Minecraft 1.21.1 or older. Run by `restart` and `bootstrap`.                        |
| `.env.example`       | yes                 | Template for `.env`.                                                                                                         |
| `.env`               | **no** — gitignored | `RCON_PASSWORD`, `PLAYIT_SECRET_KEY`, plus the four Backblaze B2 values `bootstrap` restores from. This repo is public; the real values live only here and on the VM. |
| `mods.generated.env` | yes                 | `MODRINTH_PROJECTS=...`, generated. Never hand-edit.                                                                         |
| `config/`            | yes                 | Server mod configs. Copied over `data/config/` on every start, so a committed change wins. See "Changing a mod's config".     |
| `data/`              | no — gitignored     | World, logs, and the mods the container downloads.                                                                           |
| `.restore-stage/`    | no — gitignored     | Scratch space `bootstrap` downloads a snapshot into. Deleted on exit.                                                        |

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
git clone https://github.com/A1K2S3/minecraft.git /root/mc-repo
cd /root/mc-repo/server
cp .env.example .env
$EDITOR .env          # RCON_PASSWORD, PLAYIT_SECRET_KEY + the four Backblaze B2 values
./bootstrap --logs
```

**Use `bootstrap`, not `docker compose up -d`, the first time.** It asks the B2
repository named in `.env` whether a world is already backed up there. If one is, it
downloads it into `data/` _before_ the server starts, so the container boots the real
world. If the repository is empty — a genuinely new server — it just starts and the world
generates.

**Automatic backups are currently disabled** (see Backups below), so B2 holds only the
last snapshot taken before they were switched off. Anything played since then exists
only in this VM's `data/`.

`bootstrap` is safe to re-run. Once `data/world` exists it never touches it again, so it
also works as the everyday "start the stack" command.

If it cannot read the repository — wrong key, wrong `RESTIC_PASSWORD`, B2 unreachable —
it **refuses to start** rather than generating a fresh world on top of a perfectly good
backup. Fix `.env` and re-run.

The container downloads every mod in `MODRINTH_PROJECTS` on boot. Each entry is pinned to a
version ID and every dependency is its own entry, so nothing else is resolved. First boot
takes a few minutes.
Because of lazymc (below), that first boot happens when the first player joins.

## Sleeping when empty

Players reach the server through a **playit.gg** tunnel (the `playit` container; the
tunnel and its public address are configured in the playit.gg dashboard, pointing at
`127.0.0.1:25565`). That lands on **lazymc** on port 25565, never on `mc` directly
([`lazymc-docker-proxy`](https://github.com/joesturge/lazymc-docker-proxy)). It starts the
`mc` container when someone joins and `docker stop`s it once nobody has been online for
10 minutes (`lazymc.time.sleep_after`), so the JVM exits and its 8G of RAM is freed.

- **Joining a sleeping server** wakes it. The client is held, then shown a "server is
  starting" message if boot takes longer; reconnect after a minute or two.
- **While asleep** the server list still answers, with a sleeping MOTD.
- **Nothing ticks while asleep.** Farms, ComputerCraft turtles and chunk loaders stop
  with the server. A turtle mid-program reboots when the server next starts.
- `mc` has `restart: "no"` on purpose — lazymc owns its lifecycle. `lazymc` itself has
  `restart: unless-stopped`, so after a VM reboot the proxy is back and `mc` stays asleep
  until someone joins.
- On startup lazymc stops `mc` if it is running, so right after `restart` or `bootstrap`
  `mc` shows as exited. That is expected.
- Both containers sit on `mc-net` with static addresses (`172.29.0.2` / `.3`) because
  lazymc must reach `mc` while it is stopped and has no DNS name.
- lazymc mounts the Docker socket to start and stop `mc`. That is root-equivalent on the
  host; the container is the published upstream image.

To force the server up without joining: `docker compose start mc`.

## Cutting over from Fabric 1.21.11

The live world is Fabric 1.21.11 (DataVersion 4671). NeoForge 1.21.1 must never open it
unconverted, so `restart` and `bootstrap` run `check-world` first and refuse to start
above DataVersion 3955. lazymc does not bypass that: it only `docker start`s the existing
`mc` container, and `restart`/`bootstrap` are what create it from the new compose file. The
one gap is a running stack: `git pull` changes nothing in a running container, but a
plain `docker compose up -d` would recreate `mc` without the check. So **stop the stack
before pulling, convert, then restart with `./restart`** (never a bare `docker compose up`).

On the VM, in order:

1. Announce the downtime. Everyone reinstalls the client afterwards (the root `README.md`).
2. `cd /root/mc-repo/server && docker compose exec mc rcon-cli "save-all flush"`, then
   `docker compose down`. lazymc is down too, so nothing can wake `mc`.
3. Back up: `tar czf ~/world-fabric-1.21.11-$(date +%F).tar.gz -C data world`. Keep it off the VM too.
4. Convert that archive on a workstation with
   [minecraft-1.21.1-backport](https://github.com/KiraKami-dev/minecraft-1.21.1-backport):
   `./convert.sh world-final.tar.gz ~/backport-out`, then read `summary.txt` (scan errors 0,
   `NOT allowed: 0`, smoke test 0 errors). Steps are in its `docs/BACKPORT.md`.
5. Upload: `mv data/world data/world-fabric-1.21.11`, then
   `rsync -a user@workstation:backport-out/world/ data/world/`. Also
   `mv data/mods data/mods-fabric-1.21.11` (NeoForge cannot load Fabric jars).
6. `git pull`, then `./restart --logs`. The guard passes on the converted world. Join to
   wake lazymc and watch for `Done`.
7. Rollback if it fails: `docker compose down`, `git checkout` the previous commit,
   `mv data/world data/world-failed && mv data/world-fabric-1.21.11 data/world`,
   `mv data/mods-fabric-1.21.11 data/mods`, `./restart`. (Do this with the old
   commit checked out, since the guard would refuse the Fabric world on the new one.)

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

## Changing a mod's config

Server-side mod configs live in `server/config/`, mounted read-only at `/config`. On every
start the image copies each file there over its namesake in `data/config/`
(`SYNC_SKIP_NEWER_IN_DESTINATION=false`, because the mods rewrite their files on each boot
and would otherwise look newer). A file in `server/config/` is therefore the only copy that
counts: an edit made on the VM in `data/config/` is undone at the next start. Configs not in
`server/config/` are left alone.

To change one: copy the server's current file into `server/config/` (so every other value
stays as it is), change the value, commit, push, then `git pull` and `./server/restart` on
the VM. Waystones syncs its config to clients at login, so `waystones-common.toml`
(teleport XP cost disabled) needs nothing on friends' machines.

Gamerules are not files: they live in the world's `level.dat`. Keep them in git as lines of
`RCON_CMDS_STARTUP` in `docker-compose.yml`, which the image runs over RCON on every
container start (lazymc wakes included) once the server is listening. Currently:
`gamerule playersSleepingPercentage 30` (30% of online players in bed skips the night).

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
docker compose ps -a                 # is it up (mc "exited" = asleep)
docker compose logs -f mc            # tail the server log
docker compose logs -f lazymc        # sleep / wake events
docker compose start mc              # wake the server without joining
docker compose exec mc rcon-cli      # console; reads RCON_PASSWORD from the env
```

## Backups

**Automatic backups are currently disabled.** The `itzg/mc-backup` sidecar that pushed
the world to Backblaze B2 nightly has been removed from `docker-compose.yml`, to be
reimplemented later. Until then the world exists only in this VM's `data/`.

The last snapshot it took is still in the B2 restic repository, and `bootstrap` can still
restore it — so keep the four B2 values in `.env`, and never lose `RESTIC_PASSWORD`: it
is the only key to that snapshot.

To see what is in B2:

```sh
docker run --rm --env-file "$(pwd)/.env" restic/restic:latest snapshots
```

### Restore

On a new machine, or after losing `data/`, that is just the fresh-VM flow above —
`bootstrap` restores automatically when no local world is present.

To deliberately roll the current world back to the B2 snapshot (the last one taken before
backups were disabled):

```sh
docker compose down          # bootstrap refuses to overwrite a running server
./bootstrap --force-restore  # deletes data/world, restores the snapshot, starts
```

`--force-restore` is destructive and says so before acting. Without it, `bootstrap`
never touches an existing world.
