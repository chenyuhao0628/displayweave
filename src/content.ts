export type Locale = "en" | "zh"
export type EvidenceState = "verified" | "experimental" | "deferred"

export const releaseTag = "v0.2.0-preview.5"
export const releaseBase = `https://github.com/chenyuhao0628/displayweave/releases/download/${releaseTag}`

export type ReleaseAsset = {
  platform: string
  role: string
  title: string
  file: string
  description: string
  action: string
}

export type EvidenceItem = {
  title: string
  detail: string
  state: EvidenceState
}

export type SiteCopy = {
  language: string
  nav: { status: string; transport: string; evidence: string; trust: string; faq: string; download: string }
  hero: { titleLines: string[]; accent: string; body: string; primary: string; secondary: string; live: string }
  topology: { mac: string; source: string; android: string; apple: string; usb: string; wifi: string; fallback: string; active: string }
  release: { label: string; title: string; intro: string; warning: string; checksum: string; assets: ReleaseAsset[] }
  status: { label: string; title: string; intro: string; names: Record<EvidenceState, string>; items: EvidenceItem[] }
  transport: { label: string; title: string; intro: string; steps: Array<{ code: string; title: string; body: string }> }
  proof: { label: string; title: string; metrics: Array<{ value: string; label: string; body: string }> }
  trust: { label: string; title: string; body: string; points: Array<{ title: string; body: string }>; source: string; security: string }
  faq: { label: string; title: string; items: Array<[string, string]> }
  footer: { line: string; docs: string; issues: string; source: string }
}

const enAssets: ReleaseAsset[] = [
  { platform: "macOS", role: "Sender", title: "Guided Mac first install", file: "DisplayWeave-macOS.dmg", description: "Drag DisplayWeave into Applications; later releases use EdDSA-authenticated Sparkle updates. Ad-hoc signed, not notarized, and may require Gatekeeper approval.", action: "Download macOS DMG" },
  { platform: "Android", role: "Receiver", title: "Verified in-app updates", file: "DisplayWeave-Android.apk", description: "Install over the existing app once. Later downloads are checked by size, hash, package, version, SDK, and pinned signing certificate before system confirmation.", action: "Download Android APK" },
  { platform: "iOS / iPadOS", role: "Receiver input", title: "Unsigned re-signing input", file: "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa", description: "Not directly installable. You must lawfully sign it with your own Apple identity before device installation.", action: "Download re-signing input" },
]

const zhAssets: ReleaseAsset[] = [
  { platform: "macOS", role: "发送端", title: "带引导的 Mac 首次安装", file: "DisplayWeave-macOS.dmg", description: "把 DisplayWeave 拖入“应用程序”，后续版本使用 EdDSA 认证的 Sparkle 更新。应用为 ad-hoc 签名、未公证，可能需要手动允许 Gatekeeper。", action: "下载 macOS DMG" },
  { platform: "Android", role: "接收端", title: "已验证的应用内更新", file: "DisplayWeave-Android.apk", description: "首次覆盖安装到现有应用；后续下载会校验大小、哈希、包名、版本、SDK 和固定签名证书，再由系统确认。", action: "下载 Android APK" },
  { platform: "iOS / iPadOS", role: "接收端输入包", title: "未签名自签输入包", file: "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa", description: "不能直接安装；需使用你自己的 Apple 身份依法签名后才能安装到设备。", action: "下载自签输入包" },
]

