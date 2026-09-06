<#
Fabric Friends Client Pack installer for Minecraft 1.21.11 / Fabric loader 0.19.3
PowerShell 5.1 compatible. No Java required at any point.

A tier is REQUIRED: -dalit (bare minimum), -pandit (medium), or -modi (high).
Every file is downloaded from the Modrinth CDN and verified by SHA-256.
#>

param(
    [string]$Dir = "",
    [string]$Manifest = "",
    [switch]$dalit,
    [switch]$pandit,
    [switch]$modi
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FabricMcVersion = "1.21.11"
$FabricLoaderVersion = "0.19.3"
$FabricLoaderId = "fabric-loader-$FabricLoaderVersion-$FabricMcVersion"
$VersionManifestUrl = "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
$FabricProfileUrl = "https://meta.fabricmc.net/v2/versions/loader/$FabricMcVersion/$FabricLoaderVersion/profile/json"

# --- modflared forced-tunnels config (written into the game dir during install) ---
$ForcedTunnelsJson = '["minecraft.dekhlo.to"]'

# --- manifest resolution ---
# mods.generated.tsv (the mod/resourcepack/shaderpack table) and purge.generated.txt
# (server-only filename prefixes) are the single source of truth, generated from
# mods.json by scripts/generate. This installer resolves each file at runtime (see
# Resolve-Asset below): a -Manifest override first, else a copy sitting next to the
# script, else a fetch from the raw GitHub URL. The mods table, shader stack,
# resourcepack, server-only prefixes, and duplicate-detection prefixes are all derived
# from these files, not hardcoded here.
$RawBaseUrl = "https://raw.githubusercontent.com/Adarsh077/minecraft/main/client"

function Write-Log($msg) {
    Write-Host $msg
}

function Write-Warn2($msg) {
    Write-Warning $msg
}

function Fail($msg) {
    Write-Error $msg
    exit 1
}

function Show-Usage {
    Write-Host "Usage: install.ps1 (-dalit | -pandit | -modi) [-Dir DIR] [-Manifest PATH-OR-URL]"
    Write-Host "  A tier is REQUIRED:"
    Write-Host "    -dalit   very low end: no shaders, minimal settings, -Xmx3G"
    Write-Host "    -pandit  medium: Complementary shaders (MEDIUM), -Xmx5G"
    Write-Host "    -modi    dedicated GPU: Complementary shaders (HIGH), -Xmx8G"
    Write-Host "    -Manifest PATH-OR-URL  override the generated mods.generated.tsv source (testing/local)"
}

function Get-Sha256($path) {
    return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
}

function Get-Sha1($path) {
    return (Get-FileHash -Algorithm SHA1 -Path $path).Hash.ToLowerInvariant()
}

function Invoke-Download($Url, $Dest) {
    try {
        # Invoke-WebRequest follows 3xx redirects by default (Modrinth serves direct URLs).
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    } catch {
        Fail "Download failed: $Url ($($_.Exception.Message))"
    }
}

# Download a file and verify its SHA-256 (idempotent: skips if already correct).
function Invoke-DownloadVerify($Name, $Sha, $Url, $DestDir) {
    if (-not (Test-Path -LiteralPath $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }
    $dest = Join-Path $DestDir $Name
    if ((Test-Path -LiteralPath $dest) -and ((Get-Sha256 -path $dest) -eq $Sha)) {
        Write-Log "Already present and verified: $Name"
        return
    }
    Write-Log "Downloading: $Name"
    $part = "$dest.part"
    Invoke-Download -Url $Url -Dest $part
    $actual = Get-Sha256 -path $part
    if ($actual -ne $Sha) {
        Remove-Item -Force -LiteralPath $part
        Fail "SHA-256 mismatch for $Name : expected $Sha, got $actual (url: $Url)"
    }
    Move-Item -Force -LiteralPath $part -Destination $dest
}

# Resolve one generated asset to a local path. $Override (may be empty; only the
# manifest passes one) is honoured first and can be a local path or an http(s) URL.
# Else a copy next to the script ($PSScriptRoot, empty when the script is piped to
# iex) is used when present. Else it is fetched from $RawBaseUrl into the temp dir.
function Resolve-Asset($Name, $Override, $TempDir) {
    if (-not [string]::IsNullOrEmpty($Override)) {
        if ($Override -match '^https?://') {
            $dest = Join-Path $TempDir $Name
            Invoke-Download -Url $Override -Dest $dest
            return $dest
        }
        if (-not (Test-Path -LiteralPath $Override)) { Fail "Manifest not found: $Override" }
        return $Override
    }
    if ((-not [string]::IsNullOrEmpty($PSScriptRoot)) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $Name))) {
        return (Join-Path $PSScriptRoot $Name)
    }
    $dest = Join-Path $TempDir $Name
    Invoke-Download -Url "$RawBaseUrl/$Name" -Dest $dest
    return $dest
}

# --- config-writing helpers ---
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-ConfigAction($path) {
    if (Test-Path -LiteralPath $path) { return "merged" } else { return "created" }
}

