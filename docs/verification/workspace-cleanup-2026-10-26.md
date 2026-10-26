[English](workspace-cleanup-2026-10-26.md) | [简体中文](workspace-cleanup-2026-10-26.zh-CN.md)

# Workspace and documentation cleanup — 2026-10-26

Scope: local project cleanup and current documentation maintenance after stable v0.3.1. The user's “stabilizer” wording was clarified as “documentation”. No application version, signing identity or protocol migration is included.

## Evidence before changes

- Baseline main: `69fe25774d3dc94d64d9aeaa303dbe860490705d`; clean worktree, only this checkout registered.
- `du -x -k -d 1 .` measured **5,002,768 KiB**. Most space was duplicate Apple derived data, old release/install archives, download verification copies and temporary test output. Root-level `build-run`, `build-verify-mac`, `build-verify-ios`, `site-dist` and `dist-ssr` duplicated generated-output locations.
- GitHub Latest API reported published, non-prerelease **v0.3.1 / build 20**. All eight local files matched its asset sizes and SHA-256 digests before relocation.
- `docs/development-preview.md` and its Chinese peer advertised v0.3.1 but retained four stale binary hashes. The new table checker rejects all four on the old baseline, even though correct hashes appeared elsewhere in the repository.
- The iOS setup guide still described Simulator-only delivery and no unsigned IPA; support said Android streaming only used Wi-Fi. The public privacy page still claimed unencrypted Wi-Fi and no server requests despite TLS pairing and GitHub updates in source.

## Implemented organization

Platform source roots remain recognizable. Current guides are grouped by use/development/reference/releases/verification; historical plans, designs, audits and old release notes live under `docs/archive/` with explicit snapshot notices. Category indexes retain discoverability. Root support and iOS setup now have Chinese peers; public privacy pages describe both languages and current data flows.

Build, launcher, website/SSR, packaging and CI paths use the conventions in [repository layout](../development/repository-layout.md). `run.sh` delegates to the signed development script. Stable packaging requires explicit version/build and the previous signed app; the historical script name delegates to it. Existing key names and signing requirements remain intact.

The eight retained packages are in `artifacts/releases/v0.3.1/`. Selected release and source logs/screenshots are in `artifacts/verification/v0.3.1/`. Old local versions, duplicate downloads, rebuildable caches, superseded development packages and Finder metadata were removed. The first cleanup reduced measured usage to **348,256 KiB**, including installed website dependencies and Git history. Final local measurements and the deletion list are kept in `artifacts/verification/workspace-cleanup-2026-10-26/`.

Git history, public historical releases, global SDKs/caches, installed apps, local SDK configuration and external signing material were retained. Private artwork was not classified as a disposable build output.

## Automated verification

- Project generation and Swift launcher typecheck passed. All 61 standalone Swift suites and production-method recovery/admission fixtures passed.
- Website TypeScript/client/SSR/prerender checks passed using the relocated output. Generated English/Chinese pages and both static privacy pages have resolvable local links.
- Recursive bilingual/reciprocal link and current GitHub documentation-link checks passed. Active release tables match v0.3.1 hashes in both languages.
- Cleanup regressions cover dry-run planning, source/config/evidence preservation, dependency opt-in, tracked-file/key rejection, symlink boundaries, retained-release corruption/incompleteness and older-version pruning.
- Documentation regressions cover moved links, missing peers, reciprocal links, historical URLs, inline examples and bilingual website templates. Packaging regressions cover stable-only arguments, compatibility/run aliases and stale table hashes.
- Existing 20 signing tests, 12 Apple distribution tests and 36 brand exports passed. Shell/Python syntax and whitespace checks passed. CI includes the maintenance tests and builds both native targets using `build/verify/` before integration.

## Physical verification and deferred work

No new hardware-performance or permission-continuity claim. This cleanup does not need desktop capture, virtual displays, physical receiver streaming or a replacement installation. The v0.3.1 [hardware acceptance gaps](../releases/v0.3.1.md) remain as recorded. Published binary bytes and update feeds are unchanged; this work is source/documentation maintenance.