export const copy: Record<Locale, SiteCopy> = {
  en: {
    language: "中文",
    nav: { status: "Status", transport: "Transport", evidence: "Evidence", trust: "Trust", faq: "FAQ", download: "Download Preview" },
    hero: { titleLines: ["Weave every", "spare screen", "into your"], accent: "Mac workspace.", body: "DisplayWeave turns iPhone, iPad, and Android devices into local extended displays—with Apple USB/WiFi, Android ADB USB, verified Mac/Android update channels, touch input, HEVC, and experimental high refresh.", primary: "Get v0.2 Preview", secondary: "Read the source", live: "Live transport map" },
    topology: { mac: "Mac sender", source: "Capture · Encode", android: "Android receiver", apple: "Apple receiver", usb: "ADB USB", wifi: "Local WiFi", fallback: "AUTO FALLBACK", active: "ACTIVE" },
    release: { label: "v0.2 preview release", title: "Install once, then update Mac and Android in place.", intro: "Every package is distributed directly from GitHub. Older builds need this one-time manual migration before later automatic updates.", warning: "Development preview — no App Store, Google Play, Developer ID notarization, or universal iOS signing.", checksum: "Verify all downloads with SHA256SUMS.txt", assets: enAssets },
    status: { label: "Evidence, not promises", title: "A release status board with the edges left visible.", intro: "Verified means exercised on available physical hardware. Experimental means implemented with hardware-dependent performance. Deferred work is stated plainly.", names: { verified: "Verified", experimental: "Experimental", deferred: "Deferred" }, items: [
      { state: "verified", title: "Android USB and recovery", detail: "HEVC/120 and H.264/60 over wired ADB forward; unplug/replug, ADB restart, authorization revoke/reallow, foreground return, and Auto fallback recovery verified." },
      { state: "verified", title: "Touch and mixed receivers", detail: "Prior Preview 2 evidence covers tap, drag, cursor, two-finger scroll, and one iPhone WiFi receiver running beside one Android receiver; this was not rerun for v0.2." },
      { state: "verified", title: "Offline Android distribution", detail: "Release APK v2 signature, certificate identity, first install, and upgrade install verified without a Google developer account." },
      { state: "verified", title: "Update and iPhone display paths", detail: "Mac EdDSA and Android package/certificate verification reject tampered updates. Metal drawable synchronization fixes the reported iPhone black-screen path without changing the receiver protocol." },
      { state: "experimental", title: "Android high refresh", detail: "30/60/90/120fps negotiation with HEVC and H.264 fallback. OnePlus WiFi HEVC/120 measured about 109–111 rendered FPS; stable 120 FPS is not guaranteed." },
      { state: "experimental", title: "Measured performance controls", detail: "Short CSV/JSONL benchmark recording, target/actual bitrate separation, Auto/Manual/Benchmark bitrate, bounded adaptive changes, low-latency queues, and transport-aware GOP are implemented. The controlled USB/WiFi matrix remains pending." },
      { state: "experimental", title: "Private macOS display API", detail: "The Mac sender relies on CGVirtualDisplay. Future macOS versions may change private behavior." },
      { state: "deferred", title: "Remaining matrix", detail: "Two simultaneous Android devices, controlled same-condition USB/WiFi benchmark, and 30-minute/2-hour endurance runs are not complete." },
    ] },
    transport: { label: "Transport logic", title: "Auto follows the cable—without trapping the session.", intro: "One install identity anchors the handover, so a wireless-debugging endpoint cannot masquerade as a second USB device.", steps: [
      { code: "01", title: "Discover wired ADB", body: "Only a device row with wired USB metadata is eligible." },
      { code: "02", title: "Forward a dynamic port", body: "Each serial receives its own Mac-local TCP port to Android :9000." },
      { code: "03", title: "Recover with limits", body: "Protocol grace and bounded 0.5/1/2/4/8 second retries avoid hot loops." },
      { code: "04", title: "Fall back by install ID", body: "Auto uses WiFi only for the same Android app installation." },
      { code: "05", title: "Upgrade back to USB", body: "Cable return atomically ends WiFi before wired reconnection." },
    ] },
    proof: { label: "Measured path", title: "Input and pixels travel both ways.", metrics: [
      { value: "109–111", label: "rendered FPS", body: "Historical OnePlus HEVC/120 WiFi run; a device-specific result, not a guarantee." },
      { value: "≈26 s", label: "USB → WiFi fallback", body: "Observed after socket reset, protocol grace, and the full bounded recovery sequence." },
      { value: "1 + 1", label: "mixed receivers", body: "Prior Preview 2 evidence: iPhone over WiFi and Android through an independent session at the same time." },
      { value: "2-way", label: "local interaction", body: "Video streams outward while touch, drag, cursor, and two-finger scroll return to macOS." },
    ] },
    trust: { label: "Local-first boundary", title: "Your screens stay on your local link.", body: "DisplayWeave does not require an account or project-operated cloud relay. That does not make every transport production-secure yet.", points: [
      { title: "Trusted LAN only", body: "Current WiFi video and control TCP is not production-encrypted. Use a network you trust." },
      { title: "ADB trust is broad", body: "Android USB debugging authorizes the Mac as a debugging host, not only DisplayWeave." },
      { title: "Transparent origin", body: "DisplayWeave is GPL-3.0 software derived from OpenDisplay, with SideScreen technical-reference notices retained." },
    ], source: "Third-party notices", security: "Security policy" },
    faq: { label: "Install and operate", title: "Important questions before you connect.", items: [
      ["Can I install the Android APK without Google Play?", "Yes. Enable installation from the source you use to open the APK, then verify its SHA-256 and project certificate fingerprint before installing."],
      ["Will later Mac and Android releases require reinstalling?", "After manually installing this update-capable release once, Mac can use Sparkle and Android can check in Settings & Help. Android still shows its system installer, and Mac remains ad-hoc signed and not notarized."],
      ["Why does macOS warn about the app?", "The Preview is ad-hoc signed and not notarized because this release does not use a paid Developer ID. Inspect the source and checksum, then follow the documented Gatekeeper steps only if you trust the package."],
      ["Can I install the IPA directly?", "No. It is deliberately an unsigned re-signing input. A user must provide their own valid signing identity; third-party signing services carry their own security and legal risks."],
      ["Will Android reconnect after returning from the desktop?", "Yes on the validated path. The receiver restarts idempotently when its surface returns, and the Mac resends stream configuration before requesting a keyframe."],
      ["Is Android USB faster than WiFi?", "It avoids LAN variability, but the controlled same-condition benchmark remains pending. The published benchmark document defines how to compare them without inventing numbers."],
    ] },
    footer: { line: "One Mac. A woven field of useful screens.", docs: "Documentation", issues: "Report an issue", source: "GitHub source" },
  },
  zh: {
    language: "English",
    nav: { status: "状态", transport: "传输", evidence: "实测", trust: "边界", faq: "问答", download: "下载预览版" },
    hero: { titleLines: ["把每一块闲置屏幕，", "编入你的"], accent: "Mac 工作空间。", body: "DisplayWeave 将 iPhone、iPad 和 Android 设备变成本地扩展显示器，支持 Apple USB/WiFi、Android ADB USB、已验证的 Mac/Android 更新渠道、触摸、HEVC 与实验性高刷新。", primary: "获取 v0.2 预览版", secondary: "查看源代码", live: "实时传输拓扑" },
    topology: { mac: "Mac 发送端", source: "采集 · 编码", android: "Android 接收端", apple: "Apple 接收端", usb: "ADB USB", wifi: "本地 WiFi", fallback: "自动回退", active: "已连接" },
    release: { label: "v0.2 预览发布", title: "首次安装，之后原位更新 Mac 与 Android。", intro: "所有文件均由 GitHub 直接分发。旧版本需要先完成这次手动迁移，后续才能自动更新。", warning: "开发预览版——未通过 App Store、Google Play、Developer ID 公证或通用 iOS 签名分发。", checksum: "使用 SHA256SUMS.txt 验证全部下载", assets: zhAssets },
    status: { label: "证据，而不是口号", title: "保留真实边界的版本状态板。", intro: "“已验证”表示在现有真机上完成；“实验性”表示已实现但性能依赖硬件；未完成工作会明确列出。", names: { verified: "已验证", experimental: "实验性", deferred: "待完成" }, items: [
      { state: "verified", title: "Android USB 与恢复", detail: "已验证有线 ADB forward 的 HEVC/120、H.264/60，以及拔插、ADB 重启、取消/恢复授权、回到前台和 Auto 回退恢复。" },
      { state: "verified", title: "触摸与混合接收端", detail: "Preview 2 既有证据覆盖轻点、拖动、光标、双指滚动，以及 iPhone WiFi 与一台 Android 并发；v0.2 未重新执行。" },
      { state: "verified", title: "Android 离线分发", detail: "无需 Google 开发者账号，已验证 Release APK v2 签名、证书身份、首次安装和覆盖安装。" },
      { state: "verified", title: "更新与 iPhone 显示链路", detail: "Mac EdDSA 与 Android 包/证书校验会拒绝被篡改的更新；Metal drawable 同步修复已报告的 iPhone 黑屏链路，接收协议保持不变。" },
      { state: "experimental", title: "Android 高刷新", detail: "支持 30/60/90/120fps 协商、HEVC 与 H.264 回退；OnePlus WiFi HEVC/120 实测约 109–111 渲染 FPS，不保证稳定满 120 FPS。" },
      { state: "experimental", title: "可测量性能控制", detail: "已实现短时 CSV/JSONL benchmark、Target/Actual Bitrate 分离、Auto/Manual/Benchmark、自适应调节、低延迟队列与传输感知 GOP；同条件 USB/WiFi 矩阵仍待完成。" },
      { state: "experimental", title: "macOS 私有显示 API", detail: "Mac 发送端依赖 CGVirtualDisplay，未来 macOS 版本可能改变其私有行为。" },
      { state: "deferred", title: "剩余验证矩阵", detail: "双 Android 并发、同条件 USB/WiFi 受控 Benchmark，以及 30 分钟/2 小时耐久测试尚未完成。" },
    ] },
    transport: { label: "传输逻辑", title: "Auto 跟随线缆，也不会把会话困住。", intro: "同一 install ID 锚定切换目标，因此无线调试端点不会伪装成第二台 USB 设备。", steps: [
      { code: "01", title: "发现有线 ADB", body: "只有包含有线 USB 元数据的设备行才具备资格。" },
      { code: "02", title: "转发动态端口", body: "每个 serial 独享一个 Mac 本地 TCP 端口，映射到 Android :9000。" },
      { code: "03", title: "有限恢复", body: "协议宽限加 0.5/1/2/4/8 秒退避，避免高速死循环。" },
      { code: "04", title: "按 install ID 回退", body: "Auto 只回退到同一 Android 应用安装实例的 WiFi。" },
      { code: "05", title: "重新升级 USB", body: "线缆恢复时先原子结束 WiFi，再建立有线连接。" },
    ] },
    proof: { label: "实测链路", title: "像素向外传，输入向内回。", metrics: [
      { value: "109–111", label: "渲染 FPS", body: "OnePlus HEVC/120 WiFi 历史实测，属于单设备结果，不是承诺。" },
      { value: "约 26 秒", label: "USB → WiFi 回退", body: "从 socket reset 开始，经过协议宽限与完整有限恢复序列后的观察值。" },
      { value: "1 + 1", label: "混合接收端", body: "Preview 2 既有证据：iPhone 通过 WiFi、Android 通过独立会话同时运行。" },
      { value: "双向", label: "本地交互", body: "视频向设备发送，触摸、拖动、光标和双指滚动返回 macOS。" },
    ] },
    trust: { label: "本地优先边界", title: "屏幕数据留在本地链路。", body: "DisplayWeave 不要求账号或项目运营的云端中继，但这不代表所有传输都已达到生产安全级别。", points: [
      { title: "仅限可信局域网", body: "当前 WiFi 视频与控制 TCP 尚未生产级加密，请只在可信网络使用。" },
      { title: "ADB 信任范围较广", body: "Android USB 调试授权的是整台 Mac 调试主机，而不只是 DisplayWeave。" },
      { title: "来源透明", body: "DisplayWeave 是源自 OpenDisplay 的 GPL-3.0 软件，并保留 SideScreen 技术参考声明。" },
    ], source: "第三方声明", security: "安全说明" },
    faq: { label: "安装与使用", title: "连接前需要了解的问题。", items: [
      ["不通过 Google Play 能安装 Android APK 吗？", "可以。为打开 APK 的来源允许安装未知应用，并在安装前核对 SHA-256 与项目证书指纹。"],
      ["后续 Mac 和 Android 版本还要重新安装吗？", "手动安装这个支持更新的版本一次后，Mac 可使用 Sparkle，Android 可在“设置与帮助”中检查；Android 仍会显示系统安装器，Mac 也仍为 ad-hoc 签名且未公证。"],
      ["为什么 macOS 会显示安全警告？", "Preview 使用 ad-hoc 签名且未公证，因为本次没有付费 Developer ID。请先检查源码和校验和，仅在信任产物时按文档允许 Gatekeeper。"],
      ["IPA 可以直接安装吗？", "不可以。它明确是未签名的自签输入包，用户必须提供自己的有效签名身份；第三方签名服务存在独立的安全和法律风险。"],
      ["Android 回到桌面再进入会自动重连吗？", "在已验证链路上可以。Surface 返回时接收端会幂等重启，Mac 会先重发 streamConfig，再请求关键帧。"],
      ["Android USB 一定比 WiFi 快吗？", "它可以避开局域网波动，但同条件受控 Benchmark 仍未执行。公开 Benchmark 文档规定了如何比较，不会编造数字。"],
    ] },
    footer: { line: "一台 Mac，织起一片可用屏幕。", docs: "文档", issues: "报告问题", source: "GitHub 源码" },
  },
}

export const assetHref = (file: string) => `${releaseBase}/${file}`