# Merge "key<sep>value" entries into a colon- or equals-separated text config.
# Existing lines for a key are replaced in place; every other line is preserved;
# absent keys are appended. Used for options.txt (":") and .properties ("=").
function Merge-KvFile($path, $sep, $pairs) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines = @()
    if (Test-Path -LiteralPath $path) { $lines = @(Get-Content -LiteralPath $path) }
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $replaced = $false
        foreach ($k in $pairs.Keys) {
            # Tolerate optional whitespace before the separator (a mod may re-save "key = value").
            if ($line -match ("^" + [regex]::Escape($k) + "[ \t]*" + [regex]::Escape($sep))) {
                if (-not $seen.ContainsKey($k)) { $out.Add("$k$sep$($pairs[$k])"); $seen[$k] = $true }
                $replaced = $true
                break
            }
        }
        if (-not $replaced) { $out.Add($line) }
    }
    foreach ($k in $pairs.Keys) { if (-not $seen.ContainsKey($k)) { $out.Add("$k$sep$($pairs[$k])") } }
    [System.IO.File]::WriteAllText($path, ($out -join "`n") + "`n", $Utf8NoBom)
}

# Recursively convert a PSCustomObject (from ConvertFrom-Json) into nested hashtables.
function ConvertTo-HashtableDeep($obj) {
    if ($null -eq $obj) { return @{} }
    $ht = @{}
    foreach ($p in $obj.PSObject.Properties) {
        if ($p.Value -is [System.Management.Automation.PSCustomObject]) {
            $ht[$p.Name] = ConvertTo-HashtableDeep $p.Value
        } else {
            $ht[$p.Name] = $p.Value
        }
    }
    return $ht
}

function Merge-HashtableDeep($base, $patch) {
    foreach ($k in @($patch.Keys)) {
        if (($patch[$k] -is [hashtable]) -and $base.ContainsKey($k) -and ($base[$k] -is [hashtable])) {
            Merge-HashtableDeep $base[$k] $patch[$k]
        } else {
            $base[$k] = $patch[$k]
        }
    }
}

# Deep-merge a hashtable patch into a JSON file (create if absent). Booleans and
# ints in the patch serialize as JSON true/false/numbers.
function Merge-JsonFile($path, $patch) {
    $base = @{}
    if (Test-Path -LiteralPath $path) {
        try {
            $existing = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            $base = ConvertTo-HashtableDeep $existing
        } catch {
            $base = @{}
        }
    }
    Merge-HashtableDeep $base $patch
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, (($base | ConvertTo-Json -Depth 10) + "`n"), $Utf8NoBom)
}

# Set a quoted-string key in a TOML file (create if absent), replacing any existing
# line for the key (TOML forbids duplicate keys, so this cannot just append).
function Set-TomlString($path, $key, $val) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $line = "$key = `"$val`""
    $out = New-Object System.Collections.Generic.List[string]
    $seen = $false
    if (Test-Path -LiteralPath $path) {
        foreach ($l in @(Get-Content -LiteralPath $path)) {
            if ($l -match ("^[ \t]*" + [regex]::Escape($key) + "[ \t]*=")) {
                if (-not $seen) { $out.Add($line); $seen = $true }
            } else {
                $out.Add($l)
            }
        }
    }
    if (-not $seen) { $out.Add($line) }
    [System.IO.File]::WriteAllText($path, ($out -join "`n") + "`n", $Utf8NoBom)
}

# Write LambDynamicLights' [light_sources] table with every source off (dalit only).
# LambDynamicLights (NightConfig) reads each source via the path "light_sources.<name>"
# and serialises them as a nested [light_sources] TOML table, so we write that exact
# shape. entities / self / beam / firefly / guardian_laser / sonic_boom /
# glowing_effect are booleans and go to false. creeper and tnt are NOT booleans --
# they are ExplosiveLightingMode, which in 4.9.1 declares only SIMPLE and FANCY
# (verified in ExplosiveLightingMode.class). There is no OFF, so explosion lighting
# cannot be switched off here at all; "simple" is the cheaper of the two and is the
# floor. A bare false, or the string "off", is an invalid enum value that
# byId()/valueOf() silently falls back to the default for, leaving it ON.
# water_sensitive_check is a submersion behaviour flag, not a light source, so it is
# left untouched. Replaces an existing [light_sources] table if present (idempotent),
# otherwise appends one.
function Set-LambdynLightsOff($path) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path -LiteralPath $path)) { [System.IO.File]::WriteAllText($path, "", $Utf8NoBom) }
    $out = New-Object System.Collections.Generic.List[string]
    $inLs = $false
    foreach ($l in @(Get-Content -LiteralPath $path)) {
        if ($l -match '^[ \t]*\[light_sources\][ \t]*$') { $inLs = $true; continue }
        if ($inLs -and ($l -match '^[ \t]*\[')) { $inLs = $false }
        if ($inLs) { continue }
        if ($l -match '^[ \t]*light_sources\.') { continue }
        $out.Add($l)
    }
    $out.Add("[light_sources]")
    $out.Add("`tentities = false")
    $out.Add("`tself = false")
    $out.Add("`tcreeper = `"simple`"")
    $out.Add("`ttnt = `"simple`"")
    $out.Add("`tbeam = false")
    $out.Add("`tfirefly = false")
    $out.Add("`tguardian_laser = false")
    $out.Add("`tsonic_boom = false")
    $out.Add("`tglowing_effect = false")
    [System.IO.File]::WriteAllText($path, ($out -join "`n") + "`n", $Utf8NoBom)
}

