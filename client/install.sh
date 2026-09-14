#!/bin/sh
# Fabric Friends Client Pack installer for Minecraft 1.21.11 / Fabric loader 0.19.3
# POSIX sh. No Java required at any point.
set -eu

FABRIC_MC_VERSION="1.21.11"
FABRIC_LOADER_VERSION="0.19.3"
FABRIC_LOADER_ID="fabric-loader-${FABRIC_LOADER_VERSION}-${FABRIC_MC_VERSION}"
VERSION_MANIFEST_URL="https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
FABRIC_PROFILE_URL="https://meta.fabricmc.net/v2/versions/loader/${FABRIC_MC_VERSION}/${FABRIC_LOADER_VERSION}/profile/json"
# --- modflared forced-tunnels config (written into the game dir during install) ---
FORCED_TUNNELS_JSON='["minecraft.dekhlo.to"]'

# --- manifest resolution ---
# mods.generated.tsv (the mod/resourcepack/shaderpack table) and purge.generated.txt
# (server-only filename prefixes) are the single source of truth, generated from
# mods.json by scripts/generate. This installer is normally piped straight to sh with
# no checkout, so it resolves each file at runtime (see resolve_asset below): a
# --manifest override first, else a copy sitting next to the script, else a fetch from
# the raw GitHub URL. The mods table, shader stack, resourcepack, server-only prefixes,
# and duplicate-detection prefixes are all derived from these files, not hardcoded here.
RAW_BASE_URL="https://raw.githubusercontent.com/Adarsh077/minecraft/main/client"

TARGET_DIR=""
TMPDIR_CREATED=""
TIER=""
MANIFEST_ARG=""
# HAS_SHADERS is derived from the manifest below: a tier "has shaders" iff some active
# manifest row installs into shaderpacks/. There is no user-facing shader flag.
HAS_SHADERS=0

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: sh install.sh (--dalit | --pandit | --modi) [--dir DIR] [--manifest PATH-OR-URL]\n' >&2
  printf '  A tier is REQUIRED:\n' >&2
  printf '    --dalit   very low end: Complementary shaders (POTATO), minimal settings, -Xmx3G\n' >&2
  printf '    --pandit  medium: Complementary shaders (MEDIUM), -Xmx5G\n' >&2
  printf '    --modi    dedicated GPU: Complementary shaders (HIGH), -Xmx8G\n' >&2
  printf '    --manifest PATH-OR-URL  override the generated mods.generated.tsv source (testing/local)\n' >&2
}

cleanup() {
  if [ -n "$TMPDIR_CREATED" ] && [ -d "$TMPDIR_CREATED" ]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}
trap cleanup EXIT INT TERM

# --- arg parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      [ $# -ge 2 ] || die "--dir requires a value"
      TARGET_DIR="$2"
      shift 2
      ;;
    --manifest)
      [ $# -ge 2 ] || die "--manifest requires a value"
      MANIFEST_ARG="$2"
      shift 2
      ;;
    --dalit)
      [ -z "$TIER" ] || die "Only one tier flag may be given (--dalit / --pandit / --modi)"
      TIER="dalit"
      shift
      ;;
    --pandit)
      [ -z "$TIER" ] || die "Only one tier flag may be given (--dalit / --pandit / --modi)"
      TIER="pandit"
      shift
      ;;
    --modi)
      [ -z "$TIER" ] || die "Only one tier flag may be given (--dalit / --pandit / --modi)"
      TIER="modi"
      shift
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

# A tier flag is REQUIRED -- there is no default.
if [ -z "$TIER" ]; then
  usage
  die "No tier given. Choose exactly one of --dalit / --pandit / --modi."
fi

# --- per-tier settings ---
# All tiers install ALL mods; tiers differ only in shader stack and written config.
# Whether a tier gets Iris + the Sodium 0.8.7 swap is derived from the manifest below
# (HAS_SHADERS), not set here.
case "$TIER" in
    dalit)
      T_RENDER_DISTANCE=5;  T_SIM_DISTANCE=5;  T_GRAPHICS=0; T_PARTICLES=2
      T_MIPMAP=0;           T_BIOME_BLEND=0;   T_MAXFPS=60
      T_ENTITY_SHADOWS=false; T_AO=false;      T_ENTITY_DIST_SCALE=0.5
      T_XMX="3G"
      T_COMP_PROFILE="POTATO"
      T_SOUND_PHYSICS=false
      T_LAMBDYN="fastest"
      T_CONTINUITY=false
      T_SKINLAYERS=false
      T_SODIUM_ANIMATE_VISIBLE_ONLY=true
      T_SODIUM_RENDER_AHEAD=0
      ;;
    pandit)
      T_RENDER_DISTANCE=9;  T_SIM_DISTANCE=8;  T_GRAPHICS=1; T_PARTICLES=1
      T_MIPMAP=2;           T_BIOME_BLEND=2;   T_MAXFPS=120
      T_ENTITY_SHADOWS=true; T_AO=true;        T_ENTITY_DIST_SCALE=1.0
      T_XMX="5G"
      T_COMP_PROFILE="MEDIUM"
      T_SOUND_PHYSICS=true
      T_LAMBDYN="fancy"
      T_CONTINUITY=true
      T_SKINLAYERS=true
      T_SODIUM_ANIMATE_VISIBLE_ONLY=true
      T_SODIUM_RENDER_AHEAD=2
      ;;
    modi)
      T_RENDER_DISTANCE=16; T_SIM_DISTANCE=12; T_GRAPHICS=2; T_PARTICLES=0
      T_MIPMAP=4;           T_BIOME_BLEND=5;   T_MAXFPS=240
      T_ENTITY_SHADOWS=true; T_AO=true;        T_ENTITY_DIST_SCALE=1.0
      T_XMX="8G"
      T_COMP_PROFILE="HIGH"
      T_SOUND_PHYSICS=true
      T_LAMBDYN="fancy"
      T_CONTINUITY=true
      T_SKINLAYERS=true
      T_SODIUM_ANIMATE_VISIBLE_ONLY=false
      T_SODIUM_RENDER_AHEAD=3
      ;;
esac

# --- OS detection ---
if [ -z "$TARGET_DIR" ]; then
  UNAME_S="$(uname -s)"
  case "$UNAME_S" in
    Darwin)
      TARGET_DIR="$HOME/Library/Application Support/minecraft"
      ;;
    *)
      TARGET_DIR="$HOME/.minecraft"
      ;;
  esac
fi

if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR"
  warn "Game directory did not exist and was created at: $TARGET_DIR"
  warn "Please launch vanilla ${FABRIC_MC_VERSION} once from your launcher first so assets download, then re-run this installer."
fi

log "[0/8] Using game directory: $TARGET_DIR"

MODS_DIR="$TARGET_DIR/mods"
mkdir -p "$MODS_DIR"

