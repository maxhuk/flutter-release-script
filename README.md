# Flutter Release Script

Drop `release.sh` and `release.config` into your Flutter project root. Edit the config once. Then:

```bash
# 1. Bump version in pubspec.yaml yourself
# 2. Update app-whats-new.md if needed (or leave empty to reuse previous)
# 3. Run:
./release.sh
```

That's it. The script reads the version from `pubspec.yaml`, resolves changelogs from your What's New file, builds both platforms, uploads to both stores with localized changelogs, submits for review, and git-tags.

## Flags

```
./release.sh                # full release, both platforms
./release.sh --dry-run      # preview everything, upload nothing
./release.sh --android      # Android only
./release.sh --ios          # iOS only
./release.sh --metadata     # also push listing text
./release.sh --screenshots  # also push screenshots
./release.sh --all          # both of the above
```

## Store listing (optional)

By default a release touches the binary and the changelogs, and nothing else —
your name, description, keywords and screenshots stay exactly as they are.

To manage those from the repo too, point `LISTING_DIR` at a tree of one folder
per `LANGUAGE_MAP` file tag:

```
metadata/
  en-US/
    name.txt         subtitle.txt           keywords.txt
    description.txt  short_description.txt  promotional_text.txt
    eula.txt         screenshots/01.png …
  uk/
    …
```

Then `./release.sh --all` sends it. Every file is optional — one you don't
provide isn't sent, and the store keeps what it has, so a tree with only
`description.txt` in it is perfectly valid.

| Source file | App Store | Google Play |
|---|---|---|
| `name.txt` | name | title |
| `subtitle.txt` | subtitle | — |
| `keywords.txt` | keywords | — |
| `short_description.txt` | — | short description |
| `description.txt` | description | full description |
| `promotional_text.txt` | promotional text | — |
| `eula.txt` | appended to the description | — |
| `screenshots/*.png` | screenshots | phone screenshots |

`eula.txt` exists because Apple wants a licence link in the description and
Play has no equivalent field — keeping it separate means one shared
`description.txt` instead of two near-identical copies that drift apart.

Screenshots upload in **filename order**, so number them (`01.png`, `02.png`,
…). Locales that should show another locale's artwork are declared rather than
duplicated:

```bash
SCREENSHOT_ALIAS=( "ru-RU:uk" )
```

Field lengths are checked against the store maxima before the build starts, in
characters rather than bytes, and an over-long field stops the run.

Two things worth knowing before your first `--all`:

- **Both stores replace rather than merge.** Listing text is overwritten and
  screenshot sets are cleared and re-sent. Seed the tree by downloading what is
  already live (`fastlane deliver download_metadata`, `fastlane supply init`)
  and your first push changes nothing.
- **On iOS this only works during a release.** Name, subtitle, keywords,
  description and screenshots all attach to an app version, so they need one in
  an editable state — which is exactly what a release run creates. Play accepts
  them any time.

The feature graphic and app icon are never uploaded; those are set once in the
console.

## What's New file format

The script reads your existing changelog format — version headers with `<lang>` blocks:

```markdown
# 3.5.6 (10.03.2026)

<uk>
Your Ukrainian changelog here.
</uk>
<en-US>
Your English changelog here.
</en-US>

# 3.5.5 (08.02.2026)

# 3.5.4 (29.01.2026)
```

Empty versions (no lang blocks) automatically reuse the most recent previous text for each language. Platform-specific subsections (`## iOS` / `## Android`) are also supported for the rare case where changelogs differ per platform.

## Prerequisites

- **Fastlane**: `brew install fastlane`
- **Google Play**: service account JSON key ([docs](https://docs.fastlane.tools/actions/supply/))
- **App Store Connect**: API key `.p8` file ([docs](https://docs.fastlane.tools/app-store-connect-api/))

## Config

Edit `release.config` — it has comments explaining each field. The key things:

- `ANDROID_PACKAGE` / `IOS_BUNDLE_ID` — your app identifiers
- `WHATS_NEW_FILE` — path to your changelog markdown
- `LANGUAGE_MAP` — maps `<lang>` tags to store locale codes (format: `file_tag:play_locale:app_store_locale`)
- `PLAY_STORE_KEY` / `ASC_KEY_*` — paths to your store credentials
- `FLUTTER_BUILD_FLAGS` — e.g. `"--flavor prod --dart-define=ENV=production"`

Add `keys/` to your `.gitignore`.
