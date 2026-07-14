[English](current-ci-release-feed-audit.md) | [简体中文](current-ci-release-feed-audit.zh-CN.md)

# Current CI, Release, and Update-feed Audit

Audit date: 2026-07-15. Remote evidence was queried from GitHub and public Pages; artifacts were downloaded to a temporary directory and independently inspected.

## Preview 5 release

- Remote tag `v0.2.0-preview.5` resolves to `4276c1a229f9f0b3237242d3ebbc0f29d7e244da`.
- Release is a published, non-draft prerelease.
- Workflow run `29350612086` succeeded at that same SHA; build/update and feed-deployment jobs both succeeded.
- Seven expected assets are present: macOS ZIP and DMG, Android APK, unsigned iOS resigning input, appcast, Android manifest, and SHA256SUMS.
- `shasum -a 256 -c SHA256SUMS.txt` passes for all six hashed payload/feed files.
- Mac ZIP contains version `0.2.0-preview.5`, build 6, Sparkle Pages URL, and the expected embedded EdDSA public key.
- Appcast declares version/build 0.2.0-preview.5/6, references the immutable Release ZIP (not the DMG), matches ZIP size, and includes an EdDSA signature.
- APK is versionName `0.2.0-preview.5`, versionCode 6, v2-signed by exactly one signer with certificate SHA-256 `89805f...d589d`.
- Android manifest matches APK URL, size, SHA-256, version, and certificate fingerprint.
- Public Pages appcast and Android manifest match the downloaded Release feed contents.
- DMG checksum verification succeeds. The complete local verifier could not mount the DMG in this execution environment (`hdiutil attach: device not configured`), so mount-layout re-verification is environment-Pending; the publishing workflow's same verifier succeeded.

## CI finding and remediation

Before this audit the repository had Pages-on-main and manual Release workflows only. Ordinary pull requests/pushes did not run the required Android, Swift, macOS, docs, and whitespace gates (P3).

`.github/workflows/ci.yml` has been added with:

- Android self-tests, Gradle tests, and `assembleDebug`;
- targeted standalone Swift tests for queue/generation accounting, ABR, Binary V2, capability gating, and refresh policy;
- macOS Debug and unsigned iOS Simulator compatibility builds;
- site build, bilingual docs check, release-link check, and `git diff --check`.

The new workflow is locally syntax/review checked but cannot have a GitHub run until pushed; remote CI evidence is therefore Pending.
