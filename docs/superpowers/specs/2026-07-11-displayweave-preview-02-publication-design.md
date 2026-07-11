# DisplayWeave Preview 0.1.0-preview.2 Publication Design

Date: 2026-07-11
Status: approved direction, awaiting written-spec review

## Objective

Publish the completed Android ADB USB and reconnect work from
`codex/android-adb-usb` as DisplayWeave `v0.1.0-preview.2`, update the project
documentation to match the verified product state, replace the inherited
OpenDisplay-like landing-page presentation with an independently recognizable
DisplayWeave design, and publish the source plus three offline preview artifacts
to the maintainer's `chenyuhao0628/displayweave` GitHub repository.

## Branch and Repository Strategy

- Treat `https://github.com/chenyuhao0628/displayweave.git` as the publication
  remote. The `origin` remote remains the upstream OpenDisplay repository and
  must not receive this release.
- The root checkout is on local `main`, but the completed implementation is 25
  commits ahead on `codex/android-adb-usb`. Because `main` is the direct ancestor
  of that branch, integrate it by fast-forward after the publication changes
  have been completed and verified in the isolated worktree.
- Push the integrated local `main` to `displayweave/main` only after validation.
- Preserve the upstream ancestry and GPL attribution. Do not rewrite history or
  remove required OpenDisplay and SideScreen notices.

## Release Identity and Artifacts

The release tag is `v0.1.0-preview.2`. It is explicitly a development preview,
not a signed production release.

Release assets:

1. `DisplayWeave-Preview-0.1-Android.apk`
   - independently signed offline Android release APK;
   - installable without Google Play;
   - certificate fingerprint and v2 signature verification documented.
2. `DisplayWeave-Preview-0.1-macOS.zip`
   - universal ad-hoc signed macOS app;
   - not Developer ID signed and not notarized;
   - Gatekeeper caveats documented.
3. `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`
   - unsigned re-signing input only;
   - cannot be installed directly;
   - intended for users who perform their own lawful signing.
4. `SHA256SUMS.txt`
   - SHA-256 hashes for all three platform artifacts.

The release notes and website must use these exact filenames and must not link
to the obsolete Preview 1 debug APK or Simulator ZIP.

## Website Design: “Signal Weave Console”

### Brand Character

The site should express DisplayWeave as a cross-device signal fabric rather
than echoing OpenDisplay's minimal white product page. The visual language uses
an ink-blue canvas, cyan and electric-blue signal paths, fine technical grid
lines, asymmetric composition, and restrained motion. “Weaving” appears through
intersecting connection paths and device nodes, not through decorative fabric
illustration.

### Page Structure

1. **Compact navigation** — brand mark, product/status/download/navigation links,
   language switch, and GitHub link. It remains readable without becoming a
   floating card.
2. **Asymmetric hero** — concise product promise and primary download action on
   the left; a code-native live connection topology on the right showing one Mac
   linked to Apple and Android receiver nodes over USB and WiFi.
3. **Release rail** — three clearly separated platform downloads with install
   constraints shown before download. No misleading “production-ready” copy.
4. **Verified status board** — evidence-led capabilities grouped as verified,
   experimental, and deferred. It replaces generic marketing feature cards.
5. **Transport story** — a horizontal/stacked Auto flow: USB discovery, dynamic
   ADB forward, bounded recovery, same-install-ID WiFi fallback, and USB upgrade.
6. **Performance and input evidence** — verified HEVC/120 measurements, touch,
   two-finger scrolling, mixed iPhone/Android concurrency, and explicit caveats.
7. **Trust and origin** — local-first behavior, unencrypted trusted-LAN warning,
   GPL origin, OpenDisplay attribution, SideScreen notice, and build-from-source
   links.
8. **Focused FAQ and footer** — installation, signing, USB authorization,
   reconnect, limitations, issue reporting, and repository links.

Both English and Simplified Chinese pages share the same component structure and
facts. Copy may be idiomatic rather than mechanically translated.

### Design System

- Background: deep ink blue, not white or cream.
- Surfaces: mostly open bands and grid regions; bordered panels only for status
  or download units where containment carries meaning.
- Accents: cyan for active signal, electric blue for primary actions, soft green
  for verified state, amber for preview limitations.
- Typography: system sans for prose and display headings; system monospace for
  transport labels, measurements, versions, and status fields.
- Geometry: squared or lightly rounded technical surfaces; avoid the large,
  soft, white card grid associated with the previous site.
- Motion: subtle path pulses and status transitions with a complete
  `prefers-reduced-motion` fallback.
