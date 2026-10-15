[English](upgrade-plan.md) | [简体中文](upgrade-plan.zh-CN.md)

# Source upgrade plan — 2026-10-16

Baseline: `83581c5`; active branch `codex/mac-to-mac-lan`; existing PR #11. Public release remains v0.2.1-p6.

1. Rules: establish AGENTS.md and dated official Codex references; validate bilingual/release documents; commit.
2. UI contract: inventory Mac (1434-line mixed entry/controller/view), iOS (796-line mixed receiver UI/model), Android programmatic receiver panel and React website; write this standard; commit.
3. Apple UI: split ownership, introduce desktop connection workspace/settings, adaptive receiver screens and accessible stream settings; compile both targets, run Swift suites; commit.
4. Android/web UI: centralize styles, adaptive waiting/help screens, mobile navigation and semantic page sections; Android tests/build, web type/build and UI checks; commit.
5. Upstream: refresh origin/main, compare selective behavior changes against local contracts, port useful fixes with attribution and regression coverage; document conflicts and deferred features; commit.
6. Audit: examine lifecycle, network bounds, stale callback isolation, accessibility and release claims. Fix evidenced defects; run complete automated gates; update architecture, roadmap and audit with actual outcomes; commit and synchronize remote.

Completion: the four existing UI surfaces implement the standard, useful upstream items are dispositioned, critical audit defects are resolved, automated regression passes, main/remote integration is verified, and physical tests remain honestly qualified. No public release or unsupported two-device performance claims are included.
