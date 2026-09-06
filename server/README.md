# Server

Fabric 1.21.11 on [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server).
The mod list is **not** written here — it is generated into `mods.generated.env` from
`../mods.json` by `../scripts/generate`.

## Layout

| File | Committed | What it is |
| --- | --- | --- |
| `docker-compose.yml` | yes | The server, exactly as it runs. Contains no secrets. |
| `.env.example` | yes | Template for `.env`. |
| `.env` | **no** — gitignored | `RCON_PASSWORD`. This repo is public; the real password lives only here and on the VM. |
| `mods.generated.env` | yes | `MODRINTH_PROJECTS=...`, generated. Never hand-edit. |
| `data/` | no — gitignored | World, logs, and the mods the container downloads. |

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
$EDITOR .env          # set RCON_PASSWORD to the real value
docker compose up -d
docker compose logs -f
```

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
./restart                            # save the world, recreate, report (see above)
./restart --logs                     # same, then follow the log
docker compose ps                    # is it up
docker compose logs -f --tail=200    # tail the log
docker compose restart               # restart without re-reading compose changes
docker compose exec mc rcon-cli      # console; reads RCON_PASSWORD from the env
```

Backups: stop the container or run `save-off` / `save-all` over RCON first, then copy
`data/world`.