# The manifest is resolved and parsed further down (after the temp dir and the fetch
# helper exist); the tier reconciliation of mods/ happens there, still BEFORE anything
# downloads or the duplicate check runs.

# --- helper: hash tools ---
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "Neither sha256sum nor shasum is available; cannot verify downloads."
  fi
}

sha1_of() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "$1" | awk '{print $1}'
  else
    die "Neither sha1sum nor shasum is available; cannot verify vanilla client jar."
  fi
}

# --- helper: download ---
fetch() {
  # fetch URL DEST
  _url="$1"
  _dest="$2"
  if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --location --retry 3 --output "$_dest" "$_url"; then
      die "Download failed: $_url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -O "$_dest" "$_url"; then
      die "Download failed: $_url"
    fi
  else
    die "Neither curl nor wget is available; cannot download $_url"
  fi
}

# --- helper: download a file and verify its SHA-256 (idempotent) ---
# download_verify FILENAME SHA256 URL DESTDIR
# Skips the download if the file is already present with the right hash.
download_verify() {
  _dv_name="$1"
  _dv_sha="$2"
  _dv_url="$3"
  _dv_dir="$4"
  mkdir -p "$_dv_dir"
  _dv_dest="$_dv_dir/$_dv_name"
  if [ -f "$_dv_dest" ] && [ "$(sha256_of "$_dv_dest")" = "$_dv_sha" ]; then
    log "Already present and verified: $_dv_name"
    return 0
  fi
  log "Downloading: $_dv_name"
  _dv_part="$_dv_dest.part"
  fetch "$_dv_url" "$_dv_part"
  _dv_actual="$(sha256_of "$_dv_part")"
  if [ "$_dv_actual" != "$_dv_sha" ]; then
    rm -f "$_dv_part"
    die "SHA-256 mismatch for $_dv_name: expected $_dv_sha, got $_dv_actual (url: $_dv_url)"
  fi
  mv "$_dv_part" "$_dv_dest"
}

# --- helper: merge key/value lines into a colon- or equals-separated text config ---
# Reads "KEY VALUE" pairs on stdin (VALUE = everything after the first space).
# Existing lines for a key are replaced in place; every other line is preserved
# byte-for-byte; keys not already present are appended. The file (and its parent
# directory) is created if absent. Used for options.txt (":") and .properties ("=").
merge_kv_file() {
  _mkv_file="$1"
  _mkv_sep="$2"
  # Pairs are staged through a file (not an awk -v value): macOS/BSD awk hard-errors
  # ("newline in string ... at source line 1") on a -v value containing a literal
  # newline, which every multi-pair caller here (e.g. options.txt's tier settings)
  # produces. GNU awk tolerates it, so this only breaks on macOS. A file read via
  # getline works identically on every awk.
  _mkv_pairs_file="$_mkv_file.pairs.$$"
  cat > "$_mkv_pairs_file"
  mkdir -p "$(dirname "$_mkv_file")"
  [ -f "$_mkv_file" ] || : > "$_mkv_file"
  _mkv_tmp="$_mkv_file.tmp.$$"
  awk -v sep="$_mkv_sep" -v pairs_file="$_mkv_pairs_file" '
    BEGIN {
      while ((getline line < pairs_file) > 0) {
        if (line == "") continue
        p = index(line, " ")
        k = substr(line, 1, p - 1)
        v = substr(line, p + 1)
        key[k] = v
      }
      close(pairs_file)
    }
    {
      handled = 0
      for (k in key) {
        # Tolerate optional whitespace before the separator (a mod may re-save
        # "key = value"); always re-write in canonical "key<sep>value" form.
        if ($0 ~ ("^" k "[ \t]*" sep)) { print k sep key[k]; seen[k] = 1; handled = 1; break }
      }
      if (!handled) print
    }
    END {
      for (k in key) if (!seen[k]) print k sep key[k]
    }
  ' "$_mkv_file" > "$_mkv_tmp" && mv "$_mkv_tmp" "$_mkv_file"
  rm -f "$_mkv_pairs_file"
}

# --- helper: set a quoted-string key in a TOML file (create if absent) ---
# Writes `KEY = "VALUE"`, replacing any existing line for KEY (TOML forbids
# duplicate keys, so this cannot just append). Every other line is preserved.
set_toml_string() {
  _ts_file="$1"
  _ts_key="$2"
  _ts_val="$3"
  mkdir -p "$(dirname "$_ts_file")"
  [ -f "$_ts_file" ] || : > "$_ts_file"
  _ts_tmp="$_ts_file.tmp.$$"
  awk -v k="$_ts_key" -v val="$_ts_val" '
    BEGIN { line = k " = \"" val "\"" }
    $0 ~ ("^[ \t]*" k "[ \t]*=") { if (!seen) { print line; seen = 1 }; next }
    { print }
    END { if (!seen) print line }
  ' "$_ts_file" > "$_ts_tmp" && mv "$_ts_tmp" "$_ts_file"
}

# --- helper: write LambDynamicLights' [light_sources] table with every source off ---
# LambDynamicLights (NightConfig) reads each light source via the path
# "light_sources.<name>" and serialises them as a nested [light_sources] TOML table,
# so we write that exact shape. entities / self / beam / firefly / guardian_laser /
# sonic_boom / glowing_effect are booleans and go to false. creeper and tnt are NOT
# booleans -- they are ExplosiveLightingMode, which in 4.9.1 declares only SIMPLE and
# FANCY (verified in ExplosiveLightingMode.class). There is no OFF, so explosion
# lighting cannot be switched off here at all; "simple" is the cheaper of the two and
# is the floor. A bare `false`, or the string "off", is an invalid enum value that
# byId()/valueOf() silently falls back to the default for, leaving it ON.
# water_sensitive_check is a submersion behaviour flag, not a light source, so it is
# left untouched. Replaces an existing [light_sources] table if present (idempotent),
# otherwise appends one.
set_lambdyn_lights_off() {
  _ll_file="$1"
  mkdir -p "$(dirname "$_ll_file")"
  [ -f "$_ll_file" ] || : > "$_ll_file"
  _ll_tmp="$_ll_file.tmp.$$"
  awk '
    /^[ \t]*\[light_sources\][ \t]*$/ { in_ls = 1; next }
    in_ls && /^[ \t]*\[/            { in_ls = 0 }
    in_ls                          { next }
    /^[ \t]*light_sources\./        { next }
    { print }
    END {
      print "[light_sources]"
      print "\tentities = false"
      print "\tself = false"
      print "\tcreeper = \"simple\""
      print "\ttnt = \"simple\""
      print "\tbeam = false"
      print "\tfirefly = false"
      print "\tguardian_laser = false"
      print "\tsonic_boom = false"
      print "\tglowing_effect = false"
    }
  ' "$_ll_file" > "$_ll_tmp" && mv "$_ll_tmp" "$_ll_file"
}

# --- helper: ensure a pack id is present in options.txt's resourcePacks list ---
# The line is a JSON array: resourcePacks:["vanilla","file/Foo.zip"]. This preserves
# any packs the friend already enabled and appends the given id if it is absent.
# Minecraft 1.21.11 references a resourcepacks/ file as "file/<filename>" -- the
# "file/" prefix is confirmed present in the vanilla client's resource-pack class.
enable_resourcepack() {
  _rp_file="$1"       # options.txt path
  _rp_id="$2"         # e.g. file/Presence Footsteps R3.zip
  mkdir -p "$(dirname "$_rp_file")"
  [ -f "$_rp_file" ] || : > "$_rp_file"
  _rp_line="$(grep '^resourcePacks:' "$_rp_file" 2>/dev/null | head -n 1 || true)"
  if [ -z "$_rp_line" ]; then
    printf '%s\n' "resourcePacks:[\"vanilla\",\"$_rp_id\"]" >> "$_rp_file"
    return 0
  fi
  # Already present? (match the quoted id exactly)
  _rp_quoted="\"$_rp_id\""
  case "$_rp_line" in
    *"$_rp_quoted"*) return 0 ;;
  esac
  _rp_array="${_rp_line#resourcePacks:}"
  if [ "$_rp_array" = "[]" ]; then
    _rp_new="resourcePacks:[\"$_rp_id\"]"
  else
    _rp_new="resourcePacks:${_rp_array%]},\"$_rp_id\"]"
  fi
  _rp_tmp="$_rp_file.tmp.$$"
  awk -v newline="$_rp_new" '
    /^resourcePacks:/ && !done { print newline; done = 1; next }
    { print }
  ' "$_rp_file" > "$_rp_tmp" && mv "$_rp_tmp" "$_rp_file"
}

