[English](README.md) | [简体中文](README.zh-CN.md)

# Tool map

Run tools from the repository root. See [development](../docs/development/workflow.md) and [directory/cleanup policy](../docs/development/repository-layout.md).

| Task | Entry points |
| --- | --- |
| Generate / build / launch Mac | `generate.sh`, `run.sh` → `script/build_and_run.sh` |
| Swift policy and production-method fixtures | `tools/run-swift-self-tests.sh` |
| Isolated TLS / identity / receiver runtime checks | `test-tls-interop.py`, `test-apple-keychain.py`, `test-secure-ios-receiver.py`, `test-secure-android-receiver.py`, `test-android-experience.py` |
| Packaging / identity | `package-release.sh`, `mac_signing.py`, `apple-distribution.py` |
| Update integrity | `generate-android-update-manifest.sh`, `verify-update-release.sh`, `check-release-links.sh` |
| Website / documentation | `prerender.mjs`, `check-site.mjs`, `check-docs.py` via `pnpm build` / `pnpm run check:docs` |
| Brand / DMG assets | `export-brand-assets.py`, `create-guided-dmg.sh` |
| Clean generated outputs | `clean-workspace.py` (dry run by default) |
| Customer Mac display evidence | `collect-mac-display-evidence.swift` (read-only); [paired 5K investigation prompt](../docs/verification/customer-mac-geometry.md) |
| Maintenance regressions | `test-workspace-cleanup.py`, `test-docs-check.py`, `test-release-packaging.py` |
| Historical probes | `audits/2026-10-26/`; these reproduce old bugs, not current acceptance |

Executable tool locations remain stable where they are used by CI, tests or external automation. Historical packaging names delegate to the stable release entry point or are explicitly local development tools. Credentials and generated installers are never committed.
