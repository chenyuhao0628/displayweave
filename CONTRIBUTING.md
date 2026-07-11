[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

# Contributing to DisplayWeave

Focused bug reports, hardware evidence, documentation corrections, and small pull requests are welcome.

## Before changing code

1. Read [ARCHITECTURE.md](ARCHITECTURE.md), [ROADMAP.md](ROADMAP.md), and the relevant acceptance document under `docs/`.
2. Keep compatibility identifiers (`OpenSidecar.xcodeproj`, bundle/package IDs, preferences, Bonjour service) unless the change includes a migration design and tests.
3. Do not weaken GPL-3.0 or third-party attribution.
4. For user-facing behavior, update English and Simplified Chinese documentation together.

## Build and test

```bash
./generate.sh
pnpm install --frozen-lockfile
pnpm build
pnpm run check:docs
pnpm run check:release
cd AndroidReceiver && ./gradlew clean test assembleDebug
```

Run the relevant standalone Swift and Android protocol/policy self-tests listed in [docs/release-checklist.md](docs/release-checklist.md). Hardware claims need reproducible logs with device model, OS, transport, resolution, codec, target frame rate, duration, and observed rendered FPS.

## Pull requests

- Keep one purpose per change.
- Add a failing test before a behavior fix or feature, then show it passing.
- Run `git diff --check` and the relevant builds/tests.
- State what was verified, what remains inferred, and which hardware was unavailable.
- Never commit signing secrets, personal captures, device identifiers, or generated build directories.

## Documentation language policy

Current user guides use an English canonical file and a `.zh-CN.md` peer with reciprocal links. Numeric results, commands, filenames, signing boundaries, and security warnings must match in both languages. Historical design/implementation records may remain in their authored language when the current guide explains the shipped behavior independently.

## Licensing

Contributions are distributed under the repository's [GPL-3.0 license](LICENSE). By contributing, you confirm you have the right to submit the work and preserve applicable notices. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
