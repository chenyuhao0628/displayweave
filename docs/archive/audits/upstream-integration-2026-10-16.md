[English](upstream-integration-2026-10-16.md) | [简体中文](upstream-integration-2026-10-16.zh-CN.md)

> Historical record: versions, commands and conclusions describe the original snapshot. Use the [current documentation](../../README.md) for present-day instructions.

# Upstream integration review — 2026-10-16

Fetched `origin/main` at `b9eec1f232fb5ea571c87e8392379a84f47b237f` (unchanged since the prior Mac receiver review). The integration dry run against source branch `defe049` reports **23 conflicts**, including the split/deleted UI files, Android-sensitive sender code, project generation, release automation, signing configuration, appcast and branding. No whole-history merge is claimed.

| Upstream item | Decision and local implementation |
| --- | --- |
| `23b62b3`, `f1f3ec5`, `d04a439`, `04f33ad`, `f0d211a` | Already adapted: Mac receive role, H.264 caps, panel logical geometry, fullscreen and bounded receiver framing. See Mac-to-Mac design; Android DWV2 remains separate. |
| `87b000b`, `c27e538` | Adapted: failed startup releases capture/socket/ADB resources; error row offers a fresh-pipeline retry. Local `SessionLifetime` adds idempotent cleanup and waits for a suspended start. Settings replacement also waits for cleanup and checks role generation. |
| `19481a6` | Adapted bounded logging concept for both Apple targets: each current/previous file ≤2 MiB, entry ≤8192 bytes, ≤256 pending lines; excess log work is dropped rather than blocking video. Compatibility log paths retained. |
| `04590ed` | Adapted delayed touch-down: tap commits on release, drag after 10-point movement, hold after 0.12 seconds; a second finger discards an uncommitted click. Pure policy regression covers tap/drag/hold/cancel. |
| `472e785`, upstream web UI | Locally implemented task-focused receiver UI; do not import App Store rating prompts, upstream download identities or donations. |
| `91ca272` | Follow-up source iteration adapts hardware-gated Mac HEVC with bounded H.264 fallback. iOS video stays H.264; physical matrix pending. |
| `a930071`, `d24afad`, `f244d63`, display arrangement/serial recovery | Defer full per-device desktop sizing and private-API recovery redesign; current Mac panel/cap policy is covered, but changing desktop geometry requires active-display and multi-device regression evidence. |
| `42ad6fb`, helper from `d2dfb3f`, `da9f369` | Follow-up source iteration adapts pinned direct-link Mac discovery and negotiated Pencil input. See [design/evidence](../../reference/hevc-wired-pencil-plan.md). `1c857a4` only updates release metadata. |
| Remote shutdown, iOS deployment lowering / force-update gate | Still outside scope. |
| Upstream release/signing/branding changes | Retain DisplayWeave identities, feeds, keys, release versions, provenance and GPL-3.0. |

Validation for accepted changes: 29 standalone Swift suites, universal arm64/x86_64 Mac Debug build, iOS simulator build, bilingual and release-link checks. UI evidence and the final broader audit are recorded in the iteration report. Two-Mac physical streaming, closed-lid virtual-display release and mobile input on real hardware remain separate acceptance items.
