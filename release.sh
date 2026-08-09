#!/usr/bin/env bash
set -euo pipefail

RELEASE_SCRIPT_VERSION="1.1.0"
RELEASE_SCRIPT_REPO="https://raw.githubusercontent.com/maxhuk/flutter-release-script/main/release.sh"

# ═════════════════════════════════════════════════════════════
#  Flutter Release Script  (fire-and-forget edition)
#
#  Reads the version from pubspec.yaml and changelogs from your
#  What's New markdown file, then builds, uploads, and submits
#  for review on both stores. No interaction required.
#
#  Usage:   ./release.sh              (full release, both platforms)
#           ./release.sh --dry-run    (preview without uploading)
#           ./release.sh --android    (Android only)
#           ./release.sh --ios        (iOS only)
#           ./release.sh --all        (also push listing text + screenshots)
# ═════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/release.config"
DRY_RUN=false
NO_UPDATE=false
PLATFORM="both"  # "both", "android", "ios"
PUSH_METADATA=false
PUSH_SCREENSHOTS=false

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
DIM='\033[2m'; NC='\033[0m'

banner() {
  local ver_label="v${RELEASE_SCRIPT_VERSION}"
  local pad=$(( 24 - ${#ver_label} ))
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${BOLD}🚀 Flutter Release Tool${NC}  ${DIM}${ver_label}${NC}$(printf '%*s' "$pad" '')${BLUE}║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
}

step()    { echo ""; echo -e "${CYAN}── $1 ──${NC}"; echo ""; }
info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✔${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail()    { echo -e "  ${RED}✘${NC}  $1"; exit 1; }

# ── Version helpers ───────────────────────────────────────────
version_gt() {
  local IFS=.
  local i a=($1) b=($2)
  for ((i = 0; i < 3; i++)); do
    if (( ${a[i]:-0} > ${b[i]:-0} )); then return 0; fi
    if (( ${a[i]:-0} < ${b[i]:-0} )); then return 1; fi
  done
  return 1
}

auto_update() {
  local script_path="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
  local tmpfile
  tmpfile=$(mktemp)

  curl -fsSL --max-time 10 "$RELEASE_SCRIPT_REPO" > "$tmpfile" 2>/dev/null \
    || { rm -f "$tmpfile"; return; }

  head -1 "$tmpfile" | grep -q '^#!/usr/bin/env bash' || { rm -f "$tmpfile"; return; }
  grep -q '^RELEASE_SCRIPT_VERSION=' "$tmpfile"       || { rm -f "$tmpfile"; return; }

  local remote_ver
  remote_ver=$(grep -m1 '^RELEASE_SCRIPT_VERSION=' "$tmpfile" | sed 's/.*="//;s/"//')

  if ! version_gt "$remote_ver" "$RELEASE_SCRIPT_VERSION"; then
    rm -f "$tmpfile"
    return
  fi

  mv "$tmpfile" "$script_path"
  chmod +x "$script_path"
  success "Auto-updated: ${BOLD}v${RELEASE_SCRIPT_VERSION}${NC} ${GREEN}→${NC} ${BOLD}v${remote_ver}${NC}"
  exec "$script_path" "$@"
}

cleanup() {
  rm -rf ".release_metadata"
  # Guarded: the trap is armed long before ASC_API_KEY_JSON is assigned, so any
  # early exit (--version, a failed check) would otherwise die in the trap under
  # `set -u` and bury the real message.
  [[ -n "${ASC_API_KEY_JSON:-}" ]] && rm -f "$ASC_API_KEY_JSON"
  return 0
}
trap cleanup EXIT

# ── Parse CLI flags ──────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --android)  PLATFORM="android" ;;
    --ios)      PLATFORM="ios" ;;
    --no-update)  NO_UPDATE=true ;;
    --metadata)     PUSH_METADATA=true ;;
    --screenshots)  PUSH_SCREENSHOTS=true ;;
    --all)          PUSH_METADATA=true; PUSH_SCREENSHOTS=true ;;
    --version|-v)
      echo "release.sh v${RELEASE_SCRIPT_VERSION}"
      exit 0 ;;
    --help|-h)
      echo "Usage: ./release.sh [--dry-run] [--android|--ios] [--metadata] [--screenshots] [--all] [--no-update]"
      echo "  --dry-run       Walk through everything but skip uploads"
      echo "  --android       Only build & release Android"
      echo "  --ios           Only build & release iOS"
      echo "  --metadata      Also push store listing text (name, description, keywords…)"
      echo "  --screenshots   Also push store screenshots"
      echo "  --all           --metadata plus --screenshots"
      echo "  --no-update     Skip auto-update check"
      echo "  --version       Print script version and exit"
      exit 0 ;;
    *) fail "Unknown flag: $arg  (try --help)" ;;
  esac