# Ensure a pack id is present in options.txt's resourcePacks list (a JSON array),
# preserving any packs the friend already enabled. Minecraft 1.21.11 references a
# resourcepacks\ file as "file/<filename>" (the "file/" prefix is confirmed present
# in the vanilla client's resource-pack class).
function Enable-Resourcepack($path, $id) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path -LiteralPath $path)) { [System.IO.File]::WriteAllText($path, "", $Utf8NoBom) }
    $lines = @(Get-Content -LiteralPath $path)
    $line = $lines | Where-Object { $_ -like "resourcePacks:*" } | Select-Object -First 1
    if ($null -eq $line) {
        Add-Content -LiteralPath $path -Value "resourcePacks:[`"vanilla`",`"$id`"]"
        return
    }
    if ($line.Contains("`"$id`"")) { return }
    $array = $line.Substring("resourcePacks:".Length)
    if ($array -eq "[]") {
        $new = "resourcePacks:[`"$id`"]"
    } else {
        $new = "resourcePacks:" + $array.Substring(0, $array.Length - 1) + ",`"$id`"]"
    }
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($l in $lines) {
        if ((-not $done) -and ($l -like "resourcePacks:*")) { $out.Add($new); $done = $true }
        else { $out.Add($l) }
    }
    [System.IO.File]::WriteAllText($path, ($out -join "`n") + "`n", $Utf8NoBom)
}

# --- tier selection (mutually exclusive, REQUIRED) ---
$Tier = ""
$TierCount = 0
if ($dalit)  { $Tier = "dalit";  $TierCount++ }
if ($pandit) { $Tier = "pandit"; $TierCount++ }
if ($modi)   { $Tier = "modi";   $TierCount++ }
if ($TierCount -gt 1) {
    Show-Usage
    Fail "Only one tier flag may be given (-dalit / -pandit / -modi)"
}
if ($Tier -eq "") {
    Show-Usage
    Fail "No tier given. Choose exactly one of -dalit / -pandit / -modi."
}

# --- per-tier settings ---
# All tiers install every mod jar and the resourcepack the manifest marks active for
# them; tiers differ in the shader stack and written config. options.txt / .properties
# booleans are strings; JSON booleans are [bool]. Whether a tier gets Iris + the Sodium
# 0.8.7 swap is derived from the manifest below ($HasShaders), not set here.
if ($Tier -eq "dalit") {
    $T_RenderDistance = 5;  $T_SimDistance = 5;  $T_Graphics = 0; $T_Particles = 2
    $T_Mipmap = 0;          $T_BiomeBlend = 0;   $T_MaxFps = 60
    $T_EntityShadows = "false"; $T_Ao = "false"; $T_EntityDistScale = "0.5"
    $T_Xmx = "3G"
    $T_CompProfile = ""
    $T_SoundPhysics = "false"
    $T_Lambdyn = "fastest"
    $T_Continuity = $false
    $T_Skinlayers = $false
    $T_SodiumAnimateVisibleOnly = $true
    $T_SodiumRenderAhead = 0
} elseif ($Tier -eq "pandit") {
    $T_RenderDistance = 9;  $T_SimDistance = 8;  $T_Graphics = 1; $T_Particles = 1
    $T_Mipmap = 2;          $T_BiomeBlend = 2;   $T_MaxFps = 120
    $T_EntityShadows = "true"; $T_Ao = "true";   $T_EntityDistScale = "1.0"
    $T_Xmx = "5G"
    $T_CompProfile = "MEDIUM"
    $T_SoundPhysics = "true"
    $T_Lambdyn = "fancy"
    $T_Continuity = $true
    $T_Skinlayers = $true
    $T_SodiumAnimateVisibleOnly = $true
    $T_SodiumRenderAhead = 2
} elseif ($Tier -eq "modi") {
    $T_RenderDistance = 16; $T_SimDistance = 12; $T_Graphics = 2; $T_Particles = 0
    $T_Mipmap = 4;          $T_BiomeBlend = 5;   $T_MaxFps = 240
    $T_EntityShadows = "true"; $T_Ao = "true";   $T_EntityDistScale = "1.0"
    $T_Xmx = "8G"
    $T_CompProfile = "HIGH"
    $T_SoundPhysics = "true"
    $T_Lambdyn = "fancy"
    $T_Continuity = $true
    $T_Skinlayers = $true
    $T_SodiumAnimateVisibleOnly = $false
    $T_SodiumRenderAhead = 3
}

# --- OS default game directory ---
if ([string]::IsNullOrEmpty($Dir)) {
    $Dir = Join-Path $env:APPDATA ".minecraft"
}
$TargetDir = $Dir

if (-not (Test-Path -Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Write-Warn2 "Game directory did not exist and was created at: $TargetDir"
    Write-Warn2 "Please launch vanilla $FabricMcVersion once from your launcher first so assets download, then re-run this installer."
}

Write-Log "[0/8] Using game directory: $TargetDir"

$ModsDir = Join-Path $TargetDir "mods"
if (-not (Test-Path -Path $ModsDir)) {
    New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null
}

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fabric-friends-installer-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# --- resolve + parse the generated manifest (single source of truth) ---
$ManifestFile = Resolve-Asset "mods.generated.tsv" $Manifest $TempDir
if (-not (Test-Path -LiteralPath $ManifestFile)) { Fail "Could not obtain the mod manifest (mods.generated.tsv)." }
$PurgeFile = Resolve-Asset "purge.generated.txt" "" $TempDir
if (-not (Test-Path -LiteralPath $PurgeFile)) { Fail "Could not obtain the server-only purge list (purge.generated.txt)." }

# Parse the TSV (filename<TAB>sha256<TAB>url<TAB>dest<TAB>tiers<TAB>prefix), skipping
# blank and #-comment lines. A row is ACTIVE for this tier when tiers is "*" or the
# tier appears in the comma-separated list. Filenames may contain spaces, so every
# split here is on TAB only.
$ActiveRows = @()          # active rows: @{File;Sha;Url;Dest;Prefix}
$InactiveMods = @()        # inactive dest=mods rows: @{File;Prefix}
$AllModsFiles = @()        # every dest=mods filename (ALL tiers)
$AllModsPrefixes = @()     # every distinct dest=mods prefix (ALL tiers)
foreach ($rawLine in ([System.IO.File]::ReadAllLines($ManifestFile))) {
    if ($rawLine -match '^\s*#') { continue }
    $parts = $rawLine -split "`t"
    if ($parts.Count -lt 6) { continue }
    $file = $parts[0]; $sha = $parts[1]; $url = $parts[2]; $dest = $parts[3]; $tiers = $parts[4]; $prefix = $parts[5]
    $active = ($tiers -eq "*")
    if (-not $active) {
        foreach ($t in ($tiers -split ",")) { if ($t -eq $Tier) { $active = $true } }
    }
    if ($dest -eq "mods") {
        $AllModsFiles += $file
        if ($AllModsPrefixes -notcontains $prefix) { $AllModsPrefixes += $prefix }
    }
    if ($active) {
        $ActiveRows += ,@{ File = $file; Sha = $sha; Url = $url; Dest = $dest; Prefix = $prefix }
    } elseif ($dest -eq "mods") {
        $InactiveMods += ,@{ File = $file; Prefix = $prefix }
    }
}

