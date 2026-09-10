# AGENTS.md

Working notes for this repo. Read this before changing anything.

## What this repo is

A Minecraft **Fabric 1.21.11** server and its matching client modpack. `mods.json` at the
repo root is the single source of truth for the mod list. Everything else that names a mod
is **generated** from it.

```
mods.json                     hand-edited. The ONLY place a mod is declared.
scripts/generate              mods.json -> the three generated files below
server/
  docker-compose.yml          the server + the backup sidecar, as they run
  bootstrap                   restore the world from Backblaze B2 if absent, then start
  restart                     save the world, recreate the containers, report
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
   B2 values must reach the backup sidecar through `env_file` alone — never named in the
   compose file. The real values live in `server/.env`, which is gitignored. Before
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
(`modrinth.com/mod/fabric-api` -> `fabric-api`). Confirm it has a build for Fabric 1.21.11.

If you are pinning a specific build, you need its **version ID** too: open the version's
page and take the ID from the URL (`.../version/6qAuTtLR` -> `6qAuTtLR`), or query
`https://api.modrinth.com/v2/project/<slug>/version`.

### 2. Add an entry to `mods.json`

Append to the `mods` array:

```json
{
  "name": "Fabric API",
  "slug": "fabric-api",
  "side": "both",
  "type": "mod",
  "version": null,
  "notes": "",
  "client_version": "6qAuTtLR",
  "client_tiers": null
}
```

| Field | Meaning |
| --- | --- |
| `name` | Human-readable title. |
| `slug` | Modrinth project slug. |
| `side` | `server`, `client`, or `both`. **This alone decides where the mod lands.** A `server` mod never reaches a client and is actively purged from a friend's `mods/`. A `both` mod must exist on both sides at the same version or clients are rejected at login. |
| `type` | `mod`, `datapack`, `resourcepack`, or `shaderpack`. Decides the client install directory (`mods/`, `resourcepacks/`, `shaderpacks/`) and whether the server token gets a `datapack:` prefix. |
| `version` | The **server** pin, written exactly as `MODRINTH_PROJECTS` needs it (usually the version *number*, e.g. `21.11.9+fabric-1.21.11`). `null` lets the server resolve the newest build. |
| `notes` | Free text. Record anything non-obvious — why a version is pinned, what depends on it. |
| `client_version` | *client/both only.* The Modrinth **version ID** the installers pin, so every friend gets byte-identical jars. `null` resolves the newest at generate time. |
| `client_tiers` | *client/both only.* `null` for every tier, or a subset like `["pandit", "modi"]`. |

Ordering matters for the server entries: `MODRINTH_PROJECTS` is emitted in array order, so
appending is safe but reordering produces a needless diff.

Two fields exist for versions because they hold different things: `version` is the server
pin (a version *number*), `client_version` is the client pin (a version *ID*). They must
describe the same build for a `both` mod.

`slug` may repeat **only** when every entry sharing it is client-side with non-overlapping
`client_tiers`. That is how `sodium` ships one build to `dalit` and the build Iris pins to
the shader tiers. `scripts/generate` rejects any other duplicate and rejects two builds of
one mod reaching a single tier.

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

| Flag | Effect |
| --- | --- |
| *(none)* | warn players, `save-all flush`, `compose down`, `compose up -d`, print `ps` |
| `--logs` | the above, then follow the container log |
| `--force` | stop even if the pre-stop save could not be confirmed |

It refuses to run without `./server/.env` (an empty `RCON_PASSWORD` would bring the server
up with RCON effectively open), without `mods.generated.env`, or with any of the four
Backblaze B2 backup values empty in `.env` — pass `--no-backup-check` to override that
last one mid-incident. If the container is not running it skips the save rather than
failing, so it is safe after a crash or on a fresh clone, and safe to run twice.

On a machine that has no world yet, run `./server/bootstrap` instead — see Backups below.

The manual equivalent is `cd server && docker compose up -d`. Removing a mod stops the
container downloading it but does **not** delete the jar already in `data/mods/` — delete
it there and restart.

### 7. Tell friends

They re-run their installer one-liner. Re-running is the update path: it skips any file
already present with the correct hash, removes anything the manifest no longer marks active
for their tier, and purges server-only jars.

## How the client gets its list

The installers are run as `curl ... | sh`, so there is no checkout on a friend's machine.
They resolve `mods.generated.tsv` and `purge.generated.txt` in this order:

1. `--manifest` / `-Manifest` override (local path or URL) — for testing.
2. A copy sitting next to the script (a cloned checkout).
3. A fetch from `https://raw.githubusercontent.com/Adarsh077/minecraft/main/client/`.

**Consequence: a client change is only live once it is pushed to `main`.** Until then, path
3 returns 404 and the installer aborts loudly rather than installing a partial pack.

The installers depend on nothing but `curl`/`wget` and `sha256sum`/`shasum` — no `jq`, no
`python3`, no Modrinth API calls. Keep it that way; that is the whole reason the tables are
generated and committed rather than resolved at install time.

## Backups

`server/docker-compose.yml` runs an `itzg/mc-backup` sidecar that pushes the world to
**Backblaze B2** via restic at **00:00 UTC daily**, keeping **one snapshot**
(`--keep-last 1`). Credentials come from `server/.env` only. Full detail — retention
trade-offs, how to check a run, how to restore — is in `server/README.md` ("Backups");
do not duplicate it here.

Two consequences worth carrying in your head:

- **The repo plus four values in `.env` is the entire recovery kit.** `server/bootstrap`
  restores the world from B2 when a machine has none, so nothing on the VM outside
  `.env` is load-bearing. Anything you add to the server that lives *only* on the VM
  breaks that property — put it in the repo instead.
- **One snapshot means no history.** Damage not noticed within 24 hours is permanent.
  If a session is about to do something risky to the world (a biome mod, a version bump,
  a mass block edit), take a snapshot first with
  `docker compose exec backup backup now` — or widen `PRUNE_RESTIC_RETENTION` before
  starting, not after.

`bootstrap` shells out to `restic/restic:latest` for the snapshot query and the restore,
so the VM needs no restic install. Like the client installers it depends on nothing
exotic — no `jq`, no `python3`. Keep it that way.

## Tiers

`--dalit` / `--pandit` / `--modi` (`-dalit` / `-pandit` / `-modi` on Windows) are required
and mutually exclusive. They set render distances, RAM, and per-mod configs. Whether a tier
gets shaders is **derived from the manifest** (a tier has shaders iff some active row has
`dest` = `shaderpacks`), not hardcoded — do not reintroduce a per-tier shader flag.

## Changing installer config values

The per-tier config blocks write real files that mods parse: `options.txt`,
`config/sodium-options.json`, `config/soundphysics.properties`, `config/continuity.json`,
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
