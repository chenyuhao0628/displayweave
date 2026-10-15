[English](ui-guidelines.md) | [简体中文](ui-guidelines.zh-CN.md)

# UI standard

Scope: macOS control and receive windows, iOS receiver, Android receiver, and bilingual website. Effective 2026-10-16; this is the implementation contract for the source branch.

## Information and interaction

- Primary task first: choose send/receive, select a device, connect; on receivers, show readiness and the steps required on the Mac. Keep diagnostics and tuning out of the first connection path.
- Use consistent terms: Send / Receive (发送 / 接收), Extend / Mirror (扩展 / 镜像), LAN (局域网，Wi-Fi or Ethernet), USB, Connected / Waiting / Failed (已连接 / 等待连接 / 连接失败). Protocol names belong in advanced settings or diagnostics.
- Every visible state includes text, not only a colored dot. Show actionable errors with retry, permission settings or network guidance. A pending connection is not a connected device.
- One prominent primary action per context. Secondary actions use native bordered/text controls. Destructive disconnect/stop remains clearly labeled. Never replace a failed state with silent success.
- Keep local transport security guidance near connection help. Distinguish source-only capability, experimental performance and downloadable releases.

## Visual tokens

| Role | Standard |
| --- | --- |
| Spacing | 4, 8, 12, 16, 24, 32 logical points/dp; sections 24; page inset 20–24 |
| Typography | System font; title, headline, body, caption semantic styles; monospaced only for measured values and identifiers |
| Surface | Native system background and grouped secondary surface on Apple; adaptive day/night palette on Android; shared CSS variables on web |
| Accent | One blue/cyan accent for primary action; green/amber/red reserved for labeled status |
| Shape | 12–16 radius for content panels; system control shapes; avoid excessive decoration |
| Target | Native desktop controls; at least 44 points for touch on iOS, 48 dp on Android; web touch actions at least 44 CSS px |
| Width | Desktop resizable and scrollable; mobile content up to 520 points; website 1240 px maximum |

## Platform contracts

**Mac:** app entry, sender controller/session models, permissions, reusable UI and feature views live in separate files. Main window contains roles, devices and connection controls. A dedicated settings window holds stream quality, application presentation and diagnostics. AppKit bridges only window lifecycle/video behavior. Preserve a bounded menu-bar panel and a resizable main window. Keep keyboard access and Command-comma settings.

**iOS:** scrollable waiting/onboarding views support landscape and Dynamic Type. Settings must have a visible, accessible streaming entry point; shaking remains optional. Video stays black-backed and aspect-correct. Separate model, video host, performance overlay, settings and onboarding from app entry.

**Android:** keep immersive video, with an accessible connection panel while waiting. Put common spacing, colors, text/button styles in a UI helper; support day/night and scroll on small screens. Preserve touch/decoder/lifecycle ownership and explicit update controls.

**Web:** reusable page sections and shared tokens; accessible navigation on mobile as well as desktop, visible keyboard focus, semantic landmarks, reduced motion and bilingual labels. Development features must not change release download claims. Preserve downloadable artifact checks.

## Acceptance

Inspect light/dark, minimum size and long text; keyboard/tab navigation on desktop/web; portrait/landscape and increased text on mobile. Check waiting, connecting, connected, failure, role transition and settings. Builds and state-policy tests gate each affected platform; hardware-only states need the physical matrix, not fabricated screenshots. Record inspected versus untested states in the iteration report.
