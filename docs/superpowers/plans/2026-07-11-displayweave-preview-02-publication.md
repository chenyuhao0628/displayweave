# DisplayWeave Preview 0.1.0-preview.2 Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the verified Android USB/reconnect work, a fully bilingual documentation set, and an independently designed DisplayWeave website as GitHub Release `v0.1.0-preview.2` on `chenyuhao0628/displayweave`.

**Architecture:** Keep the existing React/Vite static-site and prerender pipeline, but split copy, topology, release, evidence, and trust surfaces into focused components driven by one typed bilingual content model. Treat documentation facts and release filenames as release inputs, validate them locally, then fast-forward the verified feature branch into local `main`, push only to the `displayweave` remote, upload artifacts, and verify Pages and Release remotely.

**Tech Stack:** React 19, TypeScript, Vite 8, CSS, Motion, Markdown, Swift/Xcode, Gradle/Android, Bash packaging, GitHub CLI and GitHub Actions.

---

## File Map

- `src/content.ts`: typed English/Chinese product, release, evidence, FAQ, and legal copy.
- `src/components/SignalTopology.tsx`: code-native Mac/receiver transport visualization.
- `src/components/ReleaseRail.tsx`: exact Preview 2 download assets and limitations.
- `src/components/StatusBoard.tsx`: verified/experimental/deferred evidence groups.
- `src/components/TransportFlow.tsx`: Auto USB recovery/fallback/upgrade sequence.
- `src/App.tsx`: page composition, locale selection, navigation, and optional star count.
- `src/index.css`: complete Signal Weave Console tokens, layout, motion, accessibility, and responsive behavior.
- `index.html`, `public/robots.txt`, `public/sitemap.xml`: bilingual release metadata and discovery.
- `README*.md`, root `*.md`, `AndroidReceiver/README*.md`, `docs/*.md`: paired user documentation and release facts.
- `tools/check-bilingual-docs.sh`: deterministic pair/link/fact checks for current public documentation.
- `tools/check-release-links.sh`: verify site filenames and tag match the packaged release directory.
- `build/preview-0.1/`: package-script output uploaded to GitHub Release.

### Task 1: Lock Release Facts with Failing Checks

**Files:**
- Create: `tools/check-bilingual-docs.sh`
- Create: `tools/check-release-links.sh`
- Modify: `package.json`

- [ ] **Step 1: Write a bilingual-document checker that declares the required pairs**

The script must use `set -euo pipefail`, enumerate root and current `docs/` English files, require the `.zh-CN.md` peer, and require reciprocal language links. Historical files in `docs/superpowers/` and the explicitly historical `android-usb-transport-design.md` are excluded.

- [ ] **Step 2: Run the checker and verify it fails**

Run: `./tools/check-bilingual-docs.sh`

Expected: non-zero with the first missing Chinese peer, such as `ARCHITECTURE.zh-CN.md`.

- [ ] **Step 3: Write a release-link checker**

Require `v0.1.0-preview.2` and the exact APK, macOS ZIP, unsigned IPA, and checksum filenames in site content and release notes. Reject old `preview.1`, debug APK, and Simulator ZIP download claims.

- [ ] **Step 4: Add `check:docs` and `check:release` scripts to `package.json`**

Use direct shell commands so CI and maintainers run the same checks.

- [ ] **Step 5: Commit the red checks**

```bash
git add tools/check-bilingual-docs.sh tools/check-release-links.sh package.json
git commit -m "test: define Preview 2 publication facts"
```

### Task 2: Build the Typed Bilingual Content Model

**Files:**
- Create: `src/content.ts`
- Modify: `src/App.tsx`

- [ ] **Step 1: Move all visible English and Chinese copy into typed content**

Define `Locale`, `ReleaseAsset`, `EvidenceItem`, and `SiteCopy`; export `releaseTag`, `releaseBase`, `releaseAssets`, and `copy`. Encode exact Preview 2 filenames and matching limitations once per locale.

- [ ] **Step 2: Make TypeScript expose missing content**

Temporarily switch `App.tsx` imports to `content.ts` before components exist.

Run: `pnpm build`

Expected: FAIL on unresolved new component/layout references or missing typed fields.

- [ ] **Step 3: Remove stale Preview 1 and obsolete validation claims**

Facts must reflect verified USB HEVC/120, H.264/60, reconnect, authorization recovery, touch, two-finger scrolling, iPhone/Android concurrency, and deferred two-Android/endurance/controlled benchmark work.

- [ ] **Step 4: Commit the content model**

```bash
git add src/content.ts src/App.tsx
git commit -m "feat: define bilingual Preview 2 site content"
```

### Task 3: Implement Signal Weave Components

**Files:**
- Create: `src/components/SignalTopology.tsx`
- Create: `src/components/ReleaseRail.tsx`
- Create: `src/components/StatusBoard.tsx`
- Create: `src/components/TransportFlow.tsx`
- Modify: `src/App.tsx`

