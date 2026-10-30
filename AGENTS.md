# AGENTS.md

Working notes for this repo. Read this before changing anything.

## What this repo is

A Minecraft **NeoForge 1.21.1** (21.1.265, Java 21) server and its matching client modpack. `mods.json` at the
repo root is the single source of truth for the mod list. Everything else that names a mod
is **generated** from it.

```
mods.json                     hand-edited. The ONLY place a mod is declared.
scripts/generate              mods.json -> the three generated files below
server/
  docker-compose.yml          the server + the lazymc proxy that sleeps/wakes it
  bootstrap                   restore the world from Backblaze B2 if absent, then start
  restart                     save the world, recreate the containers, report
  check-world                 refuses to start unless data/world is Minecraft 1.21.1 or older
  .env                        NOT COMMITTED. RCON_PASSWORD + the four Backblaze B2 values.
  .env.example                template for .env
  mods.generated.env          GENERATED. MODRINTH_PROJECTS=...
client/
  install.sh                  Linux/macOS installer
  install.ps1                 Windows installer
  mods.generated.tsv          GENERATED. filename/sha256/url/dest/tiers/prefix
  purge.generated.txt         GENERATED. server-only filename prefixes
```

## Hard rules

1. **This repo is PUBLIC. Never commit the RCON password**, the Backblaze B2 key, the
   restic password, or any other secret, in any file, at any commit.
   `docker-compose.yml` must only ever contain the `${RCON_PASSWORD}` reference, and the
   B2 values must never be named in the compose file. The real values live in `server/.env`, which is gitignored. Before
   pushing, check: `git log --all -S '<the secret>'` must be empty.
2. **Never hand-edit a `*.generated.*` file.** Edit `mods.json` and re-run
   `scripts/generate`. A hand edit is silently overwritten on the next run and puts the
   server and the clients out of sync.
3. **Never hardcode a mod list anywhere else** — not in the installers, not in the compose
   file, not in a README. If you need a mod fact, derive it from `mods.json` or from a
   generated file.
4. **Never edit `MODRINTH_PROJECTS` on the server VM.** The next `git pull` overwrites it
   and the clients silently drift.
5. The four files `mods.json`, `server/mods.generated.env`, `client/mods.generated.tsv`,
   and `client/purge.generated.txt` are **one commit**. Never commit some without the rest.
6. **`RESTIC_PASSWORD` is not a rotatable password — it is the decryption key for every
   backup.** Changing it orphans the existing Backblaze B2 repository, and losing it
   makes the world permanently unrecoverable even though the bytes are still in the
   bucket. Never generate a new one for an existing repository, and never suggest "just
   rotate it" the way `RCON_PASSWORD` can be rotated.
7. **Never treat "cannot read the B2 repository" as "there is no backup".** A wrong key,
   a wrong restic password and an unreachable B2 all look like an empty repository if you
   only check an exit code — and acting on that starts a fresh world on top of a world
   that still exists. `server/bootstrap` distinguishes the two and refuses to start on
   anything but a genuinely absent repository; keep it that way.

## Adding a mod

### 1. Get the facts from Modrinth

You need the project **slug** — the last path segment of the Modrinth URL
(`modrinth.com/mod/fabric-api` -> `fabric-api`). Confirm it has a build for NeoForge 1.21.1.

If you are pinning a specific build, you need its **version ID** too: open the version's
page and take the ID from the URL (`.../version/6qAuTtLR` -> `6qAuTtLR`), or query
`https://api.modrinth.com/v2/project/<slug>/version`.

### 2. Add an entry to `mods.json`

Append to the `mods` array:

```json
{
  "name": "Lithium",
  "slug": "lithium",
  "side": "both",
  "type": "mod",
  "version": "DDUrRVCA",
  "notes": "",
  "client_version": "DDUrRVCA",
  "client_tiers": null
}
```