# --- helper: deep-merge a JSON patch into a JSON file (create if absent) ---
# Prefers python3, then jq. If neither is available and the file is absent, the
# patch is written verbatim (a partial JSON is safe for every consumer here). If
# neither is available and the file already exists, it is left untouched (we must
# not clobber a friend's config) and a warning is logged; return 1 in that case.
json_merge() {
  _jm_file="$1"
  _jm_patch="$2"
  mkdir -p "$(dirname "$_jm_file")"
  if command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$_jm_patch" | python3 -c '
import json, sys
path = sys.argv[1]
patch = json.load(sys.stdin)
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, ValueError):
    data = {}
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        else:
            a[k] = v
merge(data, patch)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
' "$_jm_file"; then
      return 0
    fi
    warn "Failed to write JSON config $_jm_file; leaving it untouched."
    return 1
  elif command -v jq >/dev/null 2>&1; then
    _jm_base="$_jm_file"
    if [ ! -f "$_jm_file" ]; then
      _jm_base="$TMPDIR_CREATED/json_merge_empty.json"
      printf '{}' > "$_jm_base"
    fi
    _jm_tmp="$_jm_file.tmp.$$"
    if printf '%s' "$_jm_patch" | jq -s '.[0] * .[1]' "$_jm_base" - > "$_jm_tmp"; then
      mv "$_jm_tmp" "$_jm_file"
      return 0
    fi
    rm -f "$_jm_tmp"
    warn "Failed to write JSON config $_jm_file; leaving it untouched."
    return 1
  elif [ ! -f "$_jm_file" ]; then
    printf '%s\n' "$_jm_patch" > "$_jm_file"
    return 0
  else
    warn "Neither python3 nor jq available; not merging $_jm_file (leaving your existing config untouched)."
    return 1
  fi
}

# --- helper: report whether a config file will be created or merged (for logging) ---
config_action() {
  if [ -f "$1" ]; then printf 'merged'; else printf 'created'; fi
}

TMPDIR_CREATED="$(mktemp -d)"