done

# ── Load config ──────────────────────────────────────────────
[[ ! -f "$CONFIG_FILE" ]] && fail "Config not found at ${CONFIG_FILE}"
source "$CONFIG_FILE"

if $PUSH_METADATA || $PUSH_SCREENSHOTS; then
  [[ -z "${LISTING_DIR:-}" ]] && fail "--metadata / --screenshots need LISTING_DIR set in ${CONFIG_FILE}"
  [[ ! -d "$LISTING_DIR"  ]] && fail "LISTING_DIR not found: ${LISTING_DIR}"
fi

banner
$DRY_RUN && warn "DRY RUN — nothing will be uploaded or submitted."

! $NO_UPDATE && auto_update "$@"

# ══════════════════════════════════════════════════════════════
#  READ VERSION
# ══════════════════════════════════════════════════════════════

step "Reading version from ${PUBSPEC}"
[[ ! -f "$PUBSPEC" ]] && fail "${PUBSPEC} not found. Run this from your project root."

VERSION_LINE=$(grep -E '^version:[[:space:]]' "$PUBSPEC")
VERSION=$(echo "$VERSION_LINE" | sed -E 's/version:[[:space:]]*//;s/\+.*//' | xargs)
BUILD_NUMBER=$(echo "$VERSION_LINE" | sed -E 's/.*\+//' | xargs)

info "Version: ${BOLD}${VERSION}+${BUILD_NUMBER}${NC}"
info "Platform: ${BOLD}${PLATFORM}${NC}"

# ══════════════════════════════════════════════════════════════
#  CHANGELOG PARSER (embedded Python)
# ══════════════════════════════════════════════════════════════
#
# Parses the What's New markdown file. Takes a platform arg
# ("android", "ios", or "both") so that platform-specific
# ## iOS / ## Android subsections are handled correctly.
#
# When a version has no <lang> blocks, the parser walks backwards
# through older versions until it finds text for that language.

resolve_changelogs() {
  local platform_arg="$1"
  python3 - "$WHATS_NEW_FILE" "$VERSION" "$platform_arg" <<'PYEOF'
import sys, re, json

whats_new_file = sys.argv[1]
target_version = sys.argv[2]
target_platform = sys.argv[3]

with open(whats_new_file, "r", encoding="utf-8") as f:
    content = f.read()

# Split file into (version, body) pairs
version_pattern = re.compile(r'^#\s+([\d]+\.[\d]+(?:\.[\d]+)?)\b.*$', re.MULTILINE)
splits = list(version_pattern.finditer(content))

versions = []
for i, m in enumerate(splits):
    ver = m.group(1)
    start = m.end()
    end = splits[i + 1].start() if i + 1 < len(splits) else len(content)
    versions.append((ver, content[start:end].strip()))

def extract_lang_blocks(body, platform):
    """Extract <lang>...</lang> blocks, respecting ## iOS/Android subsections."""
    text_to_search = body

    if platform not in ("both", ""):
        platform_sections = list(re.finditer(
            r'^##\s+(iOS|Android)\s*$', body, re.MULTILINE | re.IGNORECASE
        ))
        for i, ps in enumerate(platform_sections):
            if ps.group(1).lower() == platform:
                start = ps.end()
                end = platform_sections[i+1].start() if i+1 < len(platform_sections) else len(body)
                text_to_search = body[start:end]
                break

    result = {}
    for m in re.finditer(r'<([a-zA-Z][a-zA-Z0-9_-]*)>\s*\n(.*?)\n\s*</\1>', text_to_search, re.DOTALL):
        text = m.group(2).strip()
        if text:
            result[m.group(1)] = text
    return result

# Collect all language tags used anywhere in the file
all_lang_tags = set()
for _, body in versions:
    all_lang_tags.update(extract_lang_blocks(body, "both").keys())

# Find the target version's index
target_idx = 0
for i, (ver, _) in enumerate(versions):
    if ver == target_version:
        target_idx = i
        break

# For each language, walk forward (= backwards in time) until we find text
changelogs = {}
for lang in all_lang_tags:
    for i in range(target_idx, len(versions)):
        blocks = extract_lang_blocks(versions[i][1], target_platform)
        if lang in blocks:
            changelogs[lang] = blocks[lang]
            if i != target_idx:
                changelogs[f"_src_{lang}"] = versions[i][0]
            break

print(json.dumps(changelogs, ensure_ascii=False))
PYEOF
}

