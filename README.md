# Minecraft NeoForge 1.21.1 — Friends Modpack

Pick one tier. All three ship the same mods and shaders (Iris + Complementary
Unbound); they differ in shader profile, render distance, and RAM.

| Tier | For | Shader profile | RAM |
| --- | --- | --- | --- |
| Dalit | very low end / integrated graphics | POTATO | 3G |
| Pandit | mid range | MEDIUM | 5G |
| Modi | dedicated GPU | HIGH | 8G |

Re-running your one-liner is also the update path.

## Before you start

- Close Minecraft and the launcher.
- You need **Java 21** once, for the installer to set up NeoForge. The installer finds it
  (including the one the official launcher downloads) or tells you how to get it:
  [Temurin 21](https://adoptium.net/temurin/releases/?version=21), `winget install EclipseAdoptium.Temurin.21.JRE`
  on Windows, `brew install --cask temurin@21` on macOS. On Windows, if no Java 21 is found
  the installer downloads a portable one into `.minecraft\.mcf\java`.
- Coming from the old Fabric pack: the installer first copies your `mods/` and `config/` to
  `mods-backup-<date>` and `config-backup-<date>` in your game folder, then removes every old
  Fabric jar. Your worlds, screenshots and `options.txt` are kept.
- Afterwards, pick the **`neoforge-21.1.265`** profile in the official launcher. In
  TLauncher pick the version `neoforge-21.1.265` (not plain 1.21.1: that starts with no mods).

## Dalit

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/A1K2S3/minecraft/main/client/install.ps1))) -dalit
```

## Pandit

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/A1K2S3/minecraft/main/client/install.ps1))) -pandit
```

## Modi

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/A1K2S3/minecraft/main/client/install.ps1))) -modi
```

## Linux / macOS

```sh
curl -fsSL https://raw.githubusercontent.com/A1K2S3/minecraft/main/client/install.sh | sh -s -- --dalit
```

## Troubleshooting

**The game says `Mod ID: 'minecraft' ... Actual version: '[MISSING]'` for every mod.** NeoForge was not
fully installed (its patched client jar,
`libraries\net\neoforged\neoforge\21.1.265\neoforge-21.1.265-client.jar`, is missing). Re-run the
installer: it now notices this and re-runs the NeoForge step, and stops with the installer log path
(`.minecraft\.mcf\neoforge-21.1.265-installer.jar.log`) if that fails. To do the NeoForge step by
hand, download [neoforge-21.1.265-installer.jar](https://maven.neoforged.net/releases/net/neoforged/neoforge/21.1.265/neoforge-21.1.265-installer.jar),
then on Windows double-click it, or run (TLauncher's Java shown):

```
"%APPDATA%\.minecraft\runtime\java-runtime-delta\windows\java-runtime-delta\bin\java.exe" -jar "%USERPROFILE%\Downloads\neoforge-21.1.265-installer.jar"
```

Choose **Install client**, point it at your `.minecraft` folder, then re-run the one-liner.

## What changed

(A changelog. The mods actually installed are whatever `mods.json` lists.)

The server and the pack moved from Fabric 1.21.11 to **NeoForge 1.21.1**, so the old Fabric
mods cannot be loaded and everyone has to reinstall once. The world was converted with
[minecraft-1.21.1-backport](https://github.com/KiraKami-dev/minecraft-1.21.1-backport).

- **Create Aeronautics and Create Offroad are the official releases.** The official
  Create Aeronautics jar bundles Simulated and Offroad, and Sable 2.0.6 is separate. The
  self-hosted port jars (Create Fly, Sable, Simulated, Aeronautics, Offroad) are gone.
- **New:** GraveStone, Creating Space (rockets, Moon and Mars), Illager Invasion, Creeper
  Overhaul, Vanilla Backport, and Xaero's Minimap and World Map.
- **Exploration and worldgen:** YUNG's Better Dungeons, Mineshafts, Strongholds and Ocean
  Monuments, When Dungeons Arise (and Seven Seas), Moog's Soaring Structures, ChoiceTheorem's
  Overhauled Village, Towns and Towers, Terralith, Biomes O' Plenty.
- **Optimisation:** ModernFix, Chunky, Clumps, Alternate Current, Let Me Despawn, Structure
  Layout Optimizer, zfastnoise, Packet Fixer, Entity Culling, C2ME.
- **Fabric-only mods dropped, with their replacements:**
  Fabric API and Fabric Language Kotlin (NeoForge and Kotlin for Forge),
  Universal Graves and Polymer (GraveStone),
  VoxelMap (Xaero's Minimap),
  Continuity (Fusion connected textures).
  No NeoForge 1.21.1 build exists for Saturated Eating, Expanded Weaponry or Extended Vanilla
  Endgame, so they are gone without a replacement.
- Same mods, new builds: several are a little older than the 1.21.11 versions.
