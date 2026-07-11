[English](branding-and-doc-audit.md) | [简体中文](branding-and-doc-audit.zh-CN.md)

# DisplayWeave Brand and Documentation Audit

> 2026-07-11 更新：本文记录早期审计历史。Android USB 已改为 Mac 端
> `adb forward` 实现（不是 `adb reverse`），但真机、多设备和耐久验收仍
> 待完成。当前资源清单与缺失的透明/深色 master 以 `docs/brand-assets.md`
> 为准；下文“Android WiFi-only/USB planned”属于此前状态，不应作为当前声明。

Audit date: 2026-07-10

## Second-Round Resolution

The 2026-07-10 second-round update acted on this audit. The supplied full
DisplayWeave logo is now the README, website hero, and social identity. A
temporary mark-only derivative is checked in at `public/icon.png` and replaces the old OpenDisplay
artwork across favicon, macOS, iOS/iPadOS, Android launcher, and in-app logo
resources. The derivative is intentionally temporary pending final production
exports and platform review.

Core documentation now separates completed, physically validated,
experimental, and planned capabilities. `ROADMAP.md` and
`docs/roadmap-and-acceptance.md` were restructured, the high-refresh migration
record received a current-status header, and website/structured-data FAQ copy
now explicitly states the Android WiFi-only and measured 109-111 FPS limits.

## Scope

This audit covers the repository's user-facing brand, tracked visual assets,
top-level documentation, `docs/`, the Android receiver guide, website copy and
metadata, and origin/license statements. It compares those surfaces with the
implemented and physically validated state recorded in
`docs/120hz-migration-plan.md` and `docs/roadmap-and-acceptance.md`.

The audit deliberately distinguishes public branding from compatibility
identifiers. Names such as `OpenSidecar.xcodeproj`, Xcode schemes,
`app.opendisplay.android`, `OpenDisplayServer`, bundle IDs, preference keys, and
`_opensidecar._tcp` remain internal compatibility contracts. They should not be
renamed as a cosmetic cleanup without a separate migration design.

## Summary

- The README's feature/status section is generally accurate: Android USB/ADB
  reverse and iOS/iPadOS 120Hz are explicitly described as planned, Android
  high refresh is experimental, and the measured result is stated as about
  109-111 FPS rather than stable 120 FPS.
- The website and README now use the supplied DisplayWeave logo. The old
  OpenDisplay social preview, favicon, and web logo were replaced in this audit.
- Native macOS, iOS, and Android application icons now use the temporary
  DisplayWeave mark. Final platform-polished exports remain recommended.
- `ARCHITECTURE.md` was materially stale: it described an H.264-only pipeline
  and did not delimit Android WiFi from Apple USB. The obvious factual errors
  were corrected in this audit.
- Several top-level documents still called DisplayWeave a "fork". Current
  project prose was corrected where unambiguous; historical records and
  compatibility names were retained.
- Multi-device support exists in the inherited Apple receiver path, but the
  website's "up to three" claim was not backed by current DisplayWeave
  validation evidence. It is now qualified as an OpenDisplay-history report.

## Findings

