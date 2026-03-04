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
./release.sh              # full release, both platforms
./release.sh --dry-run    # preview everything, upload nothing
./release.sh --android    # Android only
./release.sh --ios        # iOS only
```

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
