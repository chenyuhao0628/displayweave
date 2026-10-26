[English](ui-guidelines.md) | [简体中文](ui-guidelines.zh-CN.md)

# DisplayWeave UI design standard

Revision 3 · 2026-10-26. This is the implementation contract for macOS, iOS and Android application UI. Website branding and download accuracy follow the same vocabulary; this iteration changes native applications and release information. Evidence belongs in the [UI audit](../archive/audits/ui-audit-2026-10-16.md), separately from this specification.

## Product and information architecture

Help a person turn another device into a display. The first screen must answer: which role is this device using, what is happening, and what should I do next? Use native controls and system typography; keep detailed tuning out of the first connection path.

| Surface | Order and primary action | Secondary content |
| --- | --- | --- |
| Mac sender | Role → display mode/transport → devices → first-connection help; Connect on a selected device | Pairing and permission recovery; quality in Settings |
| Mac receiver | Role → live receive status + pairing → display options → optional input | Connection steps and network recovery |
| Mac settings | Stream / General / Permissions & diagnostics / Security & pairing | Group settings by outcome, with explanations beneath their control |
| iOS / Android waiting | Brand → device/status → connection mode → setup steps; iOS pins connection settings to the bottom safe area | General settings/help; download Mac app in onboarding/help |
| Streaming receiver | Aspect-correct black-backed video with a persistent accessible Settings button | Optional measured diagnostics; no idle cards over video |

Mac working window starts at 680 × 720 points and supports 480 × 440. The menu panel is 480 × 640, scrolls its body, and offers Open window. Header and footer remain reachable. Receiver settings and pairing must not be buried below long setup instructions. Mobile content is centered, at most 520 points/dp wide excluding page insets, and scrolls in both orientations. No fixed-height text containers.

## Layout and component tokens

| Token | Rule |
| --- | --- |
| Spacing | 4, 8, 12, 16, 24, 32 logical points/dp; 24 between sections; 20–24 page inset |
| Typography | System title/title2 for a page; headline for a section/device; body for actions and instructions; caption/footnote for supporting detail |
| Measurements | Monospaced digits for throughput/FPS; identifiers may use monospaced text and selection |
| Surfaces | Native adaptive window background/material; quiet secondary cards; Android explicit day/night semantic palette |
| Accent | One blue accent for primary actions; status additionally has a symbol and readable text |
| Shape | 16 for content cards; native button/toggle shapes; 12 for compact status surfaces |
| Targets | Native Mac controls; iOS at least 44 pt and Android at least 48 dp for touch actions |
| Borders | Subtle separator stroke; no decorative gradients, redundant shadows, or oversized icon tiles |

Reusable components have a single purpose: section heading, content panel, status label, device row, numbered setup step. Apple setup steps are shared between onboarding and waiting surfaces. Android styling belongs in ReceiverUi. Avoid copying full pages or placing network work in view bodies.

## State and interaction contract

| State | Presentation | Available recovery/action |
| --- | --- | --- |
| Discovering / waiting | Antenna icon + waiting text, setup steps | Pairing settings, permission/network help |
| Device discovered | Name and transport; wired link-local is a candidate | Connect; never claim a live connection |
| Starting / reconnecting | Session's actual status; pending symbol | Disconnect/cancel; disable duplicate starts during replacement |
| Streaming | Session text, actual security mode and transport; metrics subordinate | Disconnect; failed sessions offer Retry |
| Failed | Error text wraps without a two-line cap; warning symbol | Retry and relevant permission/pairing action |
| Switching role | Progress and cleanup explanation; role controls disabled | Wait for resource ownership transfer |
| Receiver stopped | Actual stopped status | Start receiving |

One primary action per decision area. Keep Stop/Disconnect labeled and secondary. Never infer connection readiness or encryption from a successful TCP connection. Security preference summaries describe policy, while active sessions display their negotiated mode. Default policy says pairing is required; an enabled legacy preference says unencrypted compatibility is allowed, not that every session is unencrypted. No unconditional plaintext warning on a secure sender.

## Copy, accessibility and localization

Use Send/Receive (发送屏幕/接收屏幕), Extend/Mirror (扩展/镜像), LAN (局域网; Wi-Fi or Ethernet), USB, Waiting (等待连接), Pairing (配对), Retry (重试), Disconnect (断开). Errors explain the next action. Explain invitation creation on the receiver and import on the Mac; pairing is not the same as granting ADB or Accessibility permission.

All statuses have readable text and an icon. Decorative art is hidden from accessibility. Icon-only actions have accessible names. Long device names and failures wrap. Label form fields even if their visual labels are hidden. Keep keyboard focus visible, use native tab traversal and Command-comma for settings. Mobile supports Dynamic Type/font scale and scroll; do not force all-caps or fixed text heights. Secondary text uses semantic contrast, not low-opacity primary text. Honor system appearance; black is reserved for video. Do not make frequent frame-rate changes an accessibility announcement.

User guides have reciprocal English/Simplified Chinese links. The current native UI is Simplified Chinese; adding a complete English UI is separate work, not implied by bilingual documentation.

Released in v0.3.1: new Android installations use concise streaming status, with optional metrics and selectable detailed diagnostics in settings. Disabling metrics must replace the visible text immediately. Video, cursor and touch use the same aspect-fit rectangle; black bars do not send remote input. Honor system rotation. Mac settings distinguish requested bitrate/FPS from the negotiated raster/codec/target and measured throughput, and explain resolution versus frame-rate priority. iOS keeps its settings action reachable at accessibility text sizes; only branding caps Dynamic Type.

## Ownership and compatibility

MacRoleController owns exclusive send/receive transitions. SenderController/DeviceSession own transport and cleanup; views bind to existing state. ReceiverModel/PhoneReceiver and Android MainActivity keep their lifecycle and decoder ownership. Presentation changes preserve preference keys, bundle/package IDs, service names, wire framing, update feeds and signing identities. Generate the Xcode project from project.yml.

HEVC, high refresh, wired candidates and Pencil retain capability and physical-evidence qualifiers. Target FPS and submitted FPS are not measured panel refresh. Settings must distinguish consent from confirmed protocol support. Source functionality becomes a download claim only after the matching release is published.

## Acceptance and evidence

Before release, build both Apple targets and Android; run the project regression and documentation gates. Inspect Mac sender/receiver/settings at minimum and default widths, light/dark, long text, and keyboard navigation where a usable display is available. Inspect mobile waiting/onboarding/settings, portrait/landscape and enlarged text. Exercise streaming and failures with isolated fixtures where possible; label synthetic evidence.

Record separately: implemented changes, automated checks, observed UI, physical-device results, and SKIP/deferred work. No fabricated connection screenshots. Virtual-display tests require an independent online display; otherwise SKIP. A simulator or successful build does not prove two-device performance, VoiceOver/TalkBack quality, or Intel runtime.