- [ ] **Step 1: Implement the semantic connection topology**

Render one Mac source, wired Android, WiFi Android fallback, and Apple receiver nodes with accessible labels. Use SVG paths only for connectors; all labels remain HTML.

- [ ] **Step 2: Implement the exact release rail**

Render platform, signing/install limitation, checksum context, and direct GitHub Release link for every asset. The iOS action must say “Download re-signing input,” not imply installability.

- [ ] **Step 3: Implement status and transport evidence**

Group evidence into verified, experimental, and deferred. Render Auto as wired discovery → dynamic local port → bounded recovery → same-install-ID WiFi fallback → USB upgrade.

- [ ] **Step 4: Compose the new page in `App.tsx`**

Use header, hero, release, status, transport, performance/input, trust/origin, FAQ, and footer landmarks. Keep optional GitHub star fetching non-blocking.

- [ ] **Step 5: Run the production build**

Run: `pnpm build`

Expected: PASS with prerendered `/index.html` and `/zh.html` in `site-dist/`.

- [ ] **Step 6: Commit the component structure**

```bash
git add src/App.tsx src/content.ts src/components/SignalTopology.tsx src/components/ReleaseRail.tsx src/components/StatusBoard.tsx src/components/TransportFlow.tsx
git commit -m "feat: rebuild site around DisplayWeave signal topology"
```

### Task 4: Implement and Audit the Independent Visual System

**Files:**
- Modify: `src/index.css`
- Modify: `index.html`
- Modify: `public/robots.txt`
- Modify: `public/sitemap.xml`

- [ ] **Step 1: Replace inherited white-page styles**

Define ink-blue background, cyan/electric-blue/green/amber status tokens, open grid bands, technical monospace labels, asymmetric hero, square-light geometry, visible focus states, and high-contrast controls.

- [ ] **Step 2: Add restrained signal motion and reduced-motion fallback**

Animate path dash offset and live indicators only. Under `prefers-reduced-motion: reduce`, remove all nonessential transitions and animations.

- [ ] **Step 3: Add responsive topology, release rail, nav, and evidence layouts**

Verify no horizontal overflow at 390px and 500px; preserve language and download access in compact navigation.

- [ ] **Step 4: Update metadata**

Use Preview 2 descriptions, canonical GitHub Pages URLs, bilingual alternates, and accurate Open Graph language/product text.

- [ ] **Step 5: Run build and inspect browser screenshots**

Run `pnpm build`, `pnpm preview --host 127.0.0.1 --port 4174`, then capture English/Chinese at 1440×1000 and 390×844. Inspect with `view_image` for layout, typography, palette, topology, release rail, status hierarchy, mobile behavior, and untranslated/stale copy.

- [ ] **Step 6: Record the fidelity ledger**

Add a short table to `docs/branding-and-doc-audit.md` covering at least palette, layout, typography, topology, release rail, responsive behavior, and intentional deviations. Fix every release-blocking mismatch.

- [ ] **Step 7: Commit visual implementation**

```bash
git add src/index.css index.html public/robots.txt public/sitemap.xml docs/branding-and-doc-audit.md
git commit -m "feat: establish independent Signal Weave site design"
```

### Task 5: Rewrite Root and Android Guides as Bilingual Pairs

**Files:**
- Modify: `README.md`, `README.zh-CN.md`
- Modify: `ARCHITECTURE.md`, `ROADMAP.md`, `SECURITY.md`, `CONTRIBUTING.md`
- Create: `ARCHITECTURE.zh-CN.md`, `ROADMAP.zh-CN.md`, `SECURITY.zh-CN.md`, `CONTRIBUTING.zh-CN.md`
- Modify: `AndroidReceiver/README.md`
- Create: `AndroidReceiver/README.zh-CN.md`

- [ ] **Step 1: Add reciprocal language navigation to every pair**

Use `[English](...) | [简体中文](...)` at the top with correct relative paths.

- [ ] **Step 2: Align product and release facts**

Document exact Preview 2 assets, Auto/USB/WiFi behavior, reconnect triggers, signing limits, trusted-LAN warning, measured 109–111 FPS boundary, current validation, and explicit deferred tests.

- [ ] **Step 3: Preserve license and origin attribution in both languages**

Keep OpenDisplay derivation, GPL-3.0, and SideScreen reference facts equivalent.

- [ ] **Step 4: Run bilingual and release checks**

Run: `pnpm run check:docs && pnpm run check:release`

Expected: still FAIL only for untranslated current `docs/` files, not root or Android guides.

- [ ] **Step 5: Commit the guide pairs**

```bash
git add README.md README.zh-CN.md ARCHITECTURE.md ARCHITECTURE.zh-CN.md ROADMAP.md ROADMAP.zh-CN.md SECURITY.md SECURITY.zh-CN.md CONTRIBUTING.md CONTRIBUTING.zh-CN.md AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
git commit -m "docs: publish bilingual project and Android guides"
```

