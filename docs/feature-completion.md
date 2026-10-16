[English](feature-completion.md) | [简体中文](feature-completion.zh-CN.md)

# Feature completion plan and evidence

Baseline: `89d7d20`, 2026-10-16. This is the active source-development ledger. Installed and published p8 (build 15) is unchanged by this work. Physical acceptance is a separate gate. Historical audits retain their dated evidence; this ledger supersedes their pending-feature lists.

## Scope, feasibility and acceptance

| ID | Current gap and intended behavior | Design and compatibility boundary | Completion evidence |
| --- | --- | --- | --- |
| F01 | Embedded GitHub Pages feeds are unavailable; new builds need a reachable update channel. | Migrate the canonical feed to the existing HTTPS Cloudflare mirror; retain Sparkle Ed25519 and APK certificate identities. Android may fall back once on transport failure, never on invalid metadata or artifact integrity failure. Old p8 needs one manual install if its old URL stays unavailable. | Migration/configuration tests, fallback rejection fixtures, platform builds, live feed checks. |
| F02 | Quality scales encoding; users cannot choose a separate per-device desktop mode. | Persist Native/1080p/1440p/4K per installation ID. Use explicit pixel and logical-point geometry with orientation and receiver envelopes. Recreate only the affected extension session after owned resources stop. Mirror preserves the physical desktop. | Geometry, persistence, limits and session replacement tests; Mac build. Physical display acceptance remains separate. |
| F03 | LAN video/control has no encrypted authentication. | Introduce an explicitly negotiated secure transport with platform crypto, out-of-band pairing confirmation, retained peer trust and revocation. Authenticate before capture or input. Bound handshakes and reject downgrade for paired peers. Preserve legacy interoperability only through an explicit insecure choice. Final crypto/transport design requires API and cross-platform interoperability checks before implementation. | Positive and negative handshake, wrong identity, tampering, replay, timeout, reconnect and old-peer fixtures across Apple/Java; real network integration. |
| F04 | Apple receiver codec/refresh path is limited. | Add iOS HEVC using the validated bitstream parser and hardware capability checks; negotiate 30/60/90/120 within display/decoder limits. Extend Mac caps only when advertised display and decoder envelopes support it. H.264 fallback must remain viable. | Codec parsing, capability/FPS boundary and fallback tests; both Apple builds. Target FPS is never reported as measured performance. |
| F05 | Mac receiver has no keyboard/mouse return path. | Explicit local enablement and sender permission; negotiated events on the authenticated session, aspect-correct coordinates, bounded queues, focus/disconnect release of held keys/buttons, local escape shortcut. Preserve touch/Pencil protocol. | Event validation/mapping, overflow, cancellation and stale-session tests; Mac build. Depends on F03. |
| F06 | Mac active Wi-Fi session does not migrate to a returned wired candidate. | Opt-in Auto preference, same installation identity, stop-before-start and bounded reconnect. Pin candidate interface; no simultaneous sender pipelines. Preserve manual transport and Android USB policies. | Candidate deduplication, flapping, recovery exhaustion, manual disconnect and old callback tests. |
| F07 | Pencil lacks roll, squeeze/double tap actions and eraser tooling. | Versioned capability extension, SDK/hardware guards, configurable tool/shortcut actions and cancellation. Use documented tablet fields; app-specific integration is explicit shortcut mapping, not a promise of universal drawing-app support. | Codable/validation, action mapping, capability and cancellation tests; Apple builds. Physical Pencil/application matrix stays pending. |
| F08 | CPU sample is absent; Android allocates each frame. | Interval process CPU measurement with defined units/reset; bounded pooled frame leases with explicit transfer and exactly-once return after asynchronous decoder consumption. Never reuse an in-flight array. | CPU delta/reset tests; pool exhaustion, exception, queue drop, reconnect and concurrent lease tests; Android build and allocation metrics. |
| F09 | Protocol documentation is fragmented. | Consolidate framing, negotiation, epochs, ACK/readiness, codecs, inputs, security and compatibility into a public versioned specification. Shared golden vectors and malformed-input cases must exercise actual encoders/parsers. | Swift/Java vectors, full policy/network regression; documentation checker. Finalize after wire changes. |
| F10 | Production Apple distribution lacks identities. | Add explicit Developer ID signing/notarization and iOS archive/export workflows, preflight identity/provisioning checks, immutable packaging and existing update signatures. Never substitute a new key or claim unsigned/ad-hoc builds are notarized. | Shell/preflight tests and current preview path checks. External prerequisite: no Developer ID identity found on 2026-10-16; production signing cannot be completed without the maintainer's identity/profile. |
| F11 | No editable/transparent/dark brand master or Android adaptive icon. | Preserve current mark; complete adaptive resource packaging, safe area/palette guidance and reproducible exports. Do not invent an approved final master. | Resource/build checks. External prerequisite: original `newicon.svg` / `newnewicon.png` absent; final master and licensed real-device screenshots need supplied/approved artwork. |
| F12 | Some current-looking documents describe implemented work as pending. | Correct Android runtime decoder FPS downgrade and benchmark drop/keyframe documentation; consolidate source/release/hardware status. Update paired guides with each feature. | Bilingual/site/release checks and final full regression. |