# --- resolve + parse the generated manifest (single source of truth) ---
# Determine the script's own directory when it is resolvable. When the script is piped
# to sh ("... | sh -s -- --dalit"), $0 is "sh" or "-" with no slash, so it must NOT be
# treated as a path: only use it when it contains a slash AND the file beside it
# actually exists. This must never blow up under set -eu.
SCRIPT_DIR=""
case "$0" in
  */*)
    _sd="$(dirname "$0")"
    [ -d "$_sd" ] && SCRIPT_DIR="$_sd"
    ;;
esac

# resolve_asset FILENAME OVERRIDE -> prints a local path to the resolved file.
# OVERRIDE (may be empty; only the manifest passes one) is honoured first and can be a
# local path or an http(s) URL. Else a copy next to the script is used when present.
# Else it is fetched from RAW_BASE_URL into the temp dir.
resolve_asset() {
  _ra_name="$1"
  _ra_override="$2"
  if [ -n "$_ra_override" ]; then
    case "$_ra_override" in
      http://*|https://*)
        _ra_dest="$TMPDIR_CREATED/$_ra_name"
        fetch "$_ra_override" "$_ra_dest"
        printf '%s' "$_ra_dest"
        return 0
        ;;
      *)
        [ -f "$_ra_override" ] || die "Manifest not found: $_ra_override"
        printf '%s' "$_ra_override"
        return 0
        ;;
    esac
  fi
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$_ra_name" ]; then
    printf '%s' "$SCRIPT_DIR/$_ra_name"
    return 0
  fi
  _ra_dest="$TMPDIR_CREATED/$_ra_name"
  fetch "$RAW_BASE_URL/$_ra_name" "$_ra_dest"
  printf '%s' "$_ra_dest"
}

MANIFEST_FILE="$(resolve_asset "mods.generated.tsv" "$MANIFEST_ARG")"
[ -f "$MANIFEST_FILE" ] || die "Could not obtain the mod manifest (mods.generated.tsv)."
PURGE_FILE="$(resolve_asset "purge.generated.txt" "")"
[ -f "$PURGE_FILE" ] || die "Could not obtain the server-only purge list (purge.generated.txt)."

TAB="$(printf '\t')"

# Parse the TSV (filename<TAB>sha256<TAB>url<TAB>dest<TAB>tiers<TAB>prefix), skipping
# blank and #-comment lines. A row is ACTIVE for this tier when tiers is "*" or the
# tier appears in the comma-separated list. Filenames may contain spaces, so every
# split here is on TAB only. Derived outputs (temp files, all TAB-separated):
#   active_rows.tsv    filename<TAB>sha<TAB>url<TAB>dest<TAB>prefix  (active only)
#   inactive_mods.tsv  filename<TAB>prefix                          (inactive, dest=mods)
#   all_mods.tsv       filename<TAB>prefix                          (dest=mods, ALL tiers)
# plus scalar files jarcount.txt (active dest=mods count) and has_shaders.txt (0/1).
ACTIVE_ROWS="$TMPDIR_CREATED/active_rows.tsv"
INACTIVE_MODS="$TMPDIR_CREATED/inactive_mods.tsv"
ALL_MODS="$TMPDIR_CREATED/all_mods.tsv"
awk -F"$TAB" -v tier="$TIER" \
    -v active_out="$ACTIVE_ROWS" -v inactive_out="$INACTIVE_MODS" \
    -v allmods_out="$ALL_MODS" -v jar_out="$TMPDIR_CREATED/jarcount.txt" \
    -v shaders_out="$TMPDIR_CREATED/has_shaders.txt" '
  BEGIN { jarcount = 0; has_shaders = 0 }
  /^[ \t]*#/ { next }
  NF < 6 { next }
  {
    filename = $1; sha = $2; url = $3; dest = $4; tiers = $5; prefix = $6
    active = (tiers == "*")
    if (!active) {
      n = split(tiers, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == tier) active = 1
    }
    if (dest == "mods") print filename "\t" prefix > allmods_out
    if (active) {
      print filename "\t" sha "\t" url "\t" dest "\t" prefix > active_out
      if (dest == "mods") jarcount++
      if (dest == "shaderpacks") has_shaders = 1
    } else if (dest == "mods") {
      print filename "\t" prefix > inactive_out
    }
  }
  END {
    print jarcount > jar_out
    print has_shaders > shaders_out
  }
' "$MANIFEST_FILE"

[ -f "$ACTIVE_ROWS" ] || die "Manifest produced no active rows for tier '$TIER' (source: $MANIFEST_FILE)."
EXPECTED_JAR_COUNT="$(cat "$TMPDIR_CREATED/jarcount.txt" 2>/dev/null || printf '0')"
HAS_SHADERS="$(cat "$TMPDIR_CREATED/has_shaders.txt" 2>/dev/null || printf '0')"
[ "$EXPECTED_JAR_COUNT" -gt 0 ] 2>/dev/null || die "Manifest produced zero active mod jars for tier '$TIER' (source: $MANIFEST_FILE)."
[ -f "$INACTIVE_MODS" ] || : > "$INACTIVE_MODS"
[ -f "$ALL_MODS" ] || : > "$ALL_MODS"

# Derived filenames from the active non-mods rows.
SHADERPACK_ZIP="$(awk -F"$TAB" '$4=="shaderpacks"{print $1; exit}' "$ACTIVE_ROWS")"
ACTIVE_RESOURCEPACKS="$TMPDIR_CREATED/active_resourcepacks.txt"
awk -F"$TAB" '$4=="resourcepacks"{print $1}' "$ACTIVE_ROWS" > "$ACTIVE_RESOURCEPACKS"

# --- reconcile the mods/ directory with this tier BEFORE anything downloads or the
# duplicate check runs, so switching tiers never leaves an inactive or stale jar
# behind. "side" in mods.json decides server-only removal (step [4/8]); the per-mod
# tier list decides this. (shaderpacks/ is left untouched -- the zips are harmless.)
# 1. Every INACTIVE dest=mods row whose exact file is present is removed.
while IFS="$TAB" read -r _rf _rp; do
  [ -n "$_rf" ] || continue
  if [ -f "$MODS_DIR/$_rf" ]; then
    log "Tier '$TIER': removing inactive mod: $_rf"
    rm -f "$MODS_DIR/$_rf"
  fi
done < "$INACTIVE_MODS"
# 2. Any prefix owned by an INACTIVE row but NOT by any ACTIVE row (e.g. iris-fabric-
# when this tier has no shaders) has every matching jar removed -- this also clears an
# Iris/Sodium left behind at a DIFFERENT version than the one currently pinned.
ACTIVE_PREFIXES="$(awk -F"$TAB" '$4=="mods"{print $5}' "$ACTIVE_ROWS" | sort -u)"
awk -F"$TAB" '{print $2}' "$INACTIVE_MODS" | sort -u | while IFS= read -r _ip; do
  [ -n "$_ip" ] || continue
  if ! printf '%s\n' "$ACTIVE_PREFIXES" | grep -qxF "$_ip"; then
    for f in "$MODS_DIR/$_ip"*.jar; do
      [ -f "$f" ] || continue
      log "Tier '$TIER': removing stale mod for prefix '$_ip': $(basename "$f")"
      rm -f "$f"
    done
  fi
done
# 3. Any jar matching an ACTIVE prefix whose filename is not the active one is a
# superseded build of a mod we do install -- the pre-Iris Sodium left by a dalit
# install from before every tier had shaders, or any mod whose pin was bumped. It is
# removed here rather than left for H.1, which would abort the whole install on a
# duplicate a friend has no way to resolve by hand.
while IFS="$TAB" read -r _af _asha _aurl _adest _ap; do
  [ "$_adest" = "mods" ] || continue
  for f in "$MODS_DIR/$_ap"*.jar; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$_af" ] && continue
    log "Tier '$TIER': removing superseded build for prefix '$_ap': $(basename "$f")"
    rm -f "$f"
  done
done < "$ACTIVE_ROWS"

# --- A/B: vanilla base version ---
VERSION_DIR="$TARGET_DIR/versions/${FABRIC_MC_VERSION}"
VERSION_JSON="$VERSION_DIR/${FABRIC_MC_VERSION}.json"
VERSION_JAR="$VERSION_DIR/${FABRIC_MC_VERSION}.jar"

if [ -f "$VERSION_JSON" ] && [ -f "$VERSION_JAR" ]; then
  log "[1/8] Vanilla ${FABRIC_MC_VERSION} base version already present, skipping."
else
  log "[1/8] Installing vanilla ${FABRIC_MC_VERSION} base version..."
  mkdir -p "$VERSION_DIR"
  MANIFEST_JSON="$TMPDIR_CREATED/version_manifest_v2.json"
  fetch "$VERSION_MANIFEST_URL" "$MANIFEST_JSON"

  VERSION_URL=""
  if command -v python3 >/dev/null 2>&1; then
    VERSION_URL="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for v in data.get("versions", []):
    if v.get("id") == sys.argv[2]:
        print(v.get("url", ""))
        break
' "$MANIFEST_JSON" "$FABRIC_MC_VERSION")"
  elif command -v jq >/dev/null 2>&1; then
    VERSION_URL="$(jq -r --arg id "$FABRIC_MC_VERSION" '.versions[] | select(.id == $id) | .url' "$MANIFEST_JSON" | head -n 1)"
  else
    VERSION_URL="$(grep -o "\"id\": *\"${FABRIC_MC_VERSION}\"[^}]*\"url\": *\"[^\"]*\"" "$MANIFEST_JSON" | grep -o '"url": *"[^"]*"' | sed 's/"url": *"//; s/"$//' | head -n 1)"
    if [ -z "$VERSION_URL" ]; then
      VERSION_URL="$(tr ',' '\n' < "$MANIFEST_JSON" | grep -B2 "\"id\": *\"${FABRIC_MC_VERSION}\"" | grep '"url"' | sed 's/.*"url": *"//; s/".*//' | head -n 1)"
    fi
  fi

  [ -n "$VERSION_URL" ] || die "Could not find version ${FABRIC_MC_VERSION} in ${VERSION_MANIFEST_URL}"

  fetch "$VERSION_URL" "$VERSION_JSON"

  CLIENT_URL=""
  CLIENT_SHA1=""
  if command -v python3 >/dev/null 2>&1; then
    CLIENT_URL="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data["downloads"]["client"]["url"])
