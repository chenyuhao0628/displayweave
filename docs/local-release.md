[English](local-release.md) | [简体中文](local-release.zh-CN.md)

# Local build and publication

Use this path when the maintainer authorizes local publication. It preserves the existing application identities and signing keys. Record local evidence explicitly; do not mark unavailable GitHub checks successful or relax repository rules. See [automatic updates](automatic-updates.md) for trust and recovery boundaries.

## Prepare and build

Verify `git status`, the `displayweave` remote, the highest published build number, Xcode/XcodeGen, the Android SDK and Java, pnpm, and available signing material. Choose a new immutable version/build; never replace an existing public tag or asset. For this preview the version is `0.3.0-preview.1`, build `16`.

The Android keystore stays outside Git at `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`; the existing Keychain service is `app.displayweave.android-preview-signing`, account/alias `displayweave-preview`. The packaging script reads its password without printing it. Sparkle uses Keychain account `ed25519`. Run the existing Sparkle `generate_keys -p` only to inspect its public key; it must match `N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=`. Stop on a mismatch instead of generating a replacement.

Run from the repository root:

```bash
python3 -m venv build/local-release-venv
build/local-release-venv/bin/python -m pip install -r tools/dmg-requirements.txt
export PATH="$PWD/build/local-release-venv/bin:$PATH"
export DISPLAYWEAVE_VERSION_NAME=0.3.0-preview.1
export DISPLAYWEAVE_BUILD_NUMBER=16
export DISPLAYWEAVE_UPDATE_RELEASE=1
export DISPLAYWEAVE_RELEASE_TAG=v0.3.0-preview.1
export DISPLAYWEAVE_OUTPUT_DIR="$PWD/build/release-v0.3.0-preview.1"
test ! -e "$DISPLAYWEAVE_OUTPUT_DIR"
./tools/package-preview-0.1.sh
```

This generates the Xcode project, builds the ad-hoc Mac app and guided DMG/ZIP, builds unsigned device iOS, and runs Android tests plus the signed Release build. Do not run another packaging invocation against the same derived-data directories concurrently. Do not enable shell tracing or export private keys to files.

## Generate and verify feeds

```bash
export DISPLAYWEAVE_RELEASE_BASE_URL=https://github.com/chenyuhao0628/displayweave/releases/download
export DISPLAYWEAVE_PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export DISPLAYWEAVE_ANDROID_APK="$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-Android.apk"
export DISPLAYWEAVE_ANDROID_FEED_OUTPUT="$DISPLAYWEAVE_OUTPUT_DIR/android-update.json"
./tools/generate-android-update-manifest.sh
```

Copy only the new Mac ZIP into an empty appcast input directory. Run the bundled `build/preview-0.1-mac-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast` with `--account ed25519`, `--versions 16`, `--download-url-prefix https://github.com/chenyuhao0628/displayweave/releases/download/v0.3.0-preview.1/`, `--link https://github.com/chenyuhao0628/displayweave`, `-o "$DISPLAYWEAVE_OUTPUT_DIR/appcast.xml"` and that directory. The tool signs with the existing Keychain key.

Generate `SHA256SUMS.txt` for the four binaries and both feeds, then run `./tools/verify-update-release.sh "$DISPLAYWEAVE_OUTPUT_DIR"`. Independently verify the ZIP Ed25519 signature against the embedded public key, Mac `arm64 x86_64` architectures and bundle/feed identity, and the unsigned iOS arm64 version/identity. The APK must retain certificate SHA-256 `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.

## Local regression and release source

Run all [development gates](development.md): 52 Swift suites, Mac Debug universal build, iOS Simulator build, Android `test assembleDebug lintDebug`, website build, bilingual docs, release links and whitespace checks. Keep full logs in ignored `build/` paths. Do not launch virtual-display tests without an independent online display; record physical gaps separately.

Copy the generated feeds exactly into `public/`, update the active release links/hashes and bilingual notes, review and commit. Native source and packaging inputs must match the binaries; rebuild if either changes. Tag the verified commit. Create the corresponding tracked-source archive with `git archive --format=tar.gz --prefix=DisplayWeave-v0.3.0-preview.1/ v0.3.0-preview.1 -o "$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-v0.3.0-preview.1-source.tar.gz"`, then add its hash to the checksum manifest and verify all seven entries. Source, GPL-3.0 and build scripts stay available beside the binaries even during GitHub public-access failures.

## Upload and integration

Create a draft GitHub Release at the verified tag and upload the eight files explicitly: four binaries, two feeds, source archive and checksum manifest. Never use `--clobber`. Compare uploaded sizes/digests or independently download them through the authenticated API.

Download and hash the live files, then publish the GitHub Release. Review the final PR and merge using the maintainer's authorization, documenting local and hosted check results separately. Preserve release-tag ancestry with a merge commit and synchronize local/remote main.

GitHub API upload success does not by itself prove anonymous download access. Recheck the release and Pages feeds on each publication. On 2026-10-16 GitHub Pages returned HTTP 200 again and its latest deployment succeeded; earlier 404/account failures are historical evidence. The local p8 build (15) is separate from the currently public release list. Formal Apple production packaging is available through [the separate gated workflow](apple-distribution.md); the script above remains the preview path.
