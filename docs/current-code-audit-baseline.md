[English](current-code-audit-baseline.md) | [简体中文](current-code-audit-baseline.zh-CN.md)

# Current Code Audit Baseline

Generated: 2026-07-15 01:06:07 +0800 (Asia/Shanghai)

## Audit object

- Repository: `chenyuhao0628/displayweave`
- Branch: `main`
- Audited HEAD: `79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`
- `git describe`: `v0.2.0-preview.3-18-g79cbf90`
- Preview 5 target commit: `4276c1a229f9f0b3237242d3ebbc0f29d7e244da`
- Relationship: the Preview 5 target is an ancestor of audited HEAD; `main` is two commits ahead.
- Commits after the target:
  - `b029fb6 docs: publish preview 5 release metadata`
  - `79cbf90 docs: persist preview 5 update feeds`
- Worktree: clean; no uncommitted files were present when the baseline was captured.

## Tag caveat

The local clone did not contain a `v0.2.0-preview.5` tag when the baseline was captured. Subsequent remote verification proved that the public tag resolves exactly to `4276c1a229f9f0b3237242d3ebbc0f29d7e244da`; this is remote evidence, not an inference from commit messages.

## Scope rule

The audit reviews the code and documentation at the audited HEAD above. Physical Android/iOS behavior is reported as **Pending** unless backed by a recorded real-device run. Static review and automated tests are not treated as physical validation.

## Recent history

```text
79cbf90 (HEAD -> main, displayweave/main, displayweave/HEAD) docs: persist preview 5 update feeds
b029fb6 docs: publish preview 5 release metadata
4276c1a fix: stabilize high-refresh Android streaming
7e6214b docs: clarify preview 4 feed verification
8dbedfc docs: publish preview 4 release metadata
f300f88 feat: record Android thermal and power metrics
03e5e34 feat: add negotiated Android binary frame header
f07b3ad feat: add local fast congestion decrease
54a26c6 feat: classify Android drops for bitrate control
5ef6b61 feat: manage WiFi and Surface latency hints
3d3e323 feat: enable safe decoder low latency
a8e94e1 feat: negotiate safe Android frame sizes
c02ce4e feat: correct keyframe drop recovery policy
d878af1 fix: link localized release notes
d5deecf docs: publish preview 3 release metadata
```
