[English](local-release.md) | [简体中文](local-release.zh-CN.md)

# Local build and publication

Use this path when the maintainer authorizes local publication and hosted Actions is unavailable. It preserves the existing application identities and signing keys. Record local evidence explicitly; do not mark unavailable GitHub checks successful or relax repository rules. See [automatic updates](automatic-updates.md) for trust and recovery boundaries.

## Prepare and build

Verify `git status`, the `displayweave` remote, the highest published build number, Xcode/XcodeGen, the Android SDK and Java, pnpm, and available signing material. Choose a new immutable version/build; never replace an existing public tag or asset. For p8 the version is `0.2.1-p8`, build `15`.

The Android keystore stays outside Git at `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`; the existing Keychain service is `app.displayweave.android-preview-signing`, account/alias `displayweave-preview`. The packaging script reads its password without printing it. Sparkle uses Keychain account `ed25519`. Run the existing Sparkle `generate_keys -p` only to inspect its public key; it must match `N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=`. Stop on a mismatch instead of generating a replacement.

Run from the repository root:

```bash
python3 -m venv build/local-release-venv
build/local-release-venv/bin/python -m pip install -r tools/dmg-requirements.txt
export PATH="$PWD/build/local-release-venv/bin:$PATH"
export DISPLAYWEAVE_VERSION_NAME=0.2.1-p8
export DISPLAYWEAVE_BUILD_NUMBER=15
export DISPLAYWEAVE_UPDATE_RELEASE=1
export DISPLAYWEAVE_RELEASE_TAG=v0.2.1-p8
export DISPLAYWEAVE_OUTPUT_DIR="$PWD/build/release-p8"
./tools/package-preview-0.1.sh
```

This generates the Xcode project, builds the ad-hoc Mac app and guided DMG/ZIP, builds unsigned device iOS, and runs Android tests plus the signed Release build. Do not run another packaging invocation against the same derived-data directories concurrently. Do not enable shell tracing or export private keys to files.

## Generate and verify feeds

```bash
export DISPLAYWEAVE_RELEASE_BASE_URL=https://downloads.urlget.cyou/releases
export DISPLAYWEAVE_RELEASE_FALLBACK_BASE_URL=https://github.com/chenyuhao0628/displayweave/releases/download
export DISPLAYWEAVE_PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export DISPLAYWEAVE_ANDROID_APK="$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-Android.apk"
export DISPLAYWEAVE_ANDROID_FEED_OUTPUT="$DISPLAYWEAVE_OUTPUT_DIR/android-update.json"
./tools/generate-android-update-manifest.sh
```

Copy only the new Mac ZIP into an empty appcast input directory. Run the bundled `build/preview-0.1-mac-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast` with `--account ed25519`, `--versions 15`, `--download-url-prefix https://downloads.urlget.cyou/releases/v0.2.1-p8/`, `--link https://github.com/chenyuhao0628/displayweave`, `-o "$DISPLAYWEAVE_OUTPUT_DIR/appcast.xml"` and that directory. The tool signs with the existing Keychain key.

Generate `SHA256SUMS.txt` for the four binaries and both feeds, then run `./tools/verify-update-release.sh "$DISPLAYWEAVE_OUTPUT_DIR"`. Independently verify the ZIP Ed25519 signature against the embedded public key, Mac `arm64 x86_64` architectures and bundle/feed identity, and the unsigned iOS arm64 version/identity. The APK must retain certificate SHA-256 `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.

## Local regression and release source

Run all [development gates](development.md): 37 Swift suites, Mac Debug universal build, iOS Simulator build, Android `test assembleDebug`, website build, bilingual docs, release links and whitespace checks. Keep full logs in ignored `build/` paths. Do not launch virtual-display tests without an independent online display; record physical gaps separately.

Copy the generated feeds exactly into `public/`, update the active release links/hashes and bilingual notes, review and commit. Native source and packaging inputs must match the binaries; rebuild if either changes. Tag the verified commit. Create the corresponding tracked-source archive with `git archive --format=tar.gz --prefix=DisplayWeave-v0.2.1-p8/ v0.2.1-p8 -o "$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-v0.2.1-p8-source.tar.gz"`, then add its hash to the checksum manifest and verify all seven entries. Source, GPL-3.0 and build scripts stay available beside the binaries even during GitHub public-access failures.

## Upload and integration

Create a draft GitHub Release at the verified tag and upload the eight files explicitly: four binaries, two feeds, source archive and checksum manifest. Never use `--clobber`. Compare uploaded sizes/digests or independently download them through the authenticated API.

Deploy a complete static snapshot to Cloudflare Pages project `displayweave-downloads`, production branch `main`, preserving every historical release path. Include the new eight files under `/releases/v0.2.1-p8/`. Copy the locally built `site-dist/` to `/displayweave/` as a backup site and feed archive. Exclude `functions/`, `_worker.js`, credentials, logs and local build directories; check the current Pages file limits. Use `wrangler pages deploy` with the project, branch and verified source commit.

If a site-only correction follows the release tag, keep the application artifacts unchanged. Archive the site deployment commit with `git archive` as `/displayweave/DisplayWeave-website-source.tar.gz`, provide its hash in `/displayweave/website-SHA256SUMS.txt`, and keep the footer source link valid. Run the site's route/hydration regression checks before deploying.

Download and hash the live files, check the backup site's referenced assets, then publish the GitHub Release. Review the final PR and merge using the maintainer's authorization, documenting local checks and the unavailable hosted checks honestly. Preserve release-tag ancestry with a merge commit and synchronize local/remote main.

GitHub API upload success does not prove anonymous download availability. As observed on 2026-10-16, public GitHub and Pages returned 404 while authenticated management and Cloudflare worked. Both apps still fetch update metadata from their original GitHub Pages URLs. Backup feed copies do not redirect installed clients; use manual installation until those URLs recover. This process does not change embedded feed identities.