### Task 6: Publish Current `docs/` in Both Languages

**Files:**
- Modify: current user-facing `docs/*.md`
- Create: matching current `docs/*.zh-CN.md`
- Create: `docs/README.md`
- Create: `docs/README.zh-CN.md`

- [ ] **Step 1: Classify current versus historical documents in the index**

Current guides include development preview, release checklist/notes, stability, performance, benchmark, branding/brand assets, 120Hz migration evidence, and roadmap/acceptance. Design and implementation records are listed separately as historical/internal.

- [ ] **Step 2: Create paired current guides with reciprocal links**

Translate the full operative content, commands, tables, limits, and results. Keep filenames, hashes, certificate fingerprint, timeouts, and numeric measurements identical.

- [ ] **Step 3: Remove stale status claims in both languages**

Do not say USB physical testing, APK signing, reconnect, touch, scrolling, or mixed concurrency remain wholly pending. Continue to mark two Android devices, controlled benchmark, and endurance runs incomplete.

- [ ] **Step 4: Run factual parity scans**

Use `rg` for release tag, filenames, `109`, `111`, `26`, `30`, `2 小时|2 hours`, `SHA256`, and signing warnings across both language sets; fix asymmetry.

- [ ] **Step 5: Make document checks pass**

Run: `pnpm run check:docs && pnpm run check:release`

Expected: PASS.

- [ ] **Step 6: Commit bilingual documentation**

```bash
git add docs
git commit -m "docs: align bilingual Preview 2 documentation"
```

### Task 7: Rebuild and Verify Release Artifacts

**Files:**
- Modify if required: `tools/package-preview-0.1.sh`
- Generated: `build/preview-0.1/*`

- [ ] **Step 1: Run policy and protocol tests**

Run all seven Swift standalone self-tests and four Android standalone self-tests using the commands documented in `docs/release-checklist.md`.

Expected: 11 PASS results.

- [ ] **Step 2: Run the full packaging workflow**

Run: `./tools/package-preview-0.1.sh`

Expected: macOS Release build, unsigned iOS re-signing input, Android `clean test assembleRelease`, APK v2 verification, and four output files.

- [ ] **Step 3: Verify signatures, archive hygiene, and hashes**

Run `codesign --verify --deep --strict`, `apksigner verify --verbose --print-certs`, inspect IPA entries for only `Payload/` without `._` or `__MACOSX`, and run `shasum -a 256 -c SHA256SUMS.txt`.

- [ ] **Step 4: Update release evidence in both languages**

Record final hashes, test results, ad-hoc/unsigned/offline-keystore status, and the current date without claiming deferred physical tests.

- [ ] **Step 5: Commit packaging/document evidence**

```bash
git add tools/package-preview-0.1.sh docs README.md README.zh-CN.md
git commit -m "release: finalize Preview 2 artifacts and evidence"
```

### Task 8: Final Local Verification and Branch Integration

**Files:**
- Verify all tracked publication changes.

- [ ] **Step 1: Run final static checks**

Run `pnpm build`, both document checks, `git diff --check`, and scan for obsolete Preview 1 asset links.

- [ ] **Step 2: Verify worktree status and commit history**

Require a clean `codex/android-adb-usb` worktree and confirm local root `main` is still an ancestor.

- [ ] **Step 3: Fast-forward root `main`**

In `/Users/cyh/Documents/opendisplay`, run `git merge --ff-only codex/android-adb-usb`. Do not merge into or push to upstream `origin`.

- [ ] **Step 4: Re-run status and release-link checks on root `main`**

Expected: clean `main`, same HEAD as the feature branch, all checks PASS.

### Task 9: Push, Release, and Verify GitHub

**Files:**
- Remote repository and release state only.

- [ ] **Step 1: Verify GitHub authentication and repository default branch**

Run `gh auth status` and `gh repo view chenyuhao0628/displayweave --json defaultBranchRef,nameWithOwner,url`.

- [ ] **Step 2: Push only to the maintainer repository**

Run: `git push displayweave main`

Expected: `displayweave/main` advances to local `main`.

- [ ] **Step 3: Create and upload Preview 2 Release**

Create `v0.1.0-preview.2` as a prerelease using bilingual release notes, then upload the APK, macOS ZIP, unsigned IPA, and `SHA256SUMS.txt` from `build/preview-0.1/`.

- [ ] **Step 4: Verify published asset names and checksums**

Use `gh release view v0.1.0-preview.2 --repo chenyuhao0628/displayweave --json assets,isPrerelease,tagName,url` and compare remote asset names/sizes with local files.

- [ ] **Step 5: Verify Pages deployment**

Inspect the `pages.yml` run for the pushed commit, wait for completion, then request `/` and `/zh.html` and confirm Preview 2 tag and exact asset URLs.

- [ ] **Step 6: Publish completion evidence**

Report branch/commit, release URL, Pages URL, asset hashes, checks executed, current known limitations, and confirmation that `origin` was untouched.