' "$VERSION_JSON")"
    CLIENT_SHA1="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data["downloads"]["client"]["sha1"])
' "$VERSION_JSON")"
  elif command -v jq >/dev/null 2>&1; then
    CLIENT_URL="$(jq -r '.downloads.client.url' "$VERSION_JSON")"
    CLIENT_SHA1="$(jq -r '.downloads.client.sha1' "$VERSION_JSON")"
  else
    # No python3, no jq. The version JSON is single-line minified. The
    # "downloads" object's "client" key has a value object with no nested
    # braces (just sha1/size/url), so the literal sequence
    # "downloads": {"client": { ... } is unambiguous -- there is also an
    # unrelated top-level "logging": {"client": {"argument": ...}} object
    # elsewhere in the file, so we must anchor on "downloads":{"client": and
    # not on "client": alone, or a greedy match can grab the wrong one.
    # This also guarantees we get "client", not "client_mappings"/"server"/
    # "server_mappings" (the next key after downloads.client's closing brace).
    CLIENT_FRAGMENT="$(tr -d '\n' < "$VERSION_JSON" | sed -E 's/.*"downloads": *\{"client": *\{([^}]*)\}.*/\1/')"
    CLIENT_URL="$(printf '%s' "$CLIENT_FRAGMENT" | grep -o '"url" *: *"[^"]*"' | head -n 1 | sed 's/.*"url" *: *"//; s/"$//')"
    CLIENT_SHA1="$(printf '%s' "$CLIENT_FRAGMENT" | grep -o '"sha1" *: *"[^"]*"' | head -n 1 | sed 's/.*"sha1" *: *"//; s/"$//')"
  fi

  [ -n "$CLIENT_URL" ] && [ "$CLIENT_URL" != "null" ] || die "Could not read downloads.client.url from ${VERSION_JSON}"
  [ -n "$CLIENT_SHA1" ] && [ "$CLIENT_SHA1" != "null" ] || die "Could not read downloads.client.sha1 from ${VERSION_JSON}"

  fetch "$CLIENT_URL" "$VERSION_JAR"

  ACTUAL_SHA1="$(sha1_of "$VERSION_JAR")"
  if [ "$ACTUAL_SHA1" != "$CLIENT_SHA1" ]; then
    rm -f "$VERSION_JAR"
    die "SHA-1 mismatch for ${VERSION_JAR}: expected $CLIENT_SHA1, got $ACTUAL_SHA1"
  fi
  log "Vanilla ${FABRIC_MC_VERSION} client jar verified."
fi

# --- C: fabric loader profile ---
log "[2/8] Installing Fabric loader profile (${FABRIC_LOADER_ID})..."
PROFILE_JSON="$TMPDIR_CREATED/fabric_profile.json"
fetch "$FABRIC_PROFILE_URL" "$PROFILE_JSON"

if ! grep -q '"inheritsFrom"' "$PROFILE_JSON"; then
  die "Fabric profile response missing \"inheritsFrom\": $FABRIC_PROFILE_URL"
fi
if ! grep -q 'net\.fabricmc\.loader\.impl\.launch\.knot\.KnotClient' "$PROFILE_JSON"; then
  die "Fabric profile response missing KnotClient main class: $FABRIC_PROFILE_URL"
fi

PROFILE_ID=""
if command -v python3 >/dev/null 2>&1; then
  PROFILE_ID="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data["id"])
' "$PROFILE_JSON")"
elif command -v jq >/dev/null 2>&1; then
  PROFILE_ID="$(jq -r '.id' "$PROFILE_JSON")"
else
  PROFILE_ID="$(grep -o '"id" *: *"[^"]*"' "$PROFILE_JSON" | head -n 1 | sed 's/.*"id" *: *"//; s/"$//')"
fi

[ -n "$PROFILE_ID" ] && [ "$PROFILE_ID" != "null" ] || die "Could not read id from Fabric profile response"

if [ "$PROFILE_ID" != "$FABRIC_LOADER_ID" ]; then
  warn "Fabric profile id ($PROFILE_ID) differs from expected ($FABRIC_LOADER_ID); continuing with actual id."
fi

FABRIC_VERSION_DIR="$TARGET_DIR/versions/${PROFILE_ID}"
mkdir -p "$FABRIC_VERSION_DIR"
cp "$PROFILE_JSON" "$FABRIC_VERSION_DIR/${PROFILE_ID}.json"
log "Fabric loader profile written to versions/${PROFILE_ID}/${PROFILE_ID}.json"

# --- D: launcher_profiles.json ---
log "[3/8] Registering launcher profile..."
LAUNCHER_PROFILES="$TARGET_DIR/launcher_profiles.json"

# When a tier is set, its RAM allocation goes in the profile's javaArgs field
# (the launcher otherwise applies its own default JVM args). Empty when no tier,
# in which case no javaArgs field is written and existing installs are unchanged.
JAVA_ARGS=""
if [ -n "$TIER" ]; then
  JAVA_ARGS="-Xmx${T_XMX} -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"
fi

if command -v python3 >/dev/null 2>&1; then
  # This step is a convenience only; a parse error or unwritable file must
  # never abort the install, so its exit status is checked directly (not
  # through a pipe) and converted into a warning.
  if python3 -c '
import json, sys

path = sys.argv[1]
profile_id = sys.argv[2]
java_args = sys.argv[3]

try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, ValueError):
    data = {"profiles": {}, "settings": {}, "version": 3}

if "profiles" not in data or not isinstance(data.get("profiles"), dict):
    data["profiles"] = {}

# Preserve any other fields on our profile object; only our known keys are
# authoritative, and javaArgs is set/removed based on whether a tier was given.
prof = data["profiles"].get("fabric-loader-1.21.11")
if not isinstance(prof, dict):
    prof = {}
prof.setdefault("created", "2026-08-11T00:00:00.000Z")
prof["name"] = "fabric-loader-1.21.11"
prof["type"] = "custom"
prof["lastVersionId"] = profile_id
prof["icon"] = "TNT"
if java_args:
    prof["javaArgs"] = java_args
data["profiles"]["fabric-loader-1.21.11"] = prof

with open(path, "w") as f:
    json.dump(data, f, indent=2)
' "$LAUNCHER_PROFILES" "$PROFILE_ID" "$JAVA_ARGS"; then
    if [ -n "$JAVA_ARGS" ]; then
      log "launcher_profiles.json updated (tier '$TIER': javaArgs -Xmx${T_XMX})."
    else
      log "launcher_profiles.json updated."
    fi
  else
    warn "Failed to update launcher_profiles.json; skipping. Select the ${PROFILE_ID} version manually in TLauncher."
  fi
elif command -v jq >/dev/null 2>&1; then
  if [ -f "$LAUNCHER_PROFILES" ]; then
    BASE_JSON="$LAUNCHER_PROFILES"
  else
    BASE_JSON="$TMPDIR_CREATED/base_launcher_profiles.json"
    printf '{"profiles":{},"settings":{},"version":3}' > "$BASE_JSON"
  fi
  NEW_JSON="$TMPDIR_CREATED/launcher_profiles.new.json"
  if jq --arg lastVersionId "$PROFILE_ID" --arg javaArgs "$JAVA_ARGS" \
    '.profiles["fabric-loader-1.21.11"] = ((.profiles["fabric-loader-1.21.11"] // {}) + {"name":"fabric-loader-1.21.11","type":"custom","created":((.profiles["fabric-loader-1.21.11"].created) // "2026-08-11T00:00:00.000Z"),"lastVersionId":$lastVersionId,"icon":"TNT"} + (if $javaArgs == "" then {} else {"javaArgs":$javaArgs} end))' \
    "$BASE_JSON" > "$NEW_JSON"; then
    mv "$NEW_JSON" "$LAUNCHER_PROFILES"
    if [ -n "$JAVA_ARGS" ]; then
      log "launcher_profiles.json updated (tier '$TIER': javaArgs -Xmx${T_XMX})."
    else
      log "launcher_profiles.json updated."
    fi
  else
    warn "Failed to update launcher_profiles.json; skipping. Select the ${PROFILE_ID} version manually in TLauncher."
  fi
else
  warn "No python3 or jq available; skipping launcher_profiles.json update. Select the ${PROFILE_ID} version manually in TLauncher."
fi

# --- E: remove server-only jars ---
# The prefixes come from purge.generated.txt: mods.json's "side" == server field is
# what decides a mod is server-only, so a friend's client mods/ never keeps them.
log "[4/8] Removing server-only jars from mods/ (if present)..."
while IFS= read -r prefix; do
  case "$prefix" in ''|'#'*) continue ;; esac
  for f in "$MODS_DIR"/"$prefix"*; do
    if [ -f "$f" ]; then
      log "Removing server-only jar: $(basename "$f")"
      rm -f "$f"
    fi
  done
done < "$PURGE_FILE"

# --- F: download + verify every file for this tier from the Modrinth CDN ---
log "[5/8] Downloading and verifying mods, resourcepack, and shaders (this transfers ~145 MB on a fresh install)..."
RESOURCEPACKS_DIR="$TARGET_DIR/resourcepacks"
SHADERPACKS_DIR="$TARGET_DIR/shaderpacks"

# 5a: every active mod jar -> mods/. The active rows are already staged in a temp file
# (not a pipe), so a download_verify failure aborts the whole script, not a subshell.
while IFS="$TAB" read -r dfname dsha durl ddest dprefix; do
  [ "$ddest" = "mods" ] || continue
  download_verify "$dfname" "$dsha" "$durl" "$MODS_DIR"
done < "$ACTIVE_ROWS"

# 5b: every active non-mod file -> its dest dir (resourcepacks/ or shaderpacks/).
# Filenames may contain spaces; download_verify quotes them.
while IFS="$TAB" read -r dfname dsha durl ddest dprefix; do
  case "$ddest" in
    resourcepacks) download_verify "$dfname" "$dsha" "$durl" "$RESOURCEPACKS_DIR" ;;
    shaderpacks)   download_verify "$dfname" "$dsha" "$durl" "$SHADERPACKS_DIR" ;;
  esac