| Field            | Meaning                                                                                                                                                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`           | Human-readable title.                                                                                                                                                                                                                                        |
| `slug`           | Modrinth project slug.                                                                                                                                                                                                                                       |
| `side`           | `server`, `client`, or `both`. **This alone decides where the mod lands.** A `server` mod never reaches a client and is actively purged from a friend's `mods/`. A `both` mod must exist on both sides at the same version or clients are rejected at login. |
| `type`           | `mod`, `datapack`, `resourcepack`, or `shaderpack`. Decides the client install directory (`mods/`, `resourcepacks/`, `shaderpacks/`) and whether the server token gets a `datapack:` prefix.                                                                 |
| `version`        | The **server** pin, written exactly as `MODRINTH_PROJECTS` needs it (the Modrinth version _ID_ here, same as `client_version`, so server and clients get the identical jar; a version number also works). `null` lets the server resolve the newest build.                                                                          |
| `prefix`         | _Optional._ Overrides the filename prefix `generate` derives. Only needed when the derived prefix is also a prefix of another mod's jar (Create's `create-` vs `create-aeronautics-bundled-`); set it to a longer prefix of the same filename. |
| `notes`          | Free text. Record anything non-obvious — why a version is pinned, what depends on it.                                                                                                                                                                        |
| `client_version` | _client/both only._ The Modrinth **version ID** the installers pin, so every friend gets byte-identical jars. `null` resolves the newest at generate time.                                                                                                   |
| `client_tiers`   | _client/both only._ `null` for every tier, or a subset like `["pandit", "modi"]`.                                                                                                                                                                            |

Ordering matters for the server entries: `MODRINTH_PROJECTS` is emitted in array order, so
appending is safe but reordering produces a needless diff.

Two fields exist for versions because they hold different things: `version` is the server
pin (a version _number_), `client_version` is the client pin (a version _ID_). They must
describe the same build for a `both` mod.

### Mods not on Modrinth (`url` entries)

A jar that Modrinth does not host (e.g. a GitHub release asset) is declared with `url` + `sha256` **instead of**
`version` / `client_version`:

```json
{
  "name": "Sable",
  "slug": "sable",
  "side": "both",
  "type": "mod",
  "url": "https://github.com/<owner>/<repo>/releases/download/<tag>/<file>.jar",
  "sha256": "<64 lowercase hex>",
  "notes": "",
  "client_tiers": null
}
```

`slug` is then just an identifier. `scripts/generate` downloads the file and refuses to
continue if it does not match `sha256`. GitHub shows each asset's digest on the release
(`gh release view <tag> -R <owner>/<repo> --json assets`). The server gets these through
itzg's `MODS=` (written to `mods.generated.env` next to `MODRINTH_PROJECTS`), which
does **not** resolve dependencies, so every dependency must be its own entry. Only
`type: "mod"` is supported. To upgrade, change `url` and `sha256` together.

`slug` may repeat **only** when every entry sharing it is client-side with non-overlapping
`client_tiers` — one build to one set of tiers, a different build to the rest. (`sodium` used
to be split that way, when only some tiers had shaders.) `scripts/generate` rejects any other duplicate and rejects two builds of one
mod reaching a single tier. An empty `client_tiers` list is **not** a way to park an entry on
no tier: `""` is not a tier name and `generate` fails on it. Delete the entry instead — the
installers sweep a superseded build off a friend's disk by prefix (Tiers, below).

### 3. Regenerate

```sh
./scripts/generate
```

This validates `mods.json`, resolves Modrinth once, and rewrites all three generated files.
It downloads every client file to compute its SHA-256 (Modrinth's API exposes only sha512
and sha1, never sha256, and the installers verify by sha256), so a full run transfers
~145 MB and takes a few minutes. That cost is paid here, once — never on a friend's machine.

If it exits nonzero it printed the reason; fix `mods.json` rather than the generated files.

### 4. Verify before committing

```sh
./scripts/generate --check     # exit 0 = generated files match mods.json
sh -n client/install.sh        # shell syntax
```

For a real end-to-end check, install into a throwaway directory — never `~/.minecraft`:

```sh
sh client/install.sh --dalit --dir /tmp/mctest --manifest client/mods.generated.tsv
```

Expect `Verified jar count: N / N` and exit 0. Re-run it to confirm idempotency (every file
"Already present and verified", zero downloads). Delete the directory afterwards.

### 5. Commit and push

```sh
git add mods.json server/mods.generated.env client/mods.generated.tsv client/purge.generated.txt
git commit -m "Add <mod>"
git push
```

### 6. Deploy to the server

On the VM:

```sh
cd /root/mc-repo && git pull
./server/restart --logs
```

`server/restart` is the deploy step. It flushes the world to disk over RCON before
stopping, so nothing is lost, then recreates the containers so the new
`mods.generated.env` takes effect:

| Flag      | Effect                                                                      |
| --------- | --------------------------------------------------------------------------- |
| _(none)_  | warn players, `save-all flush`, `compose down`, `compose up -d`, print `ps` |
| `--logs`  | the above, then follow the container log                                    |
| `--force` | stop even if the pre-stop save could not be confirmed                       |

It refuses to run without `./server/.env` (an empty `RCON_PASSWORD` would bring the server
up with RCON effectively open) or without `mods.generated.env`. If the container is not
running (asleep, crashed, or a fresh clone) it skips the save rather than failing, so it
is safe to run twice. lazymc puts `mc` back to sleep right after; the new mods load on
the next join.

On a machine that has no world yet, run `./server/bootstrap` instead — see Backups below.

The manual equivalent is `cd server && docker compose up -d`. Removing a mod stops the
container downloading it but does **not** delete the jar already in `data/mods/` — delete
it there and restart.

### 7. Tell friends

They re-run their installer one-liner. Re-running is the update path: it skips any file
already present with the correct hash, removes anything the manifest no longer marks active
for their tier, and purges server-only jars.

A row deleted from `mods.json` is simply gone from the manifest, so the installer no longer
knows its jar and would leave it on a friend's disk. When removing a client/both mod
outright, add its filename prefix (the TSV `prefix` column, e.g. `lithium-fabric-`) to
the top-level `retired_prefixes` list in `mods.json`; `generate` appends it to
`purge.generated.txt`, and refuses a prefix that still matches a shipped jar.

A removed `resourcepack` row is the same problem in `resourcepacks/`, where it also stays
enabled in `options.txt`. Add its **exact** filename (the TSV `filename` column, spaces and
all, e.g. `Clear Glass 1.3.0.zip`) to the top-level `retired_resourcepacks` list;
`generate` writes it to `purge.generated.txt` as `resourcepacks/<filename>` and the
installers delete that one file. Minecraft drops the now-missing pack from `resourcePacks`
on its next launch, so `options.txt` needs no edit.

Connected glass comes from Fusion (`fusion-connected-textures`), which replaced Continuity
(Fabric-only). It needs no installer config.

## Client loader install

The installers run the official NeoForge installer (`java -jar neoforge-21.1.265-installer.jar
--install-client <dir>`), pinned by SHA-256, and need Java 21 for that one step. On the
first NeoForge install into a game directory (no `versions/neoforge-21.1.265/`) they copy
`mods/` and `config/` to `mods-backup-<stamp>` / `config-backup-<stamp>` and then delete every
jar the manifest does not name. `MCF_SKIP_LOADER_INSTALL=1` skips the loader step for dry
runs on a throwaway directory; never set it for real players. TLauncher needs only the
`neoforge-21.1.265` version folder, which the installer creates.

## How the client gets its list

The installers are run as `curl ... | sh`, so there is no checkout on a friend's machine.
They resolve `mods.generated.tsv` and `purge.generated.txt` in this order:

1. `--manifest` / `-Manifest` override (local path or URL) — for testing.
2. A copy sitting next to the script (a cloned checkout).
3. A fetch from `https://raw.githubusercontent.com/A1K2S3/minecraft/main/client/`.

