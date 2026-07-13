# DisplayWeave v0.2.0 Preview 1 Bilingual Documentation Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every current English and Simplified Chinese user entry point describe and download the live `v0.2.0-preview.1` prerelease while preserving Preview 2 records as historical evidence.

**Architecture:** Treat release facts as a tested contract in `tools/check-release-links.sh`, then update documents in responsibility-based bilingual groups: top-level onboarding, platform installation, release operations, and website metadata. Add a new release-note pair instead of rewriting the old Preview 2 notes, and finish by comparing rendered/download URLs with the live GitHub Release and Pages feeds.

**Tech Stack:** Markdown, TypeScript content data, HTML metadata/JSON-LD, Bash release checks, Vite/React static rendering, GitHub Releases, GitHub Pages.

---

## File Structure

- Modify `tools/check-release-links.sh`: define current tag/assets and reject stale current-entry downloads.
- Modify `tools/check-bilingual-docs.sh`: require the new release-note pair.
- Modify `README.md` and `README.zh-CN.md`: current capabilities, downloads, and migration summary.
- Modify `AndroidReceiver/README.md` and `AndroidReceiver/README.zh-CN.md`: current APK and in-app update flow.
- Modify `docs/development-preview.md` and `docs/development-preview.zh-CN.md`: current installation/signing boundary.
- Create `docs/release-notes-v0.2.0-preview.1.md` and `docs/release-notes-v0.2.0-preview.1.zh-CN.md`: complete current release notes.
- Modify `docs/README.md` and `docs/README.zh-CN.md`: current and historical release-note routing.
- Modify `docs/automatic-updates.md` and `docs/automatic-updates.zh-CN.md`: identify the live migration release.
- Modify `docs/release-checklist.md` and `docs/release-checklist.zh-CN.md`: current release evidence and post-release checks.
- Modify `src/content.ts`: bilingual website release tag, assets, update copy, and CTA labels.
- Modify `index.html`: current title, descriptions, social metadata, and JSON-LD download URL.

### Task 1: Lock the new release contract before editing prose

**Files:**
- Modify: `tools/check-release-links.sh`
- Modify: `tools/check-bilingual-docs.sh`

- [ ] **Step 1: Change the active release contract**

Set the current tag and assets in `tools/check-release-links.sh` to:

```bash
tag="v0.2.0-preview.1"
assets=(
  "DisplayWeave-Android.apk"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa"
  "appcast.xml"
  "android-update.json"
  "SHA256SUMS.txt"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/development-preview.md docs/development-preview.zh-CN.md
  docs/release-notes-v0.2.0-preview.1.md
  docs/release-notes-v0.2.0-preview.1.zh-CN.md
  docs/release-checklist.md docs/release-checklist.zh-CN.md
  docs/automatic-updates.md docs/automatic-updates.zh-CN.md
)
```

Require the Release URL, both live feed URLs, and these exact hashes:

```text
35c828abc9200affe8a63602519f63e56ca7aff4ca6a88d6bbcb2f2bf009bec5
24588906ccde36958355d8e72bae54fa1e6f8244c3fca832b81c9a05bd7519d9
fee1b7d8c1b81bac33b91b11dfaeeb608ccc35050ccc4bcd796178227acdedfa
```

Reject `v0.1.0-preview.2`, `DisplayWeave-Preview-0.1-macOS.zip`, and
`DisplayWeave-Preview-0.1-Android.apk` only inside the active `sources` list.
Do not scan old release notes, stability reports, design specs, or plans.

- [ ] **Step 2: Register the new bilingual release-note pair**

Add this entry to `pairs` in `tools/check-bilingual-docs.sh`:

```bash
"docs/release-notes-v0.2.0-preview.1.md:docs/release-notes-v0.2.0-preview.1.zh-CN.md"
```

- [ ] **Step 3: Run the checks and verify RED**

Run:

```bash
./tools/check-release-links.sh
./tools/check-bilingual-docs.sh
```

Expected: failures because the new release-note files do not exist and active
documents still contain Preview 2 downloads.

- [ ] **Step 4: Commit only the contract change**

```bash
git add tools/check-release-links.sh tools/check-bilingual-docs.sh
git commit -m "test: define v0.2 bilingual publication facts"
```

### Task 2: Update top-level and Android onboarding

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `AndroidReceiver/README.md`
- Modify: `AndroidReceiver/README.zh-CN.md`
- Modify: `docs/development-preview.md`
- Modify: `docs/development-preview.zh-CN.md`

