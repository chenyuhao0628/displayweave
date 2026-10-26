[English](repository-layout.md) | [简体中文](repository-layout.zh-CN.md)

# Repository layout and cleanup

Reviewed 2026-10-26. Run commands below from the repository root.

| Location | Purpose | Retention |
| --- | --- | --- |
| `Mac/`, `iOS/`, `Shared/`, `AndroidReceiver/` | Platform applications and shared Apple code | Tracked source; keep platform/project identities |
| `MacTests/`, `tools/audits/` | Current regression suites and dated baseline probes | Tracked; baseline probes are historical evidence |
| `src/`, `public/` | Website source, brand resources and exact published update feeds | Tracked; feeds are release data |
| `docs/` | Categorized bilingual guides and historical records | Tracked Markdown; local artwork stays ignored |
| `script/`, `tools/`, `.github/`, `fastlane/` | Local run, verification, packaging and automation | See [tool map](../../tools/README.md) |
| `project.yml`, package/Gradle/Gem manifests and lockfiles | Reproducible project/dependency inputs | Tracked; Xcode project is generated |
| `build/dev/mac/` | Mac development app and launcher log | Rebuildable |
| `build/verify/mac/`, `build/verify/ios/` | Unsigned compile checks | Rebuildable |
| `build/package/` | Shared release/development packaging intermediates | Rebuildable |
| `build/site/client/`, `build/site/ssr/` | Pages upload and SSR intermediate output | Rebuildable; both created by `pnpm build` |
| `build/diagnostics/` | Temporary test outputs | Move selected acceptance evidence to `artifacts/verification/` before cleanup |
| `artifacts/releases/vX.Y.Z/` | Complete local published package set | Retain the latest verified stable version |
| `artifacts/verification/` | Release receipts and selected test logs/screenshots | Local, ignored; review before sharing |
| `node_modules/`, Android `build/` and `.gradle/` | Tool-managed dependencies/builds | Reinstall or rebuild; Gradle keeps its native layout |
| `.git/` | History, refs and repository metadata | Preserved |

`build/` and `artifacts/` are ignored. Put durable notes in `docs/`, never in a disposable build directory. Keep credentials in Keychain or the existing external signing directory. `AndroidReceiver/local.properties` remains local. Root READMEs, architecture, contribution, security, roadmap, license and notices remain visible entry points.

## Safe cleanup

```bash
python3 tools/clean-workspace.py
python3 tools/clean-workspace.py --apply
```

The first command previews exact paths and logical file bytes. Stop this project's builds/dev servers before applying. The second removes only the fixed set of generated directories, including old root-level build paths. It rejects tracked content, symlink roots/ancestors and misplaced signing-key files. It keeps installed applications, source, Git history, verification records, local SDK settings and external/global caches.

To also remove website dependencies, add `--dependencies`; restore them with `pnpm install --frozen-lockfile`. To prune older **stable** local release folders, first confirm the published tag with `gh release view --repo chenyuhao0628/displayweave --json tagName,isDraft,isPrerelease`, then:

```bash
python3 tools/clean-workspace.py --keep-release v0.3.1
python3 tools/clean-workspace.py --keep-release v0.3.1 --apply
```

Retention requires a complete eight-file release and checks all seven manifest hashes before any deletion. Corrupt/missing retained files stop cleanup. Unknown folders, previews and newer staging versions are not inferred obsolete. Publication is independently verified against GitHub; a local checksum alone is not proof of publication. Never delete the previous baseline until the next stable release is verified. The dated cleanup removed legacy preview output folders after inventory; that one-time classification is not a wildcard deletion policy.

## Rebuild and maintain

Run `./generate.sh` to regenerate `OpenSidecar.xcodeproj`; `./run.sh` delegates to the existing signed development [run workflow](workflow.md). Native compile-only checks use `build/verify/`. `pnpm build` and both Pages workflows agree on `build/site/client`.

`tools/package-release.sh` requires explicit stable `X.Y.Z` / positive build values, the pinned signing identity and a previous-release app for comparison. Its default output is `artifacts/releases/vX.Y.Z/`; intermediates stay under `build/package/`. The old script name is a compatibility alias to the same stable-only path. `package-development-preview.sh` remains an internal debugging helper under `build/package/development/`, not a public release channel.

`pnpm run check:docs` recursively discovers paired guides, validates reciprocal links and resolves local/website documentation links. `pnpm run check:release` checks current release references and published hashes. Run both after moving a guide, and keep new user guides bilingual.