- Accessibility: semantic landmarks, keyboard-visible controls, sufficient
  contrast, meaningful link labels, and no information communicated by color
  alone.

### Interaction and Responsive Behavior

- Download links point directly at the Preview 2 GitHub Release assets.
- Language navigation preserves English at `/` and Chinese at `/zh.html`.
- GitHub star count remains optional progressive enhancement; page meaning does
  not depend on the API request succeeding.
- On narrow screens, the topology becomes a vertical connection stack, the
  download rail becomes one column, navigation condenses without hiding the
  language or download action, and all tables become readable stacked rows.
- No central visual relies on rasterized UI text. Existing product screenshots
  may be retained only when they demonstrate genuine app behavior and have clear
  provenance.

## Documentation Update Scope and Language Policy

All current, user-facing documentation must be available in both English and
Simplified Chinese. English remains the canonical unsuffixed filename; Chinese
uses a matching `.zh-CN.md` filename, except for the established root
`README.zh-CN.md`. Each paired document must link to its counterpart at the top.
The two versions must carry the same capabilities, limitations, commands,
release filenames, verification results, and security warnings; translation may
be idiomatic but may not weaken caveats.

Update all user-facing facts and cross-links in:

- `README.md` and `README.zh-CN.md`;
- `ARCHITECTURE.md`, `ROADMAP.md`, `SECURITY.md`, and `CONTRIBUTING.md` where
  current release behavior changes their claims, together with matching
  `ARCHITECTURE.zh-CN.md`, `ROADMAP.zh-CN.md`, `SECURITY.zh-CN.md`, and
  `CONTRIBUTING.zh-CN.md`;
- `AndroidReceiver/README.md`;
- release checklist, stability report, performance audit, benchmark protocol,
  brand audit, development preview guide, and Preview 0.1 release notes;
- website metadata, structured data, social description, and release links;
- GitHub release notes.

The Android receiver guide and each current user-facing document under `docs/`
must also have an English/Chinese pair. Historical design specifications and
implementation plans are development records rather than user instructions;
they may remain in their authored language, but the main documentation index
must label them as historical/internal records and must not rely on them as the
only explanation of a current feature.

The documentation must distinguish:

- verified on the available OnePlus Android device and current iPhone;
- implemented but not validated with two Android devices;
- explicitly deferred 30-minute and 2-hour endurance tests;
- benchmark protocol prepared but controlled USB/WiFi comparison not yet run;
- public offline Android signing versus ad-hoc macOS and unsigned iOS input.

Obsolete claims that Android USB, reconnect, APK signing, touch, scrolling, or
mixed-device concurrency are still wholly unvalidated must be removed.

## Implementation Boundaries

- Reuse the existing React/Vite/prerender structure; do not introduce a new web
  framework or external runtime service.
- Keep the site static and GitHub Pages compatible.
- Use code-native layout, topology, icons, and animation. No stock imagery or
  copied OpenDisplay layout assets.
- Do not change streaming behavior as part of the publication redesign.
- Do not claim completed two-Android, controlled benchmark, or endurance tests.
- Do not imply App Store, Google Play, notarized, or production signing support.

## Verification and Publication Gates

Before publishing:

1. Run the web production build and prerender checks.
2. Inspect English and Chinese pages at desktop and mobile widths, including
   navigation, download URLs, overflow, focus states, and reduced motion.
3. Compare the rendered site against this written design across layout,
   typography, palette, topology, release rail, status hierarchy, and mobile
   behavior; record and fix discrepancies.
4. Run the relevant Swift policy self-tests, Android unit/self-tests, release
   packaging script, APK signature verification, checksums, and
   `git diff --check`.
5. Confirm every website artifact URL exactly matches an uploaded Release asset.
6. Confirm the worktree is clean after the publication commit.
7. Fast-forward local `main`, push `main` to the `displayweave` remote, create
   GitHub Release `v0.1.0-preview.2`, upload the four assets, and confirm the
   GitHub Pages workflow succeeds.

If any gate fails, fix and rerun it before claiming publication complete.

## Success Criteria

- GitHub's default `main` contains all verified Android USB/reconnect work,
  current bilingual documentation, and the redesigned bilingual website.
- Every current user-facing guide provides direct English/Chinese navigation,
  with factual parity verified before publication.
- The site is visually and structurally distinct from the inherited OpenDisplay
  page while retaining legally required attribution.
- Preview 2 download links resolve to the exact published assets.
- The GitHub Release communicates installation and signing limitations before
  download.
- Build, test, packaging, signature, checksum, responsive, and Pages deployment
  checks are recorded with no unresolved release-blocking failures.
