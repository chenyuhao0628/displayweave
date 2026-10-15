# DisplayWeave project instructions

## Start here
- Read `CONTRIBUTING.md`, `ARCHITECTURE.md`, and the relevant current guide in `docs/README.md`.
- This is the repository instruction entry point. Historical plans describe past decisions, not mandatory current workflows. User instructions take precedence over repository guidance.
- Read `docs/development.md` for commands and evidence requirements; read `docs/ui-guidelines.md` before UI changes once that document exists.

## Contracts
- Public name: DisplayWeave. Preserve OpenSidecar project/target names, bundle/package IDs, preferences, Bonjour service, wire framing, and update/signing identities unless explicitly migrating them with compatibility coverage.
- Preserve GPL-3.0 and upstream attribution. Integrate upstream selectively after checking conflicts and behavior; never overwrite project signing keys, feeds, branding or Android recovery policies by accident.
- Sender and receiver roles on one Mac are exclusive. Each session owns its transports and resources; stale callbacks must not change a replacement session.
- Keep queues, allocations, frame sizes, retries, and network waits bounded. TCP connect alone is not protocol readiness.

## Workflow
- Inspect status before editing; preserve unrelated work. Use `codex/` for new branches. The working remote is `displayweave`; `origin` is upstream. Verify remote URLs before pushing.
- Make coherent, reviewable changes. Add a regression test for a behavior fix; do not invent tests that just repeat static UI structure. Run relevant checks before each commit and the full regression gate before integrating.
- Keep user-facing guides in English / Simplified Chinese pairs with reciprocal links. Record implementation, automated verification, physical verification and deferred work separately.
- Generate the Xcode project from `project.yml`. Do not commit build outputs, local credentials, device IDs, private captures or signing material.
- Do not claim a source feature is in a published download until it is released.

## Hardware tests
- Interactive capture, receiver-window and virtual-display tests need a usable display session. Verify an independent display is online before creating virtual displays; report SKIP when unavailable.
- Do not restart WindowServer or remote-access services to clean up a test. Record hardware-dependent gaps; automated tests do not prove two-device performance.

## Code review rules
- Flag unbounded network lengths, stale-session mutations, resource leaks, role overlap, and preference/wire compatibility changes without migration coverage.
- Flag UI claims that exceed published artifacts or measured hardware evidence. Errors must provide a recovery action, and status must not depend on color alone.
