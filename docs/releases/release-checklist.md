[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# Stable release checklist

Current publication: **v0.3.1 / build 20**, 2026-10-26. [Release notes](v0.3.1.md) describe behavior; [distribution](current.md) lists the exact files and hashes; [local publication](local-release.md) gives commands.

## Completed publication record

- [x] Reviewed source PR #19 and release PR #20 merged; tag `v0.3.1` points to `3255e9e1020ae3e90b73f65e16687c67d741e76a` and is an ancestor of main.
- [x] Release CI `40251555053` and post-merge CI `40252277449` passed; Pages deployment `40252277411` succeeded.
- [x] All eight GitHub assets independently downloaded and hashed; stable, published and Latest status confirmed on 2026-10-26. Both live Pages feeds exactly matched the release copies.
- [x] Universal Mac signature, hardened runtime, signing identity compared with build 19, Sparkle Ed25519, original Android certificate and unsigned arm64 iOS contents verified.
- [x] Source/runtime acceptance and hardware gaps recorded separately in the [upgrade ledger](../verification/reliability-experience-upgrade.md).

Android signer SHA-256: `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`. Mac remains Apple Development signed and unnotarized; iOS needs re-signing. Build 19 → 20 privacy permissions were not interactively retested. Physical capture/rotation/sleep recovery, Intel, real high refresh/Pencil, accessibility and endurance remain pending.

Local files are under `artifacts/releases/v0.3.1/`; selected evidence is under `artifacts/verification/v0.3.1/`. [Earlier checklist records](../archive/releases/release-checklist-through-v0.3.1.md) retain their original dates and scope.

## Every subsequent publication

1. Confirm authorization, clean source, `displayweave` remote and a new stable numeric version/monotonic build. No public preview, beta, RC or prerelease.
2. Run the complete [development gate](../development/workflow.md), review source/compatibility/signing changes and record unavailable hardware explicitly.
3. Build through `tools/package-release.sh` with pinned identities and the exact previous published Mac app as baseline. Keep signing material external.
4. Generate the two update feeds, independently validate signatures/versions/identities/sizes/hashes and persist exact feeds in `public/`. Update current guides, site and release-link checks together.
5. Commit/tag matching source; archive tracked source including license/build scripts. The final manifest covers four binaries, two feeds and source; there are eight files including the manifest.
6. Stage as an unpublished GitHub draft, verify every uploaded asset, then publish as stable. Never overwrite public files or tags. Only GitHub Releases hosts downloads; only the project Pages site hosts update metadata.
7. Require full CI before merge, preserve tag ancestry, verify anonymous downloads and exact deployed feeds, then record results. Keep only the newly verified local stable package set after checking the next release is usable.