- [ ] **Step 1: Update the root README pair**

Replace the current download section with tag `v0.2.0-preview.1` and stable
Mac/Android filenames. Add the same factual migration block in both languages:

```markdown
- Mac: manually install this migration build in `/Applications`; later signed
  updates use Sparkle. The app remains ad-hoc signed and not notarized.
- Android: install this APK over the existing package once; later downloads are
  verified in-app and still require Android system installation confirmation.
- iOS/iPadOS: the unsigned re-signing input and existing receiver protocol are
  unchanged by the Mac/Android update channel.
```

Retain the existing capability/evidence language and deferred-test boundary.

- [ ] **Step 2: Update the Android README pair**

Point installation to `DisplayWeave-Android.apk` in the new Release. Document:

```text
automatic check: at most once per 24 hours on resume
manual check: 设置与帮助 / Settings & Help → 检查更新 / Check for Updates
verification: size + SHA-256 + package + version + minSdk + pinned certificate
installation: unknown-source permission when needed + final system confirmation
```

Keep USB/WiFi behavior and hardware evidence unchanged and identify it as prior
validated behavior rather than a new physical rerun.

- [ ] **Step 3: Update the development-preview pair**

Use all current asset names, hashes, Release URL, both feed URLs, and the fixed
Android certificate. Explain the first-install migration and state explicitly
that Mac is not notarized, Android is not a silent installer, and iOS is not
directly installable.

- [ ] **Step 4: Run focused stale-reference checks**

Run:

```bash
rg -n "v0\.1\.0-preview\.2|DisplayWeave-Preview-0\.1-(macOS|Android)" \
  README.md README.zh-CN.md AndroidReceiver/README.md \
  AndroidReceiver/README.zh-CN.md docs/development-preview.md \
  docs/development-preview.zh-CN.md
```

Expected: no matches.

- [ ] **Step 5: Commit onboarding updates**

```bash
git add README.md README.zh-CN.md AndroidReceiver/README.md \
  AndroidReceiver/README.zh-CN.md docs/development-preview.md \
  docs/development-preview.zh-CN.md
git commit -m "docs: update bilingual v0.2 installation guides"
```

### Task 3: Add current bilingual release notes and document routing

**Files:**
- Create: `docs/release-notes-v0.2.0-preview.1.md`
- Create: `docs/release-notes-v0.2.0-preview.1.zh-CN.md`
- Modify: `docs/README.md`
- Modify: `docs/README.zh-CN.md`
- Modify: `docs/automatic-updates.md`
- Modify: `docs/automatic-updates.zh-CN.md`

- [ ] **Step 1: Write the English release notes**

Use these exact sections:

```markdown
# DisplayWeave `v0.2.0-preview.1` Release Notes
## Highlights
## One-time migration and later updates
## Security and distribution boundaries
## iOS/OpenDisplay compatibility
## Assets and SHA-256
## Verification evidence
## Deferred validation
```

Include the six assets, three installable/input artifact hashes, fixed Android
certificate, Release URL, and two live feed URLs. State that the one-byte Mac
and Android tamper fixtures were rejected, but do not claim new long-duration
or two-Android physical testing.

- [ ] **Step 2: Write the Chinese release notes with identical facts**

Use the matching sections:

```markdown
# DisplayWeave `v0.2.0-preview.1` 发布说明
## 主要更新
## 一次性迁移与后续更新
## 安全与分发边界
## iOS/OpenDisplay 兼容性
## 产物与 SHA-256
## 验证证据
## 尚未完成的验证
```

Add the reciprocal language links at the top of both files.

- [ ] **Step 3: Route current and historical notes from the docs index**

Make the new pair the first current release-note link in both docs indexes.
Keep the old `release-notes-preview-0.1*` link under a label such as
“Historical Preview 2 release notes / 历史 Preview 2 发布说明”.

- [ ] **Step 4: Mark the live migration release in automatic-update guides**

Add a “Current channel / 当前渠道” paragraph naming `v0.2.0-preview.1`, linking
to its Release, and stating that users of older builds must manually install it
before future automatic updates work.

- [ ] **Step 5: Run the bilingual check**

Run: `./tools/check-bilingual-docs.sh`

Expected: `bilingual documentation check passed: 21 pairs`.

- [ ] **Step 6: Commit release-note and routing updates**