**Consequence: a client change is only live once it is pushed to `main`.** Until then, path
3 returns 404 and the installer aborts loudly rather than installing a partial pack.

The installers depend on nothing but `curl`/`wget` and `sha256sum`/`shasum` — no `jq`, no
`python3`, no Modrinth API calls. Keep it that way; that is the whole reason the tables are
generated and committed rather than resolved at install time.

## Backups

**Automatic backups are currently disabled** — the `itzg/mc-backup` sidecar was removed
from `server/docker-compose.yml`, to be reimplemented later. The world lives only in the
VM's `server/data/`. If a session is about to do something risky to the world (a biome
mod, a version bump, a mass block edit), say so and get a manual copy of `data/world`
first.

The last B2 snapshot is still in the restic repository and `server/bootstrap` still
restores it on a machine with no world, so rules 6 and 7 still apply. `bootstrap`
shells out to `restic/restic:latest`, so the VM needs no restic install; like the client
installers it depends on nothing exotic — no `jq`, no `python3`. Keep it that way.

## World version guard (do not remove)

The live world was created on Fabric 1.21.11 (DataVersion 4671). NeoForge 1.21.1 is
DataVersion 3955 and can corrupt a newer world, so the world must be converted with
[minecraft-1.21.1-backport](https://github.com/KiraKami-dev/minecraft-1.21.1-backport)
(`docs/BACKPORT.md`) first. `server/check-world` reads `data/world/level.dat` and exits
nonzero above 3955 (or when it cannot read it); `restart` and `bootstrap` run it before any
`compose up`. Always start the stack with those two, never a bare `docker compose up`, and
stop the stack before `git pull` during the cutover (`server/README.md`).

## Sleeping when empty

`mc` is not reachable directly: `lazymc` (lazymc-docker-proxy) owns port 25565, starts the
`mc` container on the first join and `docker stop`s it after 10 minutes empty, freeing
its RAM. Detail is in `server/README.md` ("Sleeping when empty"). Do not give `mc` a
restart policy, publish its port, or drop its static address — each one breaks the
sleep/wake cycle. Nothing ticks while asleep (turtles, farms), by design.

## Tiers

`--dalit` / `--pandit` / `--modi` (`-dalit` / `-pandit` / `-modi` on Windows) are required
and mutually exclusive. They set render distances, RAM, and per-mod configs. Whether a tier
gets shaders is **derived from the manifest** (a tier has shaders iff some active row has
`dest` = `shaderpacks`), not hardcoded — do not reintroduce a per-tier shader flag.

All three tiers run shaders: Iris + Sodium + Complementary Unbound, at profile
`POTATO` (dalit) / `MEDIUM` (pandit) / `HIGH` (modi). Iris pins the Sodium it works with,
so there is a single Sodium build in `mods.json`. dalit keeps every other low-end setting it had —
render distance 5, `-Xmx3G`, sound physics off, dynamic lights off, no connected textures.
The no-shaders branches in both installers stay: `HAS_SHADERS` is manifest-derived, so a
future tier that drops the shaderpack row still installs correctly.

Before a friend's mods/ is touched, the installers reconcile it in three passes: remove an
inactive row's exact file, sweep a prefix owned only by inactive rows, then remove any jar
matching an **active** prefix whose filename is not the active one. That third pass is what
takes a superseded build off disk — the pre-Iris Sodium a dalit friend still has, or any mod
whose pin was bumped. Without it the duplicate gate (H.1) aborts the install instead, and a
friend cannot be expected to delete the right jar by hand.

## Changing installer config values

The per-tier config blocks write real files that mods parse: `options.txt`,
`config/sodium-options.json`, `config/soundphysics.properties`,
`config/skinlayers.json`, `config/lambdynlights.toml`, `config/iris.properties`. Each key
and value there was verified against the mod's own compiled classes. Before changing any
value, confirm it is in that setting's actual domain — name the enum's constants or the
serializer's naming policy. Config pre-writing fails open and fails quiet: a bad value is
ignored silently and the feature keeps its default. `lambdynlights.toml`'s `mode` accepts
only `fastest` / `fast` / `fancy` — there is no `off`, which is why `dalit` also zeroes
every `[light_sources]` entry.

## Keeping the two installers in lockstep

`client/install.sh` and `client/install.ps1` are structural mirrors. Any change to one must
be made to the other in the same commit — same behaviour, same log lines, same step
numbering. There is no PowerShell runtime on the Linux dev machine, so `install.ps1` cannot
be executed or parse-checked here; changes to it must be reviewed line-by-line against the
sh version and tested on Windows before being announced to friends.