done < "$ACTIVE_ROWS"

if [ "$HAS_SHADERS" = "1" ]; then
  log "Shaders installed for '$TIER': Iris, Sodium 0.8.7, Complementary Unbound (shaderpacks/$SHADERPACK_ZIP)."
fi

# --- G: modflared forced-tunnels config (written to both locations modflared reads) ---
log "[6/8] Writing modflared forced_tunnels.json..."
for d in "$TARGET_DIR/config/modflared" "$TARGET_DIR/modflared"; do
  mkdir -p "$d"
  printf '%s\n' "$FORCED_TUNNELS_JSON" > "$d/forced_tunnels.json"
  log "Wrote $d/forced_tunnels.json"
done

# --- G.7: tier config ---
# A tier is always set by this point. Every config path below was verified against
# the mod jar; mods whose path could not be verified are deliberately left unset.
if [ -n "$TIER" ]; then
  log "[7/8] Writing '$TIER' tier config..."

  # options.txt -- vanilla, colon-separated. Merge: replace only the tier keys,
  # keep every other line byte-identical, append any that are absent.
  OPTIONS_TXT="$TARGET_DIR/options.txt"
  _opt_action="$(config_action "$OPTIONS_TXT")"
  printf '%s\n' "renderDistance $T_RENDER_DISTANCE