```bash
git add docs/release-notes-v0.2.0-preview.1.md \
  docs/release-notes-v0.2.0-preview.1.zh-CN.md docs/README.md \
  docs/README.zh-CN.md docs/automatic-updates.md \
  docs/automatic-updates.zh-CN.md
git commit -m "docs: add bilingual v0.2 release notes"
```

### Task 4: Replace the current release checklist without rewriting history

**Files:**
- Modify: `docs/release-checklist.md`
- Modify: `docs/release-checklist.zh-CN.md`

- [ ] **Step 1: Make both checklists describe the live release**

Use `v0.2.0-preview.1`, build `2`, source commit `bb50d91`, Pages publication
commit `b8e22c8`, six exact assets, three artifact hashes, fixed certificate, and
Pages run `29269282121`. Retain these release boundaries:

```text
Mac: ad-hoc, not notarized
Android: v2, one signer, system-confirmed installation
iOS: unsigned arm64 re-signing input
Deferred: two Android devices, controlled USB/WiFi matrix, 30 min, 2 h
```

Move old Preview 0.1-specific measurements out of the current identity section;
link to the historical stability report rather than changing that report.

- [ ] **Step 2: Verify checklist parity**

Run:

```bash
rg -n "v0.2.0-preview.1|bb50d91|b8e22c8|29269282121|DisplayWeave-macOS.zip|DisplayWeave-Android.apk" \
  docs/release-checklist.md docs/release-checklist.zh-CN.md
```

Expected: every marker appears in both files.

- [ ] **Step 3: Commit checklist updates**

```bash
git add docs/release-checklist.md docs/release-checklist.zh-CN.md
git commit -m "docs: record v0.2 release verification"
```

### Task 5: Update the bilingual website and SEO metadata

**Files:**
- Modify: `src/content.ts`
- Modify: `index.html`

- [ ] **Step 1: Update central website release data**

Set:

```ts
export const releaseTag = "v0.2.0-preview.1"
```

Use stable `DisplayWeave-macOS.zip` and `DisplayWeave-Android.apk` filenames;
keep the current iOS input filename. Update English and Chinese asset copy to
include the migration/automatic-update behavior and system confirmation limits.
Change Preview 2 CTAs to `Get v0.2 Preview / 获取 v0.2 预览版` without changing
the evidence claims for transports and hardware.

- [ ] **Step 2: Update static metadata and JSON-LD**

Change `index.html` title, description, Open Graph, Twitter, and JSON-LD release
URL to `v0.2.0-preview.1`. Descriptions may say that v0.2 adds signed Mac and
verified Android update channels while preserving iPhone/iPad compatibility.

- [ ] **Step 3: Build and inspect rendered output**

Run:

```bash
pnpm build
rg -n "v0.2.0-preview.1|DisplayWeave-macOS.zip|DisplayWeave-Android.apk" \
  site-dist/index.html site-dist/zh.html
```

Expected: both rendered pages contain the new tag and exact stable asset names.

- [ ] **Step 4: Commit website updates**

```bash
git add src/content.ts index.html
git commit -m "docs(web): publish bilingual v0.2 downloads"
```

### Task 6: Run the full consistency and live-release verification

**Files:**
- Verify all files above; do not modify historical plans/reports.

- [ ] **Step 1: Run all local documentation gates**

Run:

```bash
./tools/check-bilingual-docs.sh
./tools/check-release-links.sh
pnpm run check:docs
pnpm run check:release
pnpm build
git diff --check
```

Expected: every command exits zero; bilingual check reports 21 pairs.

- [ ] **Step 2: Audit active versus historical references**

Run stale-reference search only across current entry points and expect no old
tag or old Mac/Android filenames. Separately confirm historical release notes,
stability reports, specs, and plans remain tracked and unmodified.

- [ ] **Step 3: Verify live GitHub facts**

Use `gh release view v0.2.0-preview.1` to require prerelease state and six exact
assets. Fetch both Pages feeds, require current version/tag, and run:

```bash
./tools/verify-update-release.sh --android-metadata \
  /tmp/displayweave-live-android-update.json \
  build/automatic-update-final/DisplayWeave-Android.apk \
  0.2.0-preview.1 2 \
  89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

Expected: release and feed facts match the documentation.

- [ ] **Step 4: Final status and push**

Run `git status --short`, confirm only intended documentation commits exist,
then push `main` to `displayweave`. Wait for the Pages run and confirm both
rendered language pages contain the new tag and asset URLs.
