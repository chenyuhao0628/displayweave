[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# Stable release checklist

Current release: **v0.3.3 / build 22**. [Release notes](v0.3.3.md), [exact files and hashes](current.md), [local commands](local-release.md).

## Publication record

- [x] Maintainer-authorized self-review of native head `bc928c3`; source CI `40447026849` passed all three jobs. No independent approval is claimed.
- [x] Local automated checks and synthetic display evidence are recorded in the [matching evidence](../verification/automatic-desktop-matching.md). Both initial iOS simulator failures and their successful isolated reruns are recorded in the [release notes](v0.3.3.md).
- [x] Build 22 Mac universal signature, hardened runtime and identity compared against the exact downloaded build 21; independent Sparkle Ed25519, original Android certificate and unsigned arm64 iOS verified.

The [release PR #24](https://github.com/chenyuhao0628/displayweave/pull/24) is the integration record for final CI, publication and Pages verification. The [v0.3.2 notes](v0.3.2.md) retain the previous publication receipts.

Android signer SHA-256: `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`. Mac remains Apple Development signed and unnotarized; iOS needs re-signing. Build 21 → 22 privacy permissions were not interactively retested. Customer two-Mac matching, native 5K video, Intel runtime and endurance remain pending.

Local packages: `artifacts/releases/v0.3.3/`. The [v0.3.1 notes](v0.3.1.md) and [earlier checklists](../archive/releases/release-checklist-through-v0.3.1.md) preserve historical evidence.

## Every subsequent publication

1. Confirm authorization, clean source, `displayweave` remote and a new stable numeric version/monotonic build. No public preview, beta, RC or prerelease.
2. Run the complete [development gate](../development/workflow.md), review source/compatibility/signing changes and record unavailable hardware explicitly.
3. Build through `tools/package-release.sh` with pinned identities and the exact previous published Mac app as baseline. Keep signing material external.
4. Generate the two update feeds, independently validate signatures/versions/identities/sizes/hashes and persist exact feeds in `public/`. Update current guides, site and release-link checks together.
5. Commit/tag matching source; archive tracked source including license/build scripts. The final manifest covers four binaries, two feeds and source; there are eight files including the manifest.
6. Stage as an unpublished GitHub draft, verify every uploaded asset, then publish as stable. Never overwrite public files or tags. Only GitHub Releases hosts downloads; only the project Pages site hosts update metadata.
7. Require full CI before merge, preserve tag ancestry, verify anonymous downloads and exact deployed feeds, then record results. Keep only the newly verified local stable package set after checking the next release is usable.