if ($ActiveRows.Count -eq 0) { Fail "Manifest produced no active rows for tier '$Tier' (source: $ManifestFile)." }
$ExpectedJarCount = @($ActiveRows | Where-Object { $_.Dest -eq "mods" }).Count
if ($ExpectedJarCount -eq 0) { Fail "Manifest produced zero active mod jars for tier '$Tier' (source: $ManifestFile)." }
$HasShaders = (@($ActiveRows | Where-Object { $_.Dest -eq "shaderpacks" }).Count -gt 0)
$ShaderpackZip = @($ActiveRows | Where-Object { $_.Dest -eq "shaderpacks" } | ForEach-Object { $_.File }) | Select-Object -First 1
$ActiveResourcepacks = @($ActiveRows | Where-Object { $_.Dest -eq "resourcepacks" } | ForEach-Object { $_.File })
$ActiveModsFiles = @($ActiveRows | Where-Object { $_.Dest -eq "mods" } | ForEach-Object { $_.File })

# --- reconcile the mods\ directory with this tier BEFORE anything downloads or the
# duplicate check runs, so switching tiers never leaves an inactive or stale jar
# behind. "side" in mods.json decides server-only removal (step [4/8]); the per-mod
# tier list decides this. (shaderpacks\ is left untouched -- the zips are harmless.)
# 1. Every INACTIVE dest=mods row whose exact file is present is removed.
foreach ($row in $InactiveMods) {
    $p = Join-Path $ModsDir $row.File
    if (Test-Path -LiteralPath $p) {
        Write-Log "Tier '$Tier': removing inactive mod: $($row.File)"
        Remove-Item -Force -LiteralPath $p
    }
}
# 2. Any prefix owned by an INACTIVE row but NOT by any ACTIVE row (e.g. iris-fabric-
# when this tier has no shaders) has every matching jar removed -- this also clears an
# Iris/Sodium left behind at a DIFFERENT version than the one currently pinned.
$ActiveModsPrefixes = @($ActiveRows | Where-Object { $_.Dest -eq "mods" } | ForEach-Object { $_.Prefix })
foreach ($ip in (@($InactiveMods | ForEach-Object { $_.Prefix }) | Select-Object -Unique)) {
    if ($ActiveModsPrefixes -notcontains $ip) {
        Get-ChildItem -Path $ModsDir -Filter "$ip*.jar" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "Tier '$Tier': removing stale mod for prefix '$ip': $($_.Name)"
            Remove-Item -Force $_.FullName
        }
    }
}