# Helpers to read from the JSON blobs
changelog_text() {
  echo "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2',''))"
}

changelog_source() {
  echo "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_src_$2',''))"
}

# ══════════════════════════════════════════════════════════════
#  STORE LISTING  (--metadata / --screenshots)
# ══════════════════════════════════════════════════════════════
#
# Off unless asked for. Set LISTING_DIR in release.config to a tree of
#
#   <LISTING_DIR>/<file_tag>/name.txt          subtitle.txt
#                            keywords.txt      short_description.txt
#                            description.txt   promotional_text.txt
#                            eula.txt          screenshots/*.png
#
# where <file_tag> is the first field of a LANGUAGE_MAP entry, so the folder
# names match the tags the What's New file already uses. Every file is
# optional and a missing one is simply not sent — fastlane leaves a field it
# receives no file for untouched, which is what makes partial trees safe.
#
# One source file can feed differently-named fields in the two stores
# (name -> title, description -> full_description); that mapping lives here so
# the tree stays store-neutral.
#
# eula.txt is appended to the iOS description. Apple wants a licence link in
# the description, Google Play has no such field and must not carry an
# apple.com URL — keeping it separate lets description.txt stay one shared body
# instead of two near-identical copies that drift.

copy_if_present() {
  [[ -f "$1" ]] || return 0
  cp "$1" "$2"
}

# Locales that ship another locale's artwork. SCREENSHOT_ALIAS=( "ru-RU:uk" )
# reads as "ru-RU uses uk's screenshots" — for a listing whose app UI is the
# other locale's anyway, a duplicate set would only be one more thing to keep
# in step.
screenshot_source_tag() {
  local tag="$1" entry from to
  if [[ -n "${SCREENSHOT_ALIAS+x}" ]]; then
    for entry in "${SCREENSHOT_ALIAS[@]}"; do
      IFS=':' read -r from to <<< "$entry"
      [[ "$from" == "$tag" ]] && { echo "$to"; return; }
    done
  fi
  echo "$tag"
}

assemble_ios_listing() {
  local dest="$1" entry tag asc src field
  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r tag _ asc <<< "$entry"
    src="${LISTING_DIR}/${tag}"
    [[ -d "$src" ]] || continue
    mkdir -p "${dest}/${asc}"

    for field in name subtitle keywords promotional_text; do
      copy_if_present "${src}/${field}.txt" "${dest}/${asc}/${field}.txt"
    done

    if [[ -f "${src}/description.txt" ]]; then
      if [[ -f "${src}/eula.txt" ]]; then
        { cat "${src}/description.txt"; echo; cat "${src}/eula.txt"; } \
          > "${dest}/${asc}/description.txt"
      else
        cp "${src}/description.txt" "${dest}/${asc}/description.txt"
      fi
    fi
  done
}

assemble_android_listing() {
  local dest="$1" entry tag play src
  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r tag play _ <<< "$entry"
    src="${LISTING_DIR}/${tag}"
    [[ -d "$src" ]] || continue
    mkdir -p "${dest}/${play}"

    copy_if_present "${src}/name.txt"              "${dest}/${play}/title.txt"
    copy_if_present "${src}/short_description.txt" "${dest}/${play}/short_description.txt"
    copy_if_present "${src}/description.txt"       "${dest}/${play}/full_description.txt"
  done
}