| Priority | Type | Location | Finding | Recommended action | Audit action |
| --- | --- | --- | --- | --- | --- |
| High | Visual resource issue / brand residue | `Mac/Assets.xcassets/AppIcon.appiconset/*`, `iOS/Assets.xcassets/AppIcon.appiconset/*`, `iOS/Assets.xcassets/AppLogo.imageset/applogo.png`, `AndroidReceiver/app/src/main/res/drawable/app_logo.png`, `AndroidReceiver/app/src/main/res/mipmap-*/ic_launcher.png` | The native app icons used the recognizable OpenDisplay happy-screen artwork, making installed apps look like OpenDisplay. | Create a mark-only master derived from the approved DisplayWeave logo, with platform-safe padding and no tiny wordmark. Export complete macOS, iOS, and Android adaptive/legacy icon sets, then inspect them at actual launcher sizes. | Resolved with a temporary mark-only DisplayWeave derivative in round two. Final adaptive icon, transparency, safe-area, and small-size optical review remains manual production work. |
| High | Visual resource issue / brand residue | `public/logo.png`, `public/icon.png`, `public/icon-256.png`, `public/og.png`, README header, website hero/favicon/metadata | The web logo and favicon used the old happy-screen icon; `public/og.png` explicitly displayed the name OpenDisplay. | Use the supplied DisplayWeave artwork as the canonical project logo and replace every current web entry point. Create optimized favicon and 1200 x 630 social-card derivatives. | Resolved. The full supplied logo remains the canonical hero asset; favicon uses the temporary mark and OG uses a 1200 x 630 DisplayWeave derivative. |
| High | Functional inconsistency / outdated information | `ARCHITECTURE.md` system shape, data flow, transport, Mac sender, and Android receiver sections | Architecture described VideoToolbox and payloads as H.264-only even though Android capability negotiation, HEVC encode/decode, `streamConfig`, codec failure, and H.264 fallback are implemented. It also used the nonexistent renamed class `DisplayWeaveServer`. | Document the negotiated H.264/HEVC path, legacy Apple H.264 path, fallback behavior, experimental frame rates, transport boundaries, and actual compatibility class names. | Fixed in this audit. |
| High | Outdated information | `ROADMAP.md` future capabilities | HEVC was still listed as future work although the negotiated HEVC path and H.264 fallback are implemented and physically verified. | Replace it with broader cross-device HEVC compatibility/fallback validation; keep Android USB, encrypted pairing, and package distribution as future work. | Fixed in this audit. |
| Medium | Brand residue | `ROADMAP.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `BUILD_IOS_WITH_FREE_APPLE_ID.md` | Current project prose repeatedly called DisplayWeave "the fork" or "Mac/Android CN fork", weakening the independent project identity. | Use "DisplayWeave" or "independent community project" in current prose. Keep "fork" only when explaining Git/GPL history or answering the licensing FAQ. | Fixed in these top-level documents. Historical changelog/review records were intentionally retained. |
| Medium | Functional inconsistency | `src/App.tsx` feature 003 and iPad FAQ; matching FAQ JSON-LD in `index.html` | The site stated that several iPads/iPhones and up to three screens had been tested as if this were current DisplayWeave validation. The evidence belongs to inherited OpenDisplay history; mixed Apple/Android multi-device validation is not documented. | Qualify the claim as inherited behavior/history until a DisplayWeave test matrix records simultaneous device types, session count, duration, reconnects, and input behavior. | Fixed by qualifying the claim; broader validation remains open. |
| Medium | Functional inconsistency | `src/App.tsx` hero and comparison table; `index.html` feature list; `public/privacy.html`; `SECURITY.md` | Generic USB wording could be read as Android USB support even though Android currently ships only WiFi TCP. | State "USB for iPhone/iPad" and "WiFi for Android" at each broad product summary. Do not describe ADB reverse as implemented until a real transport and install flow pass device tests. | Fixed in the highest-visibility website, metadata, privacy, architecture, and README surfaces. A second-round copy pass should check remaining low-visibility wording. |
| Medium | Outdated information | `docs/roadmap-and-acceptance.md` | The document mixed an implementation brief, completed work, future requirements, and acceptance criteria. Readers could mistake future target language such as Android USB/ADB reverse for current status. | Add a status legend and split completed, physically validated, experimental, and planned claims. | Resolved in round two with a focused acceptance document. |
| Medium | Visual resource issue / repository hygiene | `AndroidReceiver/dist/opendisplay-screen.png` | A tracked personal desktop debug screenshot remains under `dist/` with an old-brand filename. It is not an APK or deliberate documentation asset and contains unrelated desktop details. | Confirm whether it has evidentiary value; otherwise remove it. If retained, redact/crop it, move it under `docs/assets/`, and rename it to describe the test rather than the old brand. | Deferred because deletion/redaction requires an explicit decision about preserving test evidence. |
| Medium | Outdated information / metadata | `index.html` structured data | `downloadUrl` pointed to `releases/latest` even though DisplayWeave is source-first and has no current signed package; `softwareHelp` pointed to a nonexistent `#quick-start` anchor. | Remove the invalid download URL until a real package exists and link help to `#build-from-source`. | Fixed in this audit. |
| Medium | License wording | `src/App.tsx` license FAQ and matching `index.html` JSON-LD | The current GPL-3.0 status is clear, but the parenthetical "releases up to v0.4.x were MIT" can be mistaken as a DisplayWeave release policy and is not explained in `THIRD_PARTY_NOTICES.md`. | Keep the current repository license statement prominent. In round two, either document the exact upstream tag/history basis for the MIT statement or move it to a clearly labeled upstream license-history note. | Deferred pending history verification; no current GPL wording was weakened. |
| Low | Brand residue with valid historical context | `CHANGELOG.md`, `fastlane/APP_REVIEW.md`, `fastlane/APP_STORE_LISTING.md`, `src/components/Showcase.tsx`, `public/showcase/*` | OpenDisplay/OpenSidecar names remain in inherited changelog entries, App Review history, and quoted community posts. Removing them would falsify history or quotations. | Retain them, but label archival/historical sections clearly and keep them out of current product headings and metadata. | No change. The website already labels showcase items as OpenDisplay project history. |
| Low | Compatibility identifier | `project.yml`, build commands, source class/package names, bundle IDs, preference keys, `_opensidecar._tcp` | Old names remain internally and appear in technical documentation. They are not necessarily public brand residue; many are build, discovery, persistence, or application identity contracts. | Add one compatibility-identifiers note to architecture/contributor documentation. Rename only through a separately tested migration with backward compatibility and store/bundle implications. | Documented at the top of this audit; no code rename performed. |
| Low | Visual consistency | `public/privacy.html` header and browser favicon | The approved full logo contains both symbol and wordmark inside a square canvas, which is too detailed at favicon size. | Use a mark-only derivative for small surfaces and keep the full wordmark for README, hero, and social use. | Resolved with the temporary DisplayWeave mark; final optimized production exports remain recommended. |