try {

    # --- A/B: vanilla base version ---
    $VersionDir = Join-Path $TargetDir "versions\$FabricMcVersion"
    $VersionJson = Join-Path $VersionDir "$FabricMcVersion.json"
    $VersionJar = Join-Path $VersionDir "$FabricMcVersion.jar"

    if ((Test-Path $VersionJson) -and (Test-Path $VersionJar)) {
        Write-Log "[1/8] Vanilla $FabricMcVersion base version already present, skipping."
    } else {
        Write-Log "[1/8] Installing vanilla $FabricMcVersion base version..."
        New-Item -ItemType Directory -Force -Path $VersionDir | Out-Null

        $ManifestPath = Join-Path $TempDir "version_manifest_v2.json"
        Invoke-Download -Url $VersionManifestUrl -Dest $ManifestPath

        $ManifestData = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
        $VersionEntry = $ManifestData.versions | Where-Object { $_.id -eq $FabricMcVersion } | Select-Object -First 1
        if ($null -eq $VersionEntry) {
            Fail "Could not find version $FabricMcVersion in $VersionManifestUrl"
        }

        Invoke-Download -Url $VersionEntry.url -Dest $VersionJson

        $VersionData = Get-Content -Raw -Path $VersionJson | ConvertFrom-Json
        $ClientUrl = $VersionData.downloads.client.url
        $ClientSha1 = $VersionData.downloads.client.sha1

        if ([string]::IsNullOrEmpty($ClientUrl)) {
            Fail "Could not read downloads.client.url from $VersionJson"
        }
        if ([string]::IsNullOrEmpty($ClientSha1)) {
            Fail "Could not read downloads.client.sha1 from $VersionJson"
        }

        Invoke-Download -Url $ClientUrl -Dest $VersionJar

        $ActualSha1 = Get-Sha1 -path $VersionJar
        if ($ActualSha1 -ne $ClientSha1) {
            Remove-Item -Force $VersionJar
            Fail "SHA-1 mismatch for $VersionJar : expected $ClientSha1, got $ActualSha1"
        }
        Write-Log "Vanilla $FabricMcVersion client jar verified."
    }

    # --- C: fabric loader profile ---
    Write-Log "[2/8] Installing Fabric loader profile ($FabricLoaderId)..."
    $ProfileJsonPath = Join-Path $TempDir "fabric_profile.json"
    Invoke-Download -Url $FabricProfileUrl -Dest $ProfileJsonPath

    $ProfileRaw = Get-Content -Raw -Path $ProfileJsonPath
    if ($ProfileRaw -notmatch '"inheritsFrom"') {
        Fail "Fabric profile response missing `"inheritsFrom`": $FabricProfileUrl"
    }
    if ($ProfileRaw -notmatch [regex]::Escape("net.fabricmc.loader.impl.launch.knot.KnotClient")) {
        Fail "Fabric profile response missing KnotClient main class: $FabricProfileUrl"
    }

    $ProfileData = $ProfileRaw | ConvertFrom-Json
    $ProfileId = $ProfileData.id
    if ([string]::IsNullOrEmpty($ProfileId)) {
        Fail "Could not read id from Fabric profile response"
    }
    if ($ProfileId -ne $FabricLoaderId) {
        Write-Warn2 "Fabric profile id ($ProfileId) differs from expected ($FabricLoaderId); continuing with actual id."
    }

    $FabricVersionDir = Join-Path $TargetDir "versions\$ProfileId"
    New-Item -ItemType Directory -Force -Path $FabricVersionDir | Out-Null
    Copy-Item -Force -Path $ProfileJsonPath -Destination (Join-Path $FabricVersionDir "$ProfileId.json")
    Write-Log "Fabric loader profile written to versions\$ProfileId\$ProfileId.json"

    # --- D: launcher_profiles.json ---
    Write-Log "[3/8] Registering launcher profile..."
    $LauncherProfilesPath = Join-Path $TargetDir "launcher_profiles.json"

    # The tier's RAM allocation goes in the profile's javaArgs field (the launcher
    # otherwise applies its own default JVM args).
    $JavaArgs = "-Xmx$T_Xmx -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"

    try {
        if (Test-Path $LauncherProfilesPath) {
            $LauncherData = Get-Content -Raw -Path $LauncherProfilesPath | ConvertFrom-Json
        } else {
            $LauncherData = '{"profiles":{},"settings":{},"version":3}' | ConvertFrom-Json
        }

        if ($null -eq $LauncherData.profiles) {
            $LauncherData | Add-Member -MemberType NoteProperty -Name "profiles" -Value (New-Object PSObject) -Force
        }

        # Preserve any other fields on our profile object; only our known keys are authoritative.
        if ($LauncherData.profiles.PSObject.Properties.Name -contains "fabric-loader-1.21.11") {
            $NewProfile = $LauncherData.profiles."fabric-loader-1.21.11"
        } else {
            $NewProfile = New-Object PSObject
        }
        if (-not ($NewProfile.PSObject.Properties.Name -contains "created")) {
            $NewProfile | Add-Member -MemberType NoteProperty -Name "created" -Value "2026-08-11T00:00:00.000Z" -Force
        }
        $NewProfile | Add-Member -MemberType NoteProperty -Name "name" -Value "fabric-loader-1.21.11" -Force
        $NewProfile | Add-Member -MemberType NoteProperty -Name "type" -Value "custom" -Force
        $NewProfile | Add-Member -MemberType NoteProperty -Name "lastVersionId" -Value $ProfileId -Force
        $NewProfile | Add-Member -MemberType NoteProperty -Name "icon" -Value "TNT" -Force
        $NewProfile | Add-Member -MemberType NoteProperty -Name "javaArgs" -Value $JavaArgs -Force

        if ($LauncherData.profiles.PSObject.Properties.Name -contains "fabric-loader-1.21.11") {
            $LauncherData.profiles."fabric-loader-1.21.11" = $NewProfile
        } else {
            $LauncherData.profiles | Add-Member -MemberType NoteProperty -Name "fabric-loader-1.21.11" -Value $NewProfile -Force
        }

        ($LauncherData | ConvertTo-Json -Depth 10) | Set-Content -Path $LauncherProfilesPath -Encoding UTF8
        Write-Log "launcher_profiles.json updated (tier '$Tier': javaArgs -Xmx$T_Xmx)."
    } catch {
        Write-Warn2 "Failed to update launcher_profiles.json ($($_.Exception.Message)); skipping. Select the $ProfileId version manually in TLauncher."
    }

    # --- E: remove server-only jars ---
    # The prefixes come from purge.generated.txt: mods.json's "side" == server field is
    # what decides a mod is server-only, so a friend's client mods\ never keeps them.
    Write-Log "[4/8] Removing server-only jars from mods\ (if present)..."
    foreach ($prefix in ([System.IO.File]::ReadAllLines($PurgeFile))) {
        if ($prefix -match '^\s*#' -or $prefix.Trim() -eq "") { continue }
        $found = Get-ChildItem -Path $ModsDir -Filter "$prefix*" -File -ErrorAction SilentlyContinue
        foreach ($m in $found) {
            Write-Log "Removing server-only jar: $($m.Name)"
            Remove-Item -Force $m.FullName
        }
    }

    # --- F: download + verify every active file for this tier from the Modrinth CDN ---
    Write-Log "[5/8] Downloading and verifying mods, resourcepack, and shaders (this transfers ~145 MB on a fresh install)..."
    $ResourcepacksDir = Join-Path $TargetDir "resourcepacks"
    $ShaderpacksDir = Join-Path $TargetDir "shaderpacks"

    # 5a: every active mod jar -> mods\
    foreach ($row in $ActiveRows) {
        if ($row.Dest -ne "mods") { continue }
        Invoke-DownloadVerify $row.File $row.Sha $row.Url $ModsDir
    }

    # 5b: every active non-mod file -> its dest dir (resourcepacks\ or shaderpacks\).
    # Filenames may contain spaces; Invoke-DownloadVerify quotes them.
    foreach ($row in $ActiveRows) {
        if ($row.Dest -eq "resourcepacks") { Invoke-DownloadVerify $row.File $row.Sha $row.Url $ResourcepacksDir }
        elseif ($row.Dest -eq "shaderpacks") { Invoke-DownloadVerify $row.File $row.Sha $row.Url $ShaderpacksDir }
    }

    if ($HasShaders) {
        Write-Log "Shaders installed for '$Tier': Iris, Sodium 0.8.7, Complementary Unbound (shaderpacks\$ShaderpackZip)."
    }

    # --- G: modflared forced-tunnels config (written to both locations modflared reads) ---
    Write-Log "[6/8] Writing modflared forced_tunnels.json..."
    foreach ($d in @((Join-Path $TargetDir "config\modflared"), (Join-Path $TargetDir "modflared"))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $ForcedTunnelsPath = Join-Path $d "forced_tunnels.json"
        [System.IO.File]::WriteAllText($ForcedTunnelsPath, $ForcedTunnelsJson + "`n", $Utf8NoBom)
        Write-Log "Wrote $ForcedTunnelsPath"
    }

    # --- G.7: tier config ---
    # A tier is always set by this point. Every config path below was verified against
    # the mod jar; mods whose path could not be verified are deliberately left unset.
    Write-Log "[7/8] Writing '$Tier' tier config..."

    # options.txt -- vanilla, colon-separated. Merge: replace only the tier keys,
    # keep every other line, append any that are absent.
    $OptionsTxt = Join-Path $TargetDir "options.txt"
    $optAction = Get-ConfigAction $OptionsTxt
    $optPairs = [ordered]@{
        "renderDistance"        = $T_RenderDistance
        "simulationDistance"    = $T_SimDistance
        "graphicsMode"          = $T_Graphics
        "particles"             = $T_Particles
        "mipmapLevels"          = $T_Mipmap
        "biomeBlendRadius"      = $T_BiomeBlend
        "maxFps"                = $T_MaxFps
        "entityShadows"         = $T_EntityShadows
        "ao"                    = $T_Ao
        "entityDistanceScaling" = $T_EntityDistScale
    }
    Merge-KvFile $OptionsTxt ":" $optPairs
    Write-Log "options.txt ($Tier, $optAction): renderDistance=$T_RenderDistance simulationDistance=$T_SimDistance graphicsMode=$T_Graphics particles=$T_Particles mipmapLevels=$T_Mipmap biomeBlendRadius=$T_BiomeBlend maxFps=$T_MaxFps entityShadows=$T_EntityShadows ao=$T_Ao entityDistanceScaling=$T_EntityDistScale"

    # Enable each active resourcepack (normally exactly one) -- copying it does not
    # switch it on. Merged into resourcePacks so a friend's enabled packs are kept.
    # If the tier has no resourcepack row, this simply enables nothing.
    foreach ($rpName in $ActiveResourcepacks) {
        Enable-Resourcepack $OptionsTxt "file/$rpName"
        Write-Log "options.txt ($Tier): resourcePacks += `"file/$rpName`""
    }

    # Sodium -- config\sodium-options.json. GSON field naming is
    # LOWER_CASE_WITH_UNDERSCORES, so the JSON keys are snake_case (NOT the Java
    # field names). Only confirmed primitive fields; no enum-valued fields.
    $SodiumJson = Join-Path $TargetDir "config\sodium-options.json"
    $sodAction = Get-ConfigAction $SodiumJson
    Merge-JsonFile $SodiumJson @{
        performance = @{
            chunk_builder_threads         = 0
            use_entity_culling            = $true
            use_fog_occlusion             = $true
            use_block_face_culling        = $true
            animate_only_visible_textures = $T_SodiumAnimateVisibleOnly
        }
        advanced = @{ cpu_render_ahead_limit = $T_SodiumRenderAhead }
        quality  = @{ hidden_fluid_culling = $true }
    }
    Write-Log "config\sodium-options.json ($Tier, $sodAction): animate_only_visible_textures=$T_SodiumAnimateVisibleOnly cpu_render_ahead_limit=$T_SodiumRenderAhead + culling on"

    # Sound Physics Remastered -- config\soundphysics.properties, key "enabled".
    $SoundPhysicsProps = Join-Path $TargetDir "config\soundphysics.properties"
    $spAction = Get-ConfigAction $SoundPhysicsProps
    Merge-KvFile $SoundPhysicsProps "=" ([ordered]@{ "enabled" = $T_SoundPhysics })
    Write-Log "config\soundphysics.properties ($Tier, $spAction): enabled=$T_SoundPhysics"

    # Continuity -- config\continuity.json. "off" disables connected + emissive textures.
    $ContinuityJson = Join-Path $TargetDir "config\continuity.json"
    $contAction = Get-ConfigAction $ContinuityJson
    Merge-JsonFile $ContinuityJson @{ connected_textures = $T_Continuity; emissive_textures = $T_Continuity }
    Write-Log "config\continuity.json ($Tier, $contAction): connected_textures=$T_Continuity emissive_textures=$T_Continuity"

    # 3D Skin Layers -- config\skinlayers.json. No single master toggle; the 3D layers
    # are the per-body-part flags, so "off" clears them all, "on" sets them.
    $SkinlayersJson = Join-Path $TargetDir "config\skinlayers.json"
    $skinAction = Get-ConfigAction $SkinlayersJson
    Merge-JsonFile $SkinlayersJson @{
        enableHat        = $T_Skinlayers
        enableJacket     = $T_Skinlayers
        enableLeftSleeve = $T_Skinlayers
        enableRightSleeve = $T_Skinlayers
        enableLeftPants  = $T_Skinlayers
        enableRightPants = $T_Skinlayers
    }
    Write-Log "config\skinlayers.json ($Tier, $skinAction): all 3D layer parts=$T_Skinlayers"

    # LambDynamicLights -- config\lambdynlights.toml, key "mode" (a quoted enum string).
    # The ONLY valid values are fastest / fast / fancy -- there is no "off" (confirmed
    # against DynamicLightsMode in the 4.9.1 jar). Writing "off" is an invalid enum that
    # silently falls back to the default (fancy), leaving lights ON. To disable dynamic
    # lighting for dalit we set the cheapest valid mode AND turn off every source in the
    # [light_sources] table. pandit/modi keep mode="fancy" with the mod's default sources.
    $LambdynToml = Join-Path $TargetDir "config\lambdynlights.toml"
    $lambAction = Get-ConfigAction $LambdynToml
    Set-TomlString $LambdynToml "mode" $T_Lambdyn
    if ($Tier -eq "dalit") {
        Set-LambdynLightsOff $LambdynToml
        Write-Log "config\lambdynlights.toml ($Tier, $lambAction): mode=`"$T_Lambdyn`" + all [light_sources] disabled"
    } else {
        Write-Log "config\lambdynlights.toml ($Tier, $lambAction): mode=`"$T_Lambdyn`""
    }

    # NOTE: Cull Leaves (config\cullleaves.json, key "enabled") and ImmediatelyFast are
    # ON for every tier. Cull Leaves defaults to enabled and ImmediatelyFast has no
    # master enable field (a pure optimizer, active once installed), so neither needs
    # a written config -- installing the jar is "on".

    # Iris (pandit/modi only) -- point it at the shaderpack, enable it, and set the
    # tier's Complementary profile. Iris stores the selected pack in
    # config\iris.properties (java.util.Properties) and per-shaderpack options --
    # including the profile -- in shaderpacks\<shaderPack>.txt, where <shaderPack> is
    # exactly the iris.properties "shaderPack" value (the .zip name for a zip pack).
    # Confirmed against the Iris jar: Iris.class resolves
    # getShaderpacksDirectory().resolve(name + ".txt") and reads "profile" via
    # queueShaderPackOptionsFromProperties.
    if ($HasShaders) {
        $IrisProperties = Join-Path $TargetDir "config\iris.properties"
        $irisAction = Get-ConfigAction $IrisProperties
        Merge-KvFile $IrisProperties "=" ([ordered]@{ "shaderPack" = $ShaderpackZip; "enableShaders" = "true" })
        Write-Log "config\iris.properties ($Tier, $irisAction): shaderPack=$ShaderpackZip, enableShaders=true"

        $ShaderpackOptionsTxt = Join-Path $ShaderpacksDir "$ShaderpackZip.txt"
        $profAction = Get-ConfigAction $ShaderpackOptionsTxt
        Merge-KvFile $ShaderpackOptionsTxt "=" ([ordered]@{ "profile" = $T_CompProfile })
        Write-Log "shaderpacks\$ShaderpackZip.txt ($Tier, $profAction): profile=$T_CompProfile"
    }

    # --- H: verify all mod jars ---
    # dalit: 43 active jars; pandit/modi: 44 active jars (Sodium swapped to 0.8.7, plus
    # Iris). The active jar count is derived from the manifest for this tier. Non-mod
    # files (the resourcepack, and the shaderpack for shader tiers) live in
    # resourcepacks\ and shaderpacks\ and are verified separately in H.4 below.
    Write-Log "[8/8] Verifying all $ExpectedJarCount mod jars by SHA-256..."

    # --- H.1: hard-fail on duplicate mods (two files for the same mod). The known-prefix
    # set is every distinct prefix from ALL manifest rows (all tiers), so a mod that is
    # inactive for this tier is still recognised. This must run BEFORE the tier-swap
    # artifact cleanup below, so a duplicate that was NOT produced by our own controlled
    # logic (e.g. a stray copy a user dropped in manually) is reported and aborted rather
    # than silently deleted out from under them. ---
    $ModKeyFiles = @{}
    $AllJars = Get-ChildItem -Path $ModsDir -Filter "*.jar" -File -ErrorAction SilentlyContinue
    foreach ($jarFile in $AllJars) {
        $bn = $jarFile.Name
        if ($bn -like "tl_skin_cape*.jar") { continue }

        $matched = $null
        foreach ($prefix in $AllModsPrefixes) {
            if ($bn.StartsWith($prefix)) {
                $matched = $prefix
                break
            }
        }

        if ($matched) {
            if (-not $ModKeyFiles.ContainsKey($matched)) {
                $ModKeyFiles[$matched] = @()
            }
            $ModKeyFiles[$matched] += $bn
        } else {
            if ($ActiveModsFiles -notcontains $bn) {
                Write-Warn2 "Unrecognized extra jar in mods\: $bn (not part of the expected pack; leaving in place)"
            }
        }
    }

    foreach ($prefix in $AllModsPrefixes) {
        if (-not $ModKeyFiles.ContainsKey($prefix)) { continue }
        $files = $ModKeyFiles[$prefix]
        if ($files.Count -gt 1) {
            $expectedName = $ActiveModsFiles | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
            Write-Host ("ERROR: Duplicate mod detected for prefix `"$prefix`" -- two versions of one mod will crash the game:") -ForegroundColor Red
            foreach ($fn in $files) {
                Write-Host "  - $fn" -ForegroundColor Red
            }
            if ($expectedName) {
                Write-Host ("  Keep `"$expectedName`" (expected) and delete the other file(s) listed above.") -ForegroundColor Red
            } else {
                Write-Host "  Delete all but one of the files listed above." -ForegroundColor Red
            }
            Fail "Duplicate mod jars found in $ModsDir."
        }
    }

    # --- H.2: remove our own tier-swap artifacts before the manifest check. A jar whose
    # filename is named by the FULL manifest (any tier) but is NOT active for this tier
    # (e.g. the base Sodium build left by a dalit->pandit switch) is our own artifact and
    # is safe to delete. This must not touch any file the manifest does not name; H.1
    # above already aborted on any duplicate a user introduced by hand. ---
    Get-ChildItem -Path $ModsDir -Filter "*.jar" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $bn = $_.Name
        if (($AllModsFiles -contains $bn) -and ($ActiveModsFiles -notcontains $bn)) {
            Write-Log "Removing tier-swap artifact jar: $bn (named by the manifest but not active for '$Tier')"
            Remove-Item -Force $_.FullName
        }
    }

    # --- H.3: every active mod jar exists at mods\<filename> with the right hash ---
    $Missing = @()
    $Mismatched = @()
    $VerifiedCount = 0

    foreach ($row in $ActiveRows) {
        if ($row.Dest -ne "mods") { continue }
        $fname = $row.File
        $expected = $row.Sha
        $target = Join-Path $ModsDir $fname
        if (-not (Test-Path -LiteralPath $target)) {
            $Missing += $fname
            continue
        }
        $actual = Get-Sha256 -path $target
        if ($actual -ne $expected) {
            $Mismatched += "$fname(expected=$expected,got=$actual)"
            continue
        }
        $VerifiedCount++
    }

    if ($Missing.Count -gt 0 -or $Mismatched.Count -gt 0) {
        if ($Missing.Count -gt 0) {
            Write-Host ("ERROR: Missing mod jars in $ModsDir : " + ($Missing -join ", ")) -ForegroundColor Red
        }
        if ($Mismatched.Count -gt 0) {
            Write-Host ("ERROR: Mismatched mod jars in $ModsDir : " + ($Mismatched -join ", ")) -ForegroundColor Red
        }
        Fail "Mod jar verification failed. See errors above."
    }

    # --- H.4: every active non-mod file (resourcepack, and shaderpack for shader tiers)
    # exists at <gamedir>\<dest>\<filename> with the right hash (same SHA-256 gate). ---
    $NonModsMissing = @()
    $NonModsMismatched = @()
    $NonModsVerified = 0
    foreach ($row in $ActiveRows) {
        if ($row.Dest -eq "mods") { continue }
        $ntarget = Join-Path (Join-Path $TargetDir $row.Dest) $row.File
        if (-not (Test-Path -LiteralPath $ntarget)) {
            $NonModsMissing += "$($row.Dest)/$($row.File)"
            continue
        }
        $nactual = Get-Sha256 -path $ntarget
        if ($nactual -ne $row.Sha) {
            $NonModsMismatched += "$($row.Dest)/$($row.File)(expected=$($row.Sha),got=$nactual)"
            continue
        }
        $NonModsVerified++
    }

    if ($NonModsMissing.Count -gt 0 -or $NonModsMismatched.Count -gt 0) {
        if ($NonModsMissing.Count -gt 0) {
            Write-Host ("ERROR: Missing files in $TargetDir : " + ($NonModsMissing -join ", ")) -ForegroundColor Red
        }
        if ($NonModsMismatched.Count -gt 0) {
            Write-Host ("ERROR: Mismatched files in $TargetDir : " + ($NonModsMismatched -join ", ")) -ForegroundColor Red
        }
        Fail "Resourcepack/shaderpack verification failed. See errors above."
    }

    Write-Log "All $ExpectedJarCount mod jars + $NonModsVerified other file(s) verified."

    # --- I: final summary ---
    Write-Log "Install complete."
    Write-Log "Game directory: $TargetDir"
    Write-Log "Select this version in your launcher: $ProfileId"
    Write-Log "Verified jar count: $VerifiedCount / $ExpectedJarCount (+ $NonModsVerified other file(s))"
    if ($HasShaders) {
        Write-Log "Tier applied: $Tier (RAM -Xmx$T_Xmx; shaders ON: Iris + Sodium 0.8.7 + Complementary $T_CompProfile)."
    } else {
        Write-Log "Tier applied: $Tier (RAM -Xmx$T_Xmx; no shaders, Sodium 0.8.14-beta.2)."
    }
    Write-Log "Reminder: do not add OptiFine - Sodium is included."

} finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force -Path $TempDir -ErrorAction SilentlyContinue
    }
}

exit 0