## Execution and completion

Order: F01 → F02 → F04 → F08 → F06 → F03 → F05 → F07 → F09 → F10/F11 → F12. Each round includes the relevant regression, build, paired guide update and a coherent commit. Security research may refine the implementation order; record concrete tradeoffs here. No concurrent agents are required.

Feature completion means implemented behavior and passing automated acceptance, not just a policy stub or design. A blocked external identity/artwork requirement remains visibly blocked while the supported tooling is delivered. No public release or installation replacement is implied. Before integrating, run all Swift suites, Android tests/build, both Apple builds, website production build, bilingual/release checks and whitespace checks. Preserve unrelated changes and synchronize only with `displayweave`.

## Progress

- Assessment: repository clean on baseline; twelve work items enumerated with acceptance and dependencies.
- Remaining implementation: F03, F05–F12. Individual entries below will record commits, actual automated evidence and remaining external/physical gates.

## Official API references

- Sparkle: [publishing / feed migration](https://sparkle-project.org/documentation/publishing/), [update trust](https://sparkle-project.org/documentation/). Checked 2026-10-16; changing the feed does not replace archive signature verification.

### F01 — implemented in source

Migrated Mac feed including persisted-feed override; Android bounded availability fallback with TLS/metadata fail-closed behavior. Signing identities are unchanged. Regression first failed against the old configuration, then passed. Mac universal Debug build, Android six groups (including new UpdateClient transport tests) and assembleDebug passed. Live canonical feeds returned 200 and matched tracked p8 bytes. Old p8 still needs manual migration if Pages stays unavailable.

### F02 — implemented in source

Per-installation Native/1080p/1440p/4K selection now rebuilds only the affected extension session. Logical geometry is separate from decoder/quality scaling; mirror ignores the desktop override. Added failing-then-passing geometry, persistence, limit and mirror tests. All 38 Swift suites and Mac universal Debug build passed. See [usage and physical acceptance](desktop-resolution.md).

### F04 — implemented in source

Shared bounded H.264/HEVC parser, iOS explicit Apple envelopes, hardware-gated HEVC, one-shot timed H.264 fallback, and Apple refresh negotiation up to 120fps. iOS requests ProMotion cadence only while its video view is connected. 39 Swift suites, updated Mac network/bitstream tests, Mac universal Debug and iOS Simulator builds passed. iPad simulator exercised valid H.264, configuration rejection, unsupported HEVC fallback and no re-upgrade on the same connection; hardware HEVC presentation was unavailable there. See [scope and physical acceptance](apple-video.md).
