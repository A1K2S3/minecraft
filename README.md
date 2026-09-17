# Minecraft Fabric 1.21.11 — Friends Modpack

Pick one tier. All three ship the same mods and shaders (Iris + Complementary
Unbound); they differ in shader profile, render distance, and RAM.

| Tier | For | Shader profile | RAM |
| --- | --- | --- | --- |
| Dalit | very low end / integrated graphics | POTATO | 3G |
| Pandit | mid range | MEDIUM | 5G |
| Modi | dedicated GPU | HIGH | 8G |

Re-running your one-liner is also the update path.

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
