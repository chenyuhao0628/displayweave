# DisplayWeave GitHub Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the verified Mac, iOS, and Android codebase as the public `chenyuhao0628/displayweave` GitHub repository under the DisplayWeave brand.

**Architecture:** Rebrand user-visible product and repository surfaces while retaining bundle identifiers, Java packages, Xcode schemes, class names, and Bonjour service types needed for compatibility. Preserve GPL-3.0 origin attribution, document SideScreen as an MIT-licensed design reference, and publish the existing history to a new repository rather than rewriting upstream history.

**Tech Stack:** Markdown, Swift/SwiftUI, Android Java/Gradle, XcodeGen, Git, GitHub CLI.

---

### Task 1: Establish publication metadata

**Files:**
- Modify: `README.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Move: `DisplayWeave_后续开发与验收目标_Codex提示词.md` to `docs/roadmap-and-acceptance.md`

- [ ] Replace fork-style README positioning with the approved DisplayWeave English and Chinese positioning.
- [ ] State experimental Android high-refresh support accurately and include the measured 109-111 FPS result.
- [ ] Add GPL-3.0 OpenDisplay origin attribution and MIT SideScreen design-reference notice.
- [ ] Link build, Android receiver, migration, and roadmap documentation.

### Task 2: Update user-visible product branding

**Files:**
- Modify: `project.yml`
- Modify: `Mac/OpenSidecarMacApp.swift`
- Modify: `Mac/MacSender.swift`
- Modify: `Mac/Usbmux.swift`
- Modify: `iOS/Info.plist`
- Modify: `iOS/OpenSidecarPhoneApp.swift`
- Modify: `iOS/PhoneReceiver.swift`
- Modify: `AndroidReceiver/app/src/main/AndroidManifest.xml`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/OpenDisplayServer.java`
- Modify: `AndroidReceiver/README.md`

- [ ] Change visible app names, instructions, and service labels to DisplayWeave.
- [ ] Point user-facing GitHub links at `chenyuhao0628/displayweave`.
- [ ] Keep bundle IDs, Android application ID/package, Xcode schemes, protocol classes, preferences, and `_opensidecar._tcp` unchanged.

### Task 3: Verify publication build

**Files:**
- Verify: all modified files

- [ ] Run `./gradlew clean`, `./gradlew assembleDebug`, and `./gradlew test` in `AndroidReceiver`.
- [ ] Regenerate the Xcode project with `./generate.sh`.
- [ ] Build `OpenSidecarMac` and `OpenSidecariOS` with `xcodebuild`.
- [ ] Run `git diff --check` and inspect staged scope.

### Task 4: Publish repository

**Files:**
- Commit all publication files.

- [ ] Commit with `docs: launch DisplayWeave project identity`.
- [ ] Create the public repository `chenyuhao0628/displayweave` without initializing replacement files.
- [ ] Add a `displayweave` remote and push the current branch history as the remote default `main` branch.
- [ ] Set the approved About description and repository topics.
- [ ] Verify the public repository, default branch, latest commit, README, license, and clean local worktree.