simulationDistance $T_SIM_DISTANCE
graphicsMode $T_GRAPHICS
particles $T_PARTICLES
mipmapLevels $T_MIPMAP
biomeBlendRadius $T_BIOME_BLEND
maxFps $T_MAXFPS
entityShadows $T_ENTITY_SHADOWS
ao $T_AO
entityDistanceScaling $T_ENTITY_DIST_SCALE" | merge_kv_file "$OPTIONS_TXT" ":"
  log "options.txt ($TIER, $_opt_action): renderDistance=$T_RENDER_DISTANCE simulationDistance=$T_SIM_DISTANCE graphicsMode=$T_GRAPHICS particles=$T_PARTICLES mipmapLevels=$T_MIPMAP biomeBlendRadius=$T_BIOME_BLEND maxFps=$T_MAXFPS entityShadows=$T_ENTITY_SHADOWS ao=$T_AO entityDistanceScaling=$T_ENTITY_DIST_SCALE"

  # Enable each active resourcepack (normally exactly one) -- copying it does not
  # switch it on. Merged into resourcePacks so a friend's enabled packs are kept.
  # If the tier has no resourcepack row, this simply enables nothing.
  while IFS= read -r _rpname; do
    [ -n "$_rpname" ] || continue
    enable_resourcepack "$OPTIONS_TXT" "file/$_rpname"
    log "options.txt ($TIER): resourcePacks += \"file/$_rpname\""
  done < "$ACTIVE_RESOURCEPACKS"

  # Sodium -- config/sodium-options.json. GSON field naming is
  # LOWER_CASE_WITH_UNDERSCORES, so the JSON keys are snake_case (NOT the Java
  # field names). Only confirmed primitive fields; no enum-valued fields.
  SODIUM_JSON="$TARGET_DIR/config/sodium-options.json"
  _sod_action="$(config_action "$SODIUM_JSON")"
  if json_merge "$SODIUM_JSON" "{\"performance\":{\"chunk_builder_threads\":0,\"use_entity_culling\":true,\"use_fog_occlusion\":true,\"use_block_face_culling\":true,\"animate_only_visible_textures\":$T_SODIUM_ANIMATE_VISIBLE_ONLY},\"advanced\":{\"cpu_render_ahead_limit\":$T_SODIUM_RENDER_AHEAD},\"quality\":{\"hidden_fluid_culling\":true}}"; then
    log "config/sodium-options.json ($TIER, $_sod_action): animate_only_visible_textures=$T_SODIUM_ANIMATE_VISIBLE_ONLY cpu_render_ahead_limit=$T_SODIUM_RENDER_AHEAD + culling on"
  fi

  # Sound Physics Remastered -- config/soundphysics.properties, key "enabled".
  SOUNDPHYSICS_PROPS="$TARGET_DIR/config/soundphysics.properties"
  _sp_action="$(config_action "$SOUNDPHYSICS_PROPS")"
  printf '%s\n' "enabled $T_SOUND_PHYSICS" | merge_kv_file "$SOUNDPHYSICS_PROPS" "="
  log "config/soundphysics.properties ($TIER, $_sp_action): enabled=$T_SOUND_PHYSICS"

  # Continuity -- config/continuity.json. Turning it "off" disables both
  # connected and emissive textures; "on" enables them.
  CONTINUITY_JSON="$TARGET_DIR/config/continuity.json"
  _cont_action="$(config_action "$CONTINUITY_JSON")"
  if json_merge "$CONTINUITY_JSON" "{\"connected_textures\":$T_CONTINUITY,\"emissive_textures\":$T_CONTINUITY}"; then
    log "config/continuity.json ($TIER, $_cont_action): connected_textures=$T_CONTINUITY emissive_textures=$T_CONTINUITY"
  fi

  # 3D Skin Layers -- config/skinlayers.json. No single master toggle; the 3D
  # layers are the per-body-part flags, so "off" clears them all, "on" sets them.
  SKINLAYERS_JSON="$TARGET_DIR/config/skinlayers.json"
  _skin_action="$(config_action "$SKINLAYERS_JSON")"
  if json_merge "$SKINLAYERS_JSON" "{\"enableHat\":$T_SKINLAYERS,\"enableJacket\":$T_SKINLAYERS,\"enableLeftSleeve\":$T_SKINLAYERS,\"enableRightSleeve\":$T_SKINLAYERS,\"enableLeftPants\":$T_SKINLAYERS,\"enableRightPants\":$T_SKINLAYERS}"; then
    log "config/skinlayers.json ($TIER, $_skin_action): all 3D layer parts=$T_SKINLAYERS"
  fi

  # LambDynamicLights -- config/lambdynlights.toml, key "mode" (a quoted enum string).
  # The ONLY valid values are fastest / fast / fancy -- there is no "off" (confirmed
  # against DynamicLightsMode in the 4.9.1 jar). Writing "off" is an invalid enum that
  # silently falls back to the default (fancy), leaving lights ON. To disable dynamic
  # lighting for dalit we set the cheapest valid mode AND turn off every source in the
  # [light_sources] table. pandit/modi keep mode="fancy" with the mod's default sources.
  LAMBDYN_TOML="$TARGET_DIR/config/lambdynlights.toml"
  _lamb_action="$(config_action "$LAMBDYN_TOML")"
  set_toml_string "$LAMBDYN_TOML" "mode" "$T_LAMBDYN"
  if [ "$TIER" = "dalit" ]; then
    set_lambdyn_lights_off "$LAMBDYN_TOML"
    log "config/lambdynlights.toml ($TIER, $_lamb_action): mode=\"$T_LAMBDYN\" + all [light_sources] disabled"
  else
    log "config/lambdynlights.toml ($TIER, $_lamb_action): mode=\"$T_LAMBDYN\""
  fi

  # NOTE: Cull Leaves (config/cullleaves.json, key "enabled") and ImmediatelyFast
  # are ON for every tier. Cull Leaves defaults to enabled and ImmediatelyFast
  # has no master enable field (it is a pure optimizer, active once installed),
  # so neither needs a written config -- installing the jar is "on".

  # Iris (every tier the manifest gives a shaderpack row) -- point it at the pack,
  # enable it, and set the tier's Complementary profile. Iris stores the selected pack
  # in config/iris.properties (java.util.Properties) and per-shaderpack options --
  # including the profile -- in shaderpacks/<shaderPack>.txt, where <shaderPack> is
  # exactly the iris.properties "shaderPack" value (the .zip name for a zip pack).
  # Confirmed against the Iris jar: Iris.class resolves
  # getShaderpacksDirectory().resolve(name + ".txt") and reads "profile" via
  # queueShaderPackOptionsFromProperties.
  if [ "$HAS_SHADERS" = "1" ]; then
    IRIS_PROPERTIES="$TARGET_DIR/config/iris.properties"
    _iris_action="$(config_action "$IRIS_PROPERTIES")"
    printf '%s\n' "shaderPack $SHADERPACK_ZIP
enableShaders true" | merge_kv_file "$IRIS_PROPERTIES" "="
    log "config/iris.properties ($TIER, $_iris_action): shaderPack=$SHADERPACK_ZIP, enableShaders=true"

    SHADERPACK_OPTIONS_TXT="$SHADERPACKS_DIR/$SHADERPACK_ZIP.txt"
    _prof_action="$(config_action "$SHADERPACK_OPTIONS_TXT")"
    printf '%s\n' "profile $T_COMP_PROFILE" | merge_kv_file "$SHADERPACK_OPTIONS_TXT" "="
    log "shaderpacks/$SHADERPACK_ZIP.txt ($TIER, $_prof_action): profile=$T_COMP_PROFILE"
  fi
fi

# --- H: verify all mod jars ---
# Every tier installs the same 44 active jars -- all three now run Iris + Sodium 0.8.7.
# The active jar count is derived from the manifest for this tier. Non-mod files
# (the resourcepack, and the shaderpack for shader tiers) live in resourcepacks/ and
# shaderpacks/ and are verified separately in H.4 below.
log "[8/8] Verifying all ${EXPECTED_JAR_COUNT} mod jars by SHA-256..."

# Precompute the sets used by the gate:
#   ALL_MOD_PREFIXES  every distinct prefix from ALL manifest rows (any tier), dest=mods
#   ACTIVE_MODS_FILES active dest=mods filenames (this tier)
#   ALL_MODS_FILES    every dest=mods filename (any tier)
ALL_MOD_PREFIXES="$(awk -F"$TAB" '{print $2}' "$ALL_MODS" | sort -u)"
ACTIVE_MODS_FILES="$TMPDIR_CREATED/active_mods_files.txt"
awk -F"$TAB" '$4=="mods"{print $1}' "$ACTIVE_ROWS" > "$ACTIVE_MODS_FILES"
ALL_MODS_FILES="$TMPDIR_CREATED/all_mods_files.txt"
awk -F"$TAB" '{print $1}' "$ALL_MODS" > "$ALL_MODS_FILES"