## License and Origin Assessment

The current relationship is substantially clear and internally consistent:

- `README.md` identifies DisplayWeave as an independent community project
  derived from OpenDisplay and links the upstream repository.
- The root `LICENSE` and GitHub metadata identify GPL-3.0 as the current
  repository license.
- `THIRD_PARTY_NOTICES.md` states that OpenDisplay history, copyright notices,
  and GPL obligations are retained.
- The SideScreen section says it was a design/technical reference and that the
  repository was not imported wholesale. It also explains that any future
  copied or substantially adapted source must carry the relevant MIT notice.

No high-priority license defect was found. The second-round website FAQ now
states only the current GPL-3.0 obligations and links the project origin to the
third-party notices. Any future discussion of older upstream MIT releases
should first be verified against exact upstream tags and license history.

## Capability Baseline For Future Copy

Use this baseline when editing public claims:

- Apple receivers: H.264, USB via `usbmuxd`, and local WiFi.
- Android receiver: local WiFi TCP today; USB/ADB reverse is planned.
- Android codecs: HEVC when negotiated and available, with H.264 fallback.
- Android frame rates: negotiated 30/60/90/120fps modes are implemented, but
  high refresh remains experimental.
- Physical validation: approximately 109-111 FPS end to end on one OnePlus
  OPD2413 in HEVC/120 mode, with Android reporting an active 120Hz mode.
- Do not claim stable sustained 120 rendered FPS across devices.
- iOS/iPadOS 120Hz is planned, not implemented.
- Multiple Apple receiver sessions are inherited functionality; broader
  DisplayWeave mixed-device and long-duration validation remains incomplete.

## Round-Two Resolution And Remaining Work

Completed in round two:

- Replaced current web and native OpenDisplay-style visuals with the supplied
  full logo and a temporary mark-only DisplayWeave derivative.
- Added a 1200 x 630 DisplayWeave social preview and optimized-size favicon.
- Rewrote the acceptance document and Roadmap around explicit status classes.
- Updated architecture, Android docs, privacy, FAQ, metadata, and structured
  data using the capability baseline above.
- Removed the ambiguous upstream MIT-history sentence from the current website
  license FAQ while preserving GPL-3.0 and origin notices.

Still requires manual or evidence-producing work:

1. Produce final transparent/light/dark logo masters and Android adaptive icon
   foreground/background resources; inspect Dock, launcher, Settings,
   splash/onboarding, and notification surfaces on real devices.
2. Revalidate simultaneous multi-device behavior and publish a test matrix
   before strengthening claims about mixed receivers.
3. Verify exact upstream MIT-to-GPL tag history before documenting it as a
   DisplayWeave-facing license-history statement.
4. Decide whether to remove or redact
   `AndroidReceiver/dist/opendisplay-screen.png`, which contains a personal
   desktop debug capture and an old-brand filename.

## Validation Checklist For This Audit

- Confirm the README/hero asset matches the supplied logo and all favicon,
  social, and native derivatives visibly use the DisplayWeave mark rather than
  the old OpenDisplay artwork.
- Build the website and inspect desktop/mobile screenshots for logo sizing,
  metadata, overflow, and old social-preview references.
- Run targeted searches for current-project `fork` wording, old brand names,
  HEVC/H.264 claims, USB/ADB claims, iOS 120Hz, 109-111 FPS, and multi-device
  claims.
- Run `git diff --check` and confirm no source compatibility identifier was
  renamed as part of this documentation audit.