# deliver takes screenshots from their own root, keyed by locale; supply wants
# them inside the metadata tree it is already reading.
assemble_ios_screenshots() {
  local dest="$1" entry tag asc src
  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r tag _ asc <<< "$entry"
    src="${LISTING_DIR}/$(screenshot_source_tag "$tag")/screenshots"
    [[ -d "$src" ]] || continue
    mkdir -p "${dest}/${asc}"
    cp "$src"/*.png "${dest}/${asc}/"
  done
}

assemble_android_screenshots() {
  local dest="$1" entry tag play src
  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r tag play _ <<< "$entry"
    src="${LISTING_DIR}/$(screenshot_source_tag "$tag")/screenshots"
    [[ -d "$src" ]] || continue
    mkdir -p "${dest}/${play}/images/phoneScreenshots"
    cp "$src"/*.png "${dest}/${play}/images/phoneScreenshots/"
  done
}

# Field lengths in characters against the store limits. Not bytes: every limit
# below is a character count, and a Cyrillic or CJK listing is roughly twice as
# many bytes as characters — `wc -c` would report a compliant field as double
# its length. Prints "field:len" per field, then a second line naming the ones
# over their limit.
listing_field_report() {
  python3 - "$1" <<'PYEOF'
import pathlib, sys

# App Store / Play maxima. description covers Play's full description too; it
# is the smaller of the two allowances.
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "short_description": 80,
          "promotional_text": 170, "description": 4000}

folder = pathlib.Path(sys.argv[1])
read = lambda p: p.read_text(encoding="utf-8").rstrip("\n")

fields, over = [], []
eula = folder / "eula.txt"
for path in sorted(folder.glob("*.txt")):
    text = read(path)
    # eula.txt ships appended to the description, so it is the sum that has to
    # fit — checking the body alone would pass a listing the store rejects.
    if path.stem == "description" and eula.exists():
        text = text + "\n\n" + read(eula)
    limit = LIMITS.get(path.stem)
    if limit and len(text) > limit:
        fields.append(f"{path.stem}:{len(text)}/{limit}")
        over.append(path.stem)
    else:
        fields.append(f"{path.stem}:{len(text)}")

print(" ".join(fields))
print(" ".join(over))
PYEOF
}

# What a run would send, per locale — the only preview there is for the text,
# since neither store offers a diff before you commit to one.
show_listing_plan() {
  local root="$1" entry tag locale src fields over
  local violations=""
  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r tag play asc <<< "$entry"
    [[ "$root" == "android" ]] && locale="$play" || locale="$asc"
    src="${LISTING_DIR}/${tag}"
    [[ -d "$src" ]] || { warn "${tag} — no listing folder"; continue; }

    { read -r fields; read -r over; } < <(listing_field_report "$src")
    info "${BOLD}${tag}${NC} → ${locale}"
    echo -e "    ${DIM}${fields}${NC}"
    [[ -n "$over" ]] && violations+="${tag}: ${over}  "

    if $PUSH_SCREENSHOTS; then
      local shots_tag shots_dir count
      shots_tag=$(screenshot_source_tag "$tag")
      shots_dir="${LISTING_DIR}/${shots_tag}/screenshots"
      if [[ -d "$shots_dir" ]]; then
        count=$(find "$shots_dir" -name '*.png' | wc -l | tr -d ' ')
        if [[ "$shots_tag" == "$tag" ]]; then
          echo -e "    ${DIM}${count} screenshot(s)${NC}"
        else
          echo -e "    ${DIM}${count} screenshot(s) — reusing ${shots_tag}${NC}"
        fi
      else
        warn "${tag} — no screenshots"
      fi
    fi
  done

  # Stop here rather than at the store: an over-length field is rejected on
  # upload, after the build has already run.
  [[ -n "$violations" ]] && fail "Over the store limit — ${violations}"
  return 0
}

# ══════════════════════════════════════════════════════════════
#  RESOLVE & DISPLAY CHANGELOGS
# ══════════════════════════════════════════════════════════════

step "Resolving changelogs from ${WHATS_NEW_FILE}"
[[ ! -f "$WHATS_NEW_FILE" ]] && fail "${WHATS_NEW_FILE} not found."

# Pre-compute changelogs per platform
CL_ANDROID=""
CL_IOS=""
if [[ "$PLATFORM" == "both" || "$PLATFORM" == "android" ]]; then
  CL_ANDROID=$(resolve_changelogs "android")
fi
if [[ "$PLATFORM" == "both" || "$PLATFORM" == "ios" ]]; then
  CL_IOS=$(resolve_changelogs "ios")
fi

# Display summary
CL_DISPLAY="${CL_ANDROID:-${CL_IOS}}"
for entry in "${LANGUAGE_MAP[@]}"; do
  IFS=':' read -r file_tag _ _ <<< "$entry"
  TEXT=$(changelog_text "$CL_DISPLAY" "$file_tag")
  SRC=$(changelog_source "$CL_DISPLAY" "$file_tag")

  if [[ -n "$TEXT" ]]; then
    if [[ -n "$SRC" ]]; then
      info "${BOLD}${file_tag}${NC} — reusing from v${SRC}"
    else
      info "${BOLD}${file_tag}${NC} — found"
    fi
    echo -e "    ${DIM}$(echo "$TEXT" | head -1)${NC}"
  else
    warn "${file_tag} — no changelog found"
  fi
done

if $PUSH_METADATA || $PUSH_SCREENSHOTS; then
  step "Resolving store listing from ${LISTING_DIR}"
  show_listing_plan "$([[ "$PLATFORM" == "android" ]] && echo android || echo ios)"
  warn "Both stores replace what is there — listing text is overwritten, and screenshots are cleared and re-sent."
fi

# ══════════════════════════════════════════════════════════════
#  FLUTTER BUILD
# ══════════════════════════════════════════════════════════════

step "Building"

flutter clean > /dev/null 2>&1
success "flutter clean"

ANDROID_ARTIFACT=""
IOS_ARTIFACT=""

if [[ "$PLATFORM" == "both" || "$PLATFORM" == "android" ]]; then
  info "flutter build ${ANDROID_BUILD_TYPE}..."
  # shellcheck disable=SC2086
  flutter build "$ANDROID_BUILD_TYPE" $FLUTTER_BUILD_FLAGS

  if [[ "$ANDROID_BUILD_TYPE" == "appbundle" ]]; then
    ANDROID_ARTIFACT=$(find build/app/outputs/bundle -name '*.aab' 2>/dev/null | head -1)
  else
    ANDROID_ARTIFACT=$(find build/app/outputs/flutter-apk -name '*.apk' 2>/dev/null | head -1)
  fi
  [[ -z "$ANDROID_ARTIFACT" ]] && fail "Android artifact not found!"
  success "Android: ${ANDROID_ARTIFACT}"
fi

if [[ "$PLATFORM" == "both" || "$PLATFORM" == "ios" ]]; then
  info "flutter build ipa..."
  # shellcheck disable=SC2086
  flutter build ipa $FLUTTER_BUILD_FLAGS

  IOS_ARTIFACT=$(find build/ios/ipa -name '*.ipa' 2>/dev/null | head -1)
  [[ -z "$IOS_ARTIFACT" ]] && fail "iOS artifact not found!"
  success "iOS: ${IOS_ARTIFACT}"
fi

# ══════════════════════════════════════════════════════════════
#  UPLOAD TO GOOGLE PLAY
# ══════════════════════════════════════════════════════════════

upload_android() {
  step "Uploading to Google Play (${PLAY_STORE_TRACK})"

  local metadata_dir=".release_metadata/android"
  rm -rf "$metadata_dir"

  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r file_tag play_locale _ <<< "$entry"
    local text
    text=$(changelog_text "$CL_ANDROID" "$file_tag")
    if [[ -n "$text" ]]; then
      mkdir -p "${metadata_dir}/${play_locale}/changelogs"
      echo "$text" > "${metadata_dir}/${play_locale}/changelogs/${BUILD_NUMBER}.txt"
    fi
  done

  local skip_metadata=true skip_screenshots=true
  if $PUSH_METADATA; then
    assemble_android_listing "$metadata_dir"
    skip_metadata=false
  fi
  if $PUSH_SCREENSHOTS; then
    assemble_android_screenshots "$metadata_dir"
    skip_screenshots=false
  fi

  if $DRY_RUN; then
    warn "[DRY RUN] Would upload ${ANDROID_ARTIFACT}"
    find "$metadata_dir" -path '*/changelogs/*' -name '*.txt' | while read -r f; do
      warn "[DRY RUN] Changelog: $f ($(wc -c < "$f" | tr -d ' ') chars)"
    done
    if $PUSH_METADATA || $PUSH_SCREENSHOTS; then
      warn "[DRY RUN] Listing tree:"
      find "$metadata_dir" -type f -not -path '*/changelogs/*' | sort | while read -r f; do
        warn "[DRY RUN]   ${f#"$metadata_dir"/}"
      done
    fi
    return
  fi

  # skip_upload_images stays on: the feature graphic and icon are set once in
  # the console and are not part of the per-release spread.
  fastlane supply \
    --aab "$ANDROID_ARTIFACT" \
    --track "$PLAY_STORE_TRACK" \
    --release_status "completed" \
    --package_name "$ANDROID_PACKAGE" \
    --json_key "$PLAY_STORE_KEY" \
    --skip_upload_metadata "$skip_metadata" \
    --skip_upload_images true \
    --skip_upload_screenshots "$skip_screenshots" \
    --metadata_path "$metadata_dir"

  success "Android: uploaded + changelogs set"
  $PUSH_METADATA    && success "Android: listing text updated"
  $PUSH_SCREENSHOTS && success "Android: screenshots replaced"
  return 0
}

# ══════════════════════════════════════════════════════════════
#  UPLOAD TO APP STORE
# ══════════════════════════════════════════════════════════════

ASC_FLAGS=()
ASC_API_KEY_JSON=""

build_asc_flags() {
  ASC_FLAGS=()
  if [[ -n "${ASC_KEY_ID}" && -n "${ASC_ISSUER_ID}" && -f "${ASC_KEY_FILE}" ]]; then
    if [[ -z "$ASC_API_KEY_JSON" ]]; then
      ASC_API_KEY_JSON=$(mktemp "${TMPDIR:-/tmp}/asc_api_key.XXXXXX.json")
      python3 -c "
import json, sys
with open(sys.argv[3]) as f:
    key = f.read()
print(json.dumps({'key_id': sys.argv[1], 'issuer_id': sys.argv[2], 'key': key, 'in_house': False}))
" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_FILE" > "$ASC_API_KEY_JSON"
    fi
    ASC_FLAGS+=(--api_key_path "$ASC_API_KEY_JSON")
  fi
}

upload_ios() {
  step "Uploading to App Store Connect"
  build_asc_flags

  local metadata_dir=".release_metadata/ios"
  rm -rf "$metadata_dir"

  for entry in "${LANGUAGE_MAP[@]}"; do
    IFS=':' read -r file_tag _ ios_locale <<< "$entry"
    local text
    text=$(changelog_text "$CL_IOS" "$file_tag")
    if [[ -n "$text" ]]; then
      mkdir -p "${metadata_dir}/${ios_locale}"
      echo "$text" > "${metadata_dir}/${ios_locale}/release_notes.txt"
    fi
  done

  local screenshots_dir=".release_metadata/ios_screenshots"
  local skip_screenshots=true
  local shot_flags=()
  $PUSH_METADATA && assemble_ios_listing "$metadata_dir"
  if $PUSH_SCREENSHOTS; then
    assemble_ios_screenshots "$screenshots_dir"
    skip_screenshots=false
    # deliver appends without this and the ordering guarantee — which is the
    # whole point of the numbered filenames — is lost.
    shot_flags+=(--screenshots_path "$screenshots_dir" --overwrite_screenshots true)
  fi

  if $DRY_RUN; then
    warn "[DRY RUN] Would upload ${IOS_ARTIFACT}"
    find "$metadata_dir" -name '*.txt' | sort | while read -r f; do
      warn "[DRY RUN] ${f#"$metadata_dir"/} ($(wc -c < "$f" | tr -d ' ') chars)"
    done
    if $PUSH_SCREENSHOTS; then
      find "$screenshots_dir" -name '*.png' | sort | while read -r f; do
        warn "[DRY RUN] ${f#"$screenshots_dir"/}"
      done
    fi
    return
  fi

  fastlane pilot upload \
    --ipa "$IOS_ARTIFACT" \
    --app_identifier "$IOS_BUNDLE_ID" \
    --skip_waiting_for_build_processing true \
    "${ASC_FLAGS[@]}"

  success "IPA uploaded"

  fastlane deliver \
    --app_identifier "$IOS_BUNDLE_ID" \
    --app_version "$VERSION" \
    --skip_binary_upload true \
    --skip_screenshots "$skip_screenshots" \
    --skip_metadata false \
    --precheck_include_in_app_purchases false \
    --metadata_path "$metadata_dir" \
    --force true \
    ${shot_flags[@]+"${shot_flags[@]}"} \
    "${ASC_FLAGS[@]}"

  success "App Store changelogs set"
  $PUSH_METADATA    && success "App Store: listing text updated"
  $PUSH_SCREENSHOTS && success "App Store: screenshots replaced"
  return 0
}

# ── Run uploads ──────────────────────────────────────────────

if [[ "$PLATFORM" == "both" || "$PLATFORM" == "android" ]]; then
  upload_android
fi

if [[ "$PLATFORM" == "both" || "$PLATFORM" == "ios" ]]; then
  upload_ios
fi

# ══════════════════════════════════════════════════════════════
#  SUBMIT FOR REVIEW
# ══════════════════════════════════════════════════════════════

step "Submitting for review"

if $DRY_RUN; then
  warn "[DRY RUN] Skipping review submission."
else
  if [[ "$PLATFORM" == "both" || "$PLATFORM" == "android" ]]; then
    if [[ "$PLAY_STORE_TRACK" == "production" ]]; then
      success "Android: auto-submitted (production track)"
    else
      fastlane supply \
        --track "$PLAY_STORE_TRACK" \
        --track_promote_to production \
        --track_promote_release_status completed \
        --package_name "$ANDROID_PACKAGE" \
        --json_key "$PLAY_STORE_KEY" \
        --skip_upload_apk true \
        --skip_upload_aab true \
        --skip_upload_metadata true \
        --skip_upload_changelogs true \
        --skip_upload_images true \
        --skip_upload_screenshots true
      success "Android: promoted to production"
    fi
  fi

  if [[ "$PLATFORM" == "both" || "$PLATFORM" == "ios" ]]; then
    build_asc_flags

    info "iOS: waiting for build processing & submitting..."
    fastlane deliver \
      --app_identifier "$IOS_BUNDLE_ID" \
      --app_version "$VERSION" \
      --submit_for_review true \
      --automatic_release false \
      --skip_binary_upload true \
      --skip_screenshots true \
      --skip_metadata true \
      --precheck_include_in_app_purchases false \
      --metadata_path ".release_metadata/ios" \
      --force true \
      "${ASC_FLAGS[@]}"

    success "iOS: submitted for review"
  fi
fi

cleanup

# ══════════════════════════════════════════════════════════════
#  GIT TAG
# ══════════════════════════════════════════════════════════════

if ${GIT_TAG_RELEASES:-false} && ! $DRY_RUN; then
  step "Git tag"

  TAG="v${VERSION}+${BUILD_NUMBER}"
  git add "$PUBSPEC" "$WHATS_NEW_FILE" 2>/dev/null || true
  git commit -m "release: ${VERSION}+${BUILD_NUMBER}" 2>/dev/null || true
  git tag -a "$TAG" -m "Release ${VERSION}+${BUILD_NUMBER}"
  success "Tagged ${TAG}"

  if ${GIT_PUSH_TAG:-false}; then
    git push && git push --tags
    success "Pushed"
  fi
fi

# ══════════════════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}🎉 Done!  ${VERSION}+${BUILD_NUMBER}${NC}$(printf '%*s' $((28 - ${#VERSION} - ${#BUILD_NUMBER})) '')${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
$DRY_RUN && echo -e "  ${YELLOW}(dry run — nothing was uploaded)${NC}" && echo ""
