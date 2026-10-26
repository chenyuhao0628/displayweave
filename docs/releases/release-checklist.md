[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# Stable release checklist

Release package: **v0.3.2 / build 21**, 2026-10-26. [Release notes](v0.3.2.md), [exact files and hashes](current.md), [local commands](local-release.md).

## Publication record

- [x] Maintainer-authorized self-review of native head `b01e132`; source PR #22 merged as `1bfa1ca`. No independent approval is claimed. Existing owner bypass was used without changing repository rules.
- [x] Source CI `40263716075` passed all three jobs. Local runtime results and physical gaps are recorded in the [iMac evidence](../verification/imac-resolution-performance.md).
- [x] Build 21 Mac universal signature, hardened runtime and identity compared against exact downloaded build 20; independent Sparkle Ed25519, original Android certificate and unsigned arm64 iOS verified.
- [ ] Release PR CI, immutable tag/source archive and main ancestry: record after verification.
- [ ] All eight GitHub files independently downloaded/hashed, stable/Latest and anonymous access: record after publication.
- [ ] Pages deployment and both live feeds matching the release bytes: record after deployment.

Android signer SHA-256: `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`. Mac remains Apple Development signed and unnotarized; iOS needs re-signing. Build 20 → 21 privacy permissions were not interactively retested. Dual 2019 Intel iMac scaling, latency, adaptation and endurance remain pending.

Local packages: `artifacts/releases/v0.3.2/`; evidence: `artifacts/verification/v0.3.2/` and `artifacts/verification/imac-resolution-2026-10-26/`. The [v0.3.1 notes](v0.3.1.md) and [earlier checklists](../archive/releases/release-checklist-through-v0.3.1.md) preserve historical evidence.

## Every subsequent publication

1. Confirm authorization, clean source, `displayweave` remote and a new stable numeric version/monotonic build. No public preview, beta, RC or prerelease.
2. Run the complete [development gate](../development/workflow.md), review source/compatibility/signing changes and record unavailable hardware explicitly.
3. Build through `tools/package-release.sh` with pinned identities and the exact previous published Mac app as baseline. Keep signing material external.
4. Generate the two update feeds, independently validate signatures/versions/identities/sizes/hashes and persist exact feeds in `public/`. Update current guides, site and release-link checks together.
5. Commit/tag matching source; archive tracked source including license/build scripts. The final manifest covers four binaries, two feeds and source; there are eight files including the manifest.
6. Stage as an unpublished GitHub draft, verify every uploaded asset, then publish as stable. Never overwrite public files or tags. Only GitHub Releases hosts downloads; only the project Pages site hosts update metadata.
7. Require full CI before merge, preserve tag ancestry, verify anonymous downloads and exact deployed feeds, then record results. Keep only the newly verified local stable package set after checking the next release is usable.
