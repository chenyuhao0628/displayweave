[English](development.md) | [简体中文](development.zh-CN.md)

# Development workflow

Reviewed: 2026-10-16. This guide applies to source development, not a new public release.

## Project instructions and official reference

`AGENTS.md` is the short repository instruction entry point. Contributor policy belongs in `CONTRIBUTING.md`; architecture, UI standards and acceptance evidence are linked documents, not copies of agent instructions. No personal Codex configuration is required or modified by this repository.

We read the current official OpenAI guidance on 2026-10-16 (the former developers.openai.com Codex URLs redirected to these pages):

- [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md): global instructions are followed by project instructions from root to working directory; nearer instructions take precedence. An `AGENTS.override.md` takes precedence over `AGENTS.md` in its directory. Keep instructions concise (default combined discovery budget: 32 KiB). Restart a session to reload changed instruction discovery.
- [Local environments](https://learn.chatgpt.com/docs/environments/local-environment): share project actions and worktree setup in `.codex/`. Our existing Run action uses `script/build_and_run.sh`.
- [Build skills](https://learn.chatgpt.com/docs/build-skills): use focused skills when their workflow fits the task. The repository does not require a particular installed plugin or model.

These are dated source references, not a promise that product documentation never changes. Check official documentation again before changing Codex-specific behavior. Repository instructions supplement the user request; they do not grant permission for unrelated publishing or external messaging.

## Setup and local verification

Prerequisites: macOS 14+, Xcode with the required SDKs, XcodeGen, Swift, Node/pnpm (version pinned in package.json), and Java 17 / Android SDK for Android builds.

```bash
xcodegen generate
pnpm install --frozen-lockfile
./script/build_and_run.sh --verify -macRole sender -autostart NO
./tools/run-swift-self-tests.sh
pnpm build
pnpm run check:docs
pnpm run check:release
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug)
```

The Run action starts an ad-hoc signed development application. To compile without launching:

```bash
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build-verify-mac CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecariOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build-verify-ios CODE_SIGNING_ALLOWED=NO build
```

## Change and completion gates

1. Record scope and observable acceptance before a broad refactor. Inventory all affected surfaces and compatibility boundaries.
2. Keep policy/state ownership separate from presentation. Add failing regression coverage before a behavior fix; use builds and visual review for presentation-only edits.
3. Run the affected platform checks, documentation checks and `git diff --check`; commit a coherent round. Run the full CI gate before integrating into main.
4. Refresh upstream, inspect useful changes and record accepted / already covered / deferred items with commit provenance. A clean textual merge is not evidence of behavior compatibility.
5. Report commit IDs, tests, remote state and remaining hardware gaps. Do not equate compilation, synthetic video, or simulator checks with physical LAN/USB endurance evidence.

A broad iteration is complete when its documented scope is implemented, automated checks pass, UI states have been inspected where tooling permits, remote changes are synchronized, and hardware-dependent gaps have an explicit acceptance procedure. It does not automatically authorize a public release.

## Interactive testing

Use `tools/run-mac-receiver-window-test.sh` only in a usable desktop session. Virtual-display creation/removal requires an independent online display. With the lid closed and no independent display, skip it; do not repeatedly create test displays or restart WindowServer. Check current online-list membership to assess removal; retired display IDs are not reliable liveness probes.

Keep screenshots and full logs outside Git. Record reproducible commands and sanitized results in the relevant audit. Hardware evidence must include model, OS, connection type, resolution, codec, target and rendered FPS, duration and reconnect behavior.

## Current verification coverage

`tools/run-swift-self-tests.sh` runs 48 standalone suites. Android `test` includes six plain-Java groups. `pnpm build` runs TypeScript, client/SSR production builds, bilingual prerendering and generated-site assertions. Run both Apple target builds after adding shared source files.

`python3 tools/test-apple-keychain.py --ios-simulator` exercises real Mac/iOS Keychain identity persistence, missing-key recovery and explicit reset in random test namespaces. `python3 tools/test-secure-ios-receiver.py` builds an isolated app from the production PhoneReceiver/security code, sends synthetic video over authenticated TLS, checks revocation and backgrounds the app. Both create/delete their own simulator and leave installed applications untouched. Use `--screenshots build/security-ui` on the latter for light/dark settings evidence after its test invitation has been consumed. Run simulator suites sequentially to avoid competing cold boots; no desktop capture or virtual display is involved.

For the older opt-in plaintext iOS network smoke test, launch an isolated Simulator app with `-insecureLegacyReceiver YES`, keep it foregrounded, then run `python3 tools/test-ios-receiver.py --port 9000`. Relaunch without that argument after testing. The initial listener wait is bounded to 10 seconds; the test sends invalid lengths and fragmented controls, replaces connections and checks liveness. It intentionally disconnects its test peers, does not capture the desktop and does not prove video performance. Background the app separately and verify that port 9000 closes.

See [the 2026-10-16 audit](source-upgrade-audit-2026-10-16.md) for actual local UI/build evidence and pending hardware work.

`python3 tools/test-secure-android-receiver.py --screenshots build/security-ui` requires SDK command-line tools and `system-images;android-35;default;arm64-v8a`. It creates/deletes its own AVD and builds a separate test package from production sources. Real Keystore keys exercise TLS; a Mac client then uses the production pairing/revocation/legacy UI over an owned ADB forward. Test identities and invitations are confined to the disposable app/container; screenshots are taken after invitation consumption.