# --- H.1: hard-fail on duplicate mods (two files for the same mod). The known-prefix
# set is every distinct prefix from ALL manifest rows (all tiers), so a mod that is
# inactive for this tier is still recognised. This must run BEFORE the tier-swap
# artifact cleanup below, so a duplicate that was NOT produced by our own controlled
# logic (e.g. a stray copy a user dropped in manually) is reported and aborted rather
# than silently deleted out from under them. ---
DUP_TMP="$TMPDIR_CREATED/modkeys.txt"
: > "$DUP_TMP"
for f in "$MODS_DIR"/*.jar; do
  [ -f "$f" ] || continue
  bn="$(basename "$f")"
  case "$bn" in
    tl_skin_cape*.jar) continue ;;
  esac
  matched=""
  for prefix in $ALL_MOD_PREFIXES; do
    case "$bn" in
      "$prefix"*) matched="$prefix" ;;
    esac
    [ -n "$matched" ] && break
  done
  if [ -n "$matched" ]; then
    printf '%s %s\n' "$matched" "$bn" >> "$DUP_TMP"
  else
    if ! grep -qxF "$bn" "$ACTIVE_MODS_FILES"; then
      warn "Unrecognized extra jar in mods/: $bn (not part of the expected pack; leaving in place)"
    fi
  fi
done

for prefix in $ALL_MOD_PREFIXES; do
  files="$(awk -v p="$prefix" '$1==p{print $2}' "$DUP_TMP")"
  count=0
  [ -n "$files" ] && count="$(printf '%s\n' "$files" | grep -c .)"
  if [ "$count" -gt 1 ]; then
    expected_name="$(awk -v p="$prefix" 'index($0,p)==1{print; exit}' "$ACTIVE_MODS_FILES")"
    printf 'ERROR: Duplicate mod detected for prefix "%s" -- two versions of one mod will crash the game:\n' "$prefix" >&2
    printf '%s\n' "$files" | while IFS= read -r fn; do
      [ -n "$fn" ] || continue
      printf '  - %s\n' "$fn" >&2
    done
    if [ -n "$expected_name" ]; then
      printf '  Keep "%s" (expected) and delete the other file(s) listed above.\n' "$expected_name" >&2
    else
      printf '  Delete all but one of the files listed above.\n' >&2
    fi
    die "Duplicate mod jars found in $MODS_DIR."
  fi
done

# --- H.2: remove our own tier-swap artifacts before the manifest check. A jar whose
# filename is named by the FULL manifest (any tier) but is NOT active for this tier
# (e.g. a build left behind by a tier switch) is our own artifact and is safe to
# delete. This must not touch any file the manifest does not name; H.1 above
# already aborted on any duplicate a user introduced by hand. ---
for f in "$MODS_DIR"/*.jar; do
  [ -f "$f" ] || continue
  bn="$(basename "$f")"
  if grep -qxF "$bn" "$ALL_MODS_FILES" && ! grep -qxF "$bn" "$ACTIVE_MODS_FILES"; then
    log "Removing tier-swap artifact jar: $bn (named by the manifest but not active for '$TIER')"
    rm -f "$f"
  fi
done

# --- H.3: every active mod jar exists at mods/<filename> with the right hash ---
MISSING=""
MISMATCHED=""
VERIFIED_COUNT=0

while IFS="$TAB" read -r fname fsha furl fdest fprefix; do
  [ "$fdest" = "mods" ] || continue
  target="$MODS_DIR/$fname"
  if [ ! -f "$target" ]; then
    MISSING="$MISSING $fname"
    continue
  fi
  actual="$(sha256_of "$target")"
  if [ "$actual" != "$fsha" ]; then
    MISMATCHED="$MISMATCHED $fname(expected=$fsha,got=$actual)"
    continue
  fi
  VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
done < "$ACTIVE_ROWS"

if [ -n "$MISSING" ] || [ -n "$MISMATCHED" ]; then
  [ -z "$MISSING" ] || printf 'ERROR: Missing mod jars in %s:%s\n' "$MODS_DIR" "$MISSING" >&2
  [ -z "$MISMATCHED" ] || printf 'ERROR: Mismatched mod jars in %s:%s\n' "$MODS_DIR" "$MISMATCHED" >&2
  die "Mod jar verification failed. See errors above."
fi

# --- H.4: every active non-mod file (resourcepack, and shaderpack for shader tiers)
# exists at <gamedir>/<dest>/<filename> with the right hash (same SHA-256 gate). ---
NONMODS_MISSING=""
NONMODS_MISMATCHED=""
NONMODS_VERIFIED=0
while IFS="$TAB" read -r fname fsha furl fdest fprefix; do
  case "$fdest" in mods) continue ;; esac
  ntarget="$TARGET_DIR/$fdest/$fname"
  if [ ! -f "$ntarget" ]; then
    NONMODS_MISSING="$NONMODS_MISSING $fdest/$fname"
    continue
  fi
  nactual="$(sha256_of "$ntarget")"
  if [ "$nactual" != "$fsha" ]; then
    NONMODS_MISMATCHED="$NONMODS_MISMATCHED $fdest/$fname(expected=$fsha,got=$nactual)"
    continue
  fi
  NONMODS_VERIFIED=$((NONMODS_VERIFIED + 1))
done < "$ACTIVE_ROWS"

if [ -n "$NONMODS_MISSING" ] || [ -n "$NONMODS_MISMATCHED" ]; then
  [ -z "$NONMODS_MISSING" ] || printf 'ERROR: Missing files in %s:%s\n' "$TARGET_DIR" "$NONMODS_MISSING" >&2
  [ -z "$NONMODS_MISMATCHED" ] || printf 'ERROR: Mismatched files in %s:%s\n' "$TARGET_DIR" "$NONMODS_MISMATCHED" >&2
  die "Resourcepack/shaderpack verification failed. See errors above."
fi

log "All ${EXPECTED_JAR_COUNT} mod jars + ${NONMODS_VERIFIED} other file(s) verified."

# --- I: final summary ---
log "Install complete."
log "Game directory: $TARGET_DIR"
log "Select this version in your launcher: $PROFILE_ID"
log "Verified jar count: $VERIFIED_COUNT / $EXPECTED_JAR_COUNT (+ $NONMODS_VERIFIED other file(s))"
if [ "$HAS_SHADERS" = "1" ]; then
  log "Tier applied: $TIER (RAM -Xmx${T_XMX}; shaders ON: Iris + Sodium 0.8.7 + Complementary $T_COMP_PROFILE)."
else
  log "Tier applied: $TIER (RAM -Xmx${T_XMX}; no shaders -- no shaderpack row is active for this tier)."
fi
log "Reminder: do not add OptiFine — Sodium is included."

exit 0
