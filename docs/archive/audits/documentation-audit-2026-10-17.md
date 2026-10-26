[English](documentation-audit-2026-10-17.md) | [简体中文](documentation-audit-2026-10-17.zh-CN.md)

> Historical record: versions, commands and conclusions describe the original snapshot. Use the [current documentation](../../README.md) for present-day instructions.

# Documentation audit and release consistency (2026-10-17)

This pass covers root guides, the documentation index, current installation/update/signing/release procedures, OpenDisplay compatibility, resolution guidance and website copy for v0.3.0-preview.3 (18). All tracked Markdown files are scanned for local link targets.

## Corrections

- Root README, architecture, security, roadmap and website now describe the current Mac as Apple Development signed and unnotarized rather than ad-hoc signed.
- Current version, eight asset names, binary/feed hashes, website structured-data version and exact persisted feed bytes agree on preview.3 / 18.
- Initial signing migration and subsequent identity continuity are distinguished. The guides neither require reauthorization on every update nor promise permanent permission retention.
- Removed the stale Chinese dual-source update claim and retired the mirror download instruction in the old p8 record. The local p8 artifact is distinguished from public releases.
- Current publication uses the local workflow. Hosted Release lacks the Mac identity, previous-app baseline and source archive step, so it is not a complete publication route.
- Build examples specify fixed signing. The next-release recipe uses preview.4 / 19 and labels it unpublished. The bilingual gate now includes the previously omitted permission guide, eight other existing pairs and this release/audit; seven pairs gained reciprocal language links.
- Historical release notes retain their original signing and test facts; old performance observations are not presented as measurements for this build. Current compatibility entry points and extension-resolution behavior are unchanged.

## Verification and limits

Website build, 93 bilingual pairs, current release link/hash/feed consistency and local link targets across 208 Markdown files passed; the publication PR records these checks. Full hosted CI must pass before integration. Artifact validation, the local 17.1 → 18 permission-retention test and unperformed hardware tests are separated in the [release notes](../releases/release-notes-v0.3.0-preview.3.md).

A local-link scan does not establish continued availability of every external website. GitHub Release assets and GitHub Pages feeds receive separate online verification for this release. Cross-device video/performance, Intel, Pencil and endurance remain pending. Older audit reports may describe past implementations; current guides and versioned release notes define today's behavior.
