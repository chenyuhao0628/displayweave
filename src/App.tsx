import { useEffect, useState } from "react"
import Showcase from "./components/Showcase"
import TextRotate from "./components/TextRotate"

export type Locale = "en" | "zh"

const releaseTag = "v0.1.0-preview.1"
const releaseBase = `https://github.com/chenyuhao0628/displayweave/releases/download/${releaseTag}`

const copy = {
  en: {
    nav: ["Demo", "Features", "Compare", "FAQ", "Contribute"],
    language: "中文",
    heroWords: ["iPhone", "Android tablet", "spare iPad", "family iPad", "iPad"],
    eyebrow: "Free & open source",
    heroLead: "Use your",
    heroTail: "as your Mac's",
    heroAccent: "second monitor",
    tagline: "Turn an iPhone, iPad, or Android device into a true extended display for your Mac. Apple receivers connect over USB or WiFi; Android currently connects over WiFi with touch input, HEVC, and experimental high refresh.",
    downloadsIntro: "Choose the Mac sender and the receiver for your device.",
    downloads: [
      {
        step: "Mac sender",
        title: "macOS development preview",
        description: "Ad-hoc signed for local testing; not Developer ID signed or notarized. Gatekeeper approval may be required.",
        button: "Download macOS ZIP",
        href: `${releaseBase}/DisplayWeave-macOS-development-preview.zip`,
      },
      {
        step: "Apple receiver",
        title: "iOS Simulator development preview",
        description: "Simulator-only build. It cannot be installed directly on an iPhone or iPad.",
        button: "Download Simulator ZIP",
        href: `${releaseBase}/DisplayWeave-iOS-Simulator-development-preview.zip`,
      },
      {
        step: "Android receiver",
        title: "Installable Debug APK",
        description: "WiFi receiver. Android USB/ADB reverse is planned and not included.",
        button: "Download Android APK",
        href: `${releaseBase}/DisplayWeave-Android-debug.apk`,
      },
    ],
    releaseNote: "These are development previews, not signed production releases.",
    buildSource: "Build from source",
    demo: "Demo",
    demoTitle: "See it in action.",
    demoNote: "These historical community examples come from the OpenDisplay project that DisplayWeave is derived from.",
    features: "Features",
    featuresTitle: "A local second display across the devices you already own.",
    featureItems: [
      ["No account", "No sign-up, cloud account, or project-operated relay server."],
      ["Experimental high refresh", "Android supports HEVC, H.264 fallback, and dynamic 30/60/90/120fps negotiation. One OnePlus 120Hz device measured about 109-111 FPS end to end over WiFi; stable 120 FPS is not guaranteed."],
      ["Multiple receiver potential", "The inherited Apple path supports multiple receivers. Broader DisplayWeave mixed Apple/Android validation is still ongoing."],
      ["Retina and HiDPI", "Virtual display profiles match receiver geometry and support sharp HiDPI presentation."],
      ["Apple USB support", "iPhone and iPad can use macOS usbmuxd. Android currently uses WiFi; ADB reverse is planned."],
      ["Cross-device WiFi", "Apple and Android receivers advertise locally and stream directly over the LAN."],
      ["Touch and scroll", "Tap, drag, cursor, and two-finger scrolling return input to the Mac."],
      ["Runtime metrics", "Capture, encode, send, receive, decode, render, queue, drop, and latency data expose the real pipeline."],
      ["Local-first", "No cloud video service. Current WiFi TCP is unencrypted, so use a trusted network."],
    ],
    why: "Why DisplayWeave",
    whyTitle: "One Mac, more useful screens.",
    comparisons: [
      ["Apple Sidecar", "Built into macOS, but limited to supported iPads and Apple-account requirements."],
      ["Duet Display", "A mature commercial option with subscription-based plans."],
      ["Luna Display", "A polished hardware-assisted option that requires a dongle."],
      ["DisplayWeave", "GPL-3.0, local-first, auditable, and independently maintained for iPhone, iPad, and Android receivers."],
    ],
    tableTitle: "Current capability snapshot",
    tableHeaders: ["Capability", "DisplayWeave", "Current limit"],
    tableRows: [
      ["Apple receivers", "USB + WiFi", "H.264 path"],
      ["Android receiver", "WiFi + HEVC/H.264", "USB/ADB planned"],
      ["Android high refresh", "30/60/90/120fps negotiation", "Experimental; about 109-111 FPS measured"],
      ["iOS/iPadOS high refresh", "H.264 receiver", "120Hz not implemented"],
      ["Release packages", "Development previews", "No Developer ID signing or notarization"],
    ],
    faq: "FAQ",
    faqTitle: "Questions, answered.",
    faqItems: [
      ["How does it work?", "The Mac creates or mirrors a display, captures it with ScreenCaptureKit, encodes with VideoToolbox, and sends framed video over a direct local connection. Apple receivers render H.264; Android negotiates HEVC or H.264 and renders through MediaCodec."],
      ["Are production release packages available?", "Not yet. The downloadable files are development previews. macOS is only ad-hoc signed for local testing and is not notarized, iOS is Simulator-only, and Android is a Debug APK."],
      ["Does Android work over USB?", "Not yet. Android currently connects over local WiFi. USB via ADB reverse is planned. iPhone and iPad already support USB through macOS usbmuxd."],
      ["Does 120Hz mean stable 120 FPS?", "No. A 120fps request and an active 120Hz panel do not prove 120 rendered frames. The validated OnePlus HEVC/120 WiFi run measured about 109-111 FPS end to end, so high refresh remains experimental."],
      ["Is WiFi encrypted?", "Not yet. Video and control data use direct local TCP without production-grade encrypted pairing. Use a trusted LAN."],
      ["Can I use multiple devices?", "The inherited Apple path supports multiple receivers, but broad mixed-platform DisplayWeave validation is still in progress."],
      ["What is the license and origin?", "DisplayWeave is GPL-3.0 and independently maintained. It is derived from OpenDisplay and records the SideScreen technical-reference relationship in THIRD_PARTY_NOTICES.md."],
    ],
    contribute: "Contribute",
    contributeTitle: "Open source, built in the open.",
    contributeBody: "The complete Mac, iOS/iPadOS, Android, protocol, website, and documentation stack is available on GitHub. Reports and focused pull requests are welcome.",
    github: "View on GitHub",
    issue: "Open an issue",
    privacy: "Privacy",
    fine: "DisplayWeave — one Mac, every screen. Open, local, cross-device.",
  },
  zh: {
    nav: ["演示", "功能", "对比", "问答", "参与贡献"],
    language: "English",
    heroWords: ["iPhone", "Android 平板", "闲置 iPad", "家人的 iPad", "iPad"],
    eyebrow: "免费 · 开源 · 本地优先",
    heroLead: "让你的",
    heroTail: "成为 Mac 的",
    heroAccent: "第二块屏幕",
    tagline: "把 iPhone、iPad 或 Android 设备变成 Mac 的扩展显示器。Apple 接收端支持 USB 和 WiFi；Android 当前使用 WiFi，支持触摸、HEVC 与实验性高刷新链路。",
    downloadsIntro: "下载 Mac 发送端，以及与你设备对应的接收端。",
    downloads: [
      {
        step: "Mac 发送端",
        title: "macOS 开发预览版",
        description: "仅作本地测试的 ad-hoc 签名，未使用 Developer ID 且未公证，可能需要手动允许 Gatekeeper。",
        button: "下载 macOS ZIP",
        href: `${releaseBase}/DisplayWeave-macOS-development-preview.zip`,
      },
      {
        step: "Apple 接收端",
        title: "iOS Simulator 开发预览版",
        description: "仅供模拟器使用，不能直接安装到 iPhone 或 iPad 真机。",
        button: "下载模拟器 ZIP",
        href: `${releaseBase}/DisplayWeave-iOS-Simulator-development-preview.zip`,
      },
      {
        step: "Android 接收端",
        title: "可安装 Debug APK",
        description: "当前使用 WiFi；Android USB/ADB reverse 尚未实现。",
        button: "下载 Android APK",
        href: `${releaseBase}/DisplayWeave-Android-debug.apk`,
      },
    ],
    releaseNote: "以上均为开发预览文件，不是已签名的正式生产版本。",
    buildSource: "从源码构建",
    demo: "演示",
    demoTitle: "查看实际使用效果。",
    demoNote: "这些社区示例来自 DisplayWeave 所源自的 OpenDisplay 项目历史。",
    features: "功能",
    featuresTitle: "让你已有的设备成为真正有用的第二屏。",
    featureItems: [
      ["无需账号", "无需注册、云账号或项目运营的中转服务器。"],
      ["实验性高刷新", "Android 支持 HEVC、H.264 回退和动态 30/60/90/120fps 协商。一台 OnePlus 120Hz 设备通过 WiFi 实测约 109-111 FPS，不代表稳定满 120 FPS。"],
      ["多设备潜力", "继承的 Apple 链路支持多个接收端；DisplayWeave 的 Apple/Android 混合多设备场景仍在扩大验证。"],
      ["Retina 与 HiDPI", "虚拟显示配置匹配接收端尺寸，并支持清晰的 HiDPI 显示。"],
      ["Apple USB", "iPhone 和 iPad 可通过 macOS usbmuxd 连接；Android 当前使用 WiFi，ADB reverse 仍在规划中。"],
      ["跨设备 WiFi", "Apple 与 Android 接收端在局域网内发现，并通过本地连接直接传输。"],
      ["触摸与滚动", "轻点、拖动、光标和双指滚动可以回传到 Mac。"],
      ["运行时统计", "采集、编码、发送、接收、解码、渲染、队列、丢帧和延迟数据可用于判断真实性能。"],
      ["本地优先", "不使用云端视频服务；当前 WiFi TCP 尚未加密，请仅在可信局域网使用。"],
    ],
    why: "为什么选择 DisplayWeave",
    whyTitle: "一台 Mac，连接更多可用屏幕。",
    comparisons: [
      ["Apple Sidecar", "系统内置，但仅支持特定 iPad，并受 Apple 账号和硬件组合限制。"],
      ["Duet Display", "成熟的商业方案，主要采用订阅模式。"],
      ["Luna Display", "体验完善的硬件辅助方案，需要额外购买适配器。"],
      ["DisplayWeave", "GPL-3.0、本地优先、代码可审计，独立支持 iPhone、iPad 与 Android 接收端。"],
    ],
    tableTitle: "当前能力概览",
    tableHeaders: ["能力", "DisplayWeave 当前状态", "当前限制"],
    tableRows: [
      ["Apple 接收端", "USB + WiFi", "H.264 链路"],
      ["Android 接收端", "WiFi + HEVC/H.264", "USB/ADB 尚未实现"],
      ["Android 高刷新", "30/60/90/120fps 协商", "实验性；实测约 109-111 FPS"],
      ["iOS/iPadOS 高刷新", "H.264 接收端", "120Hz 尚未实现"],
      ["发布安装包", "开发预览版", "无 Developer ID 签名与公证"],
    ],
    faq: "常见问题",
    faqTitle: "重要边界说明。",
    faqItems: [
      ["DisplayWeave 如何工作？", "Mac 创建或镜像显示器，通过 ScreenCaptureKit 采集、VideoToolbox 编码，再经本地连接发送分帧视频。Apple 接收端渲染 H.264；Android 协商 HEVC 或 H.264，并通过 MediaCodec 渲染。"],
      ["已经有正式安装包了吗？", "还没有。本站下载的是开发预览文件：macOS 仅作 ad-hoc 本地签名且未公证，iOS 仅支持 Simulator，Android 为 Debug APK。"],
      ["Android 支持 USB 吗？", "目前不支持。Android 当前通过局域网 WiFi 连接，ADB reverse USB 仍在规划中；iPhone 和 iPad 已支持 macOS usbmuxd USB。"],
      ["120Hz 等于稳定 120 FPS 吗？", "不等于。请求 120fps 和启用 120Hz 面板不能证明渲染了 120 帧。OnePlus HEVC/120 WiFi 实测约 109-111 FPS，因此高刷新仍属于实验功能。"],
      ["WiFi 传输已经加密了吗？", "还没有。当前视频和控制数据使用本地 TCP，尚无生产级加密配对，请仅在可信局域网使用。"],
      ["可以同时使用多台设备吗？", "继承的 Apple 链路支持多个接收端，但 DisplayWeave 的跨平台混合多设备验证仍在进行。"],
      ["许可证和项目来源是什么？", "DisplayWeave 使用 GPL-3.0 并独立维护，项目源自 OpenDisplay；对 SideScreen 的技术参考关系记录在 THIRD_PARTY_NOTICES.md。"],
    ],
    contribute: "参与贡献",
    contributeTitle: "完整源码，公开协作。",
    contributeBody: "Mac、iOS/iPadOS、Android、协议、网站与文档源码均托管在 GitHub。欢迎提交可复现的问题报告和范围清晰的 Pull Request。",
    github: "前往 GitHub",
    issue: "提交问题",
    privacy: "隐私说明",
    fine: "DisplayWeave — 一台 Mac，连接你的每一块屏幕。开源、本地、跨设备。",
  },
} as const

export default function App({ initialLocale = "en" }: { initialLocale?: Locale }) {
  const [starCount, setStarCount] = useState<string | null>(null)
  const c = copy[initialLocale]
  const languageHref = initialLocale === "en" ? "zh.html" : "./"

  useEffect(() => {
    document.documentElement.lang = initialLocale === "zh" ? "zh-CN" : "en"
    fetch("https://api.github.com/repos/chenyuhao0628/displayweave", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (data && typeof data.stargazers_count === "number") {
          setStarCount(data.stargazers_count.toLocaleString())
        }
      })
      .catch(() => {})
  }, [initialLocale])

  return (
    <>
      <nav>
        <div className="wrap">
          <a className="brand" href={initialLocale === "zh" ? "zh.html" : "./"}>DisplayWeave</a>
          <a className="mobile-language" href={languageHref}>{c.language}</a>
          <div className="links">
            <a href="#demo">{c.nav[0]}</a>
            <a href="#features">{c.nav[1]}</a>
            <a href="#why">{c.nav[2]}</a>
            <a href="#faq">{c.nav[3]}</a>
            <a href="#contribute">{c.nav[4]}</a>
            <a className="language-toggle" href={languageHref}>{c.language}</a>
            <a className="gh" href="https://github.com/chenyuhao0628/displayweave" title="DisplayWeave on GitHub">
              <svg className="gh-logo" viewBox="0 0 16 16" aria-hidden="true">
                <path fillRule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8z" />
              </svg>
              {starCount && <span className="gh-stars">{starCount}</span>}
            </a>
          </div>
        </div>
      </nav>

      <section>
        <div className="wrap hero">
          <img className="hero-logo" src="logo.png" alt="DisplayWeave" width="1254" height="1254" />
          <p className="eyebrow">{c.eyebrow}</p>
          <h1>
            <span className="l1">{c.heroLead}{" "}<TextRotate as="span" texts={[...c.heroWords]} mainClassName="rotator-pill" splitLevelClassName="rotator-line" staggerFrom="last" staggerDuration={0.025} rotationInterval={2200} transition={{ type: "spring", damping: 30, stiffness: 400 }} initial={{ y: "100%", opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: "-120%", opacity: 0 }} /></span>
            <span className="l2">{c.heroTail}{" "}<span className="u">{c.heroAccent}</span>.</span>
          </h1>
          <p className="tagline">{c.tagline}</p>
          <p className="meta">macOS 14+ &nbsp;·&nbsp; iOS/iPadOS 17+ &nbsp;·&nbsp; Android 8+ &nbsp;·&nbsp; GPL-3.0</p>
        </div>
      </section>

      <section className="downloads-sec" id="downloads">
        <div className="wrap">
          <p className="needs-both">{c.downloadsIntro}</p>
          <div className="downloads">
            {c.downloads.map((item) => (
              <div key={item.step}>
                <div className="dl-head"><span className="step">{item.step}</span><span className="ver">{releaseTag}</span></div>
                <h3>{item.title}</h3>
                <p className="dl-sub">{item.description}</p>
                <a className="btn primary" href={item.href}>{item.button}</a>
              </div>
            ))}
          </div>
          <p className="release-warning">{c.releaseNote}{" "}<a href="https://github.com/chenyuhao0628/displayweave#build-from-source">{c.buildSource}</a>.</p>
        </div>
      </section>

      <section id="demo">
        <div className="wrap sec">
          <p className="eyebrow">{c.demo}</p>
          <h2>{c.demoTitle}</h2>
          <Showcase />
          <p className="sub">{c.demoNote}</p>
        </div>
      </section>

      <section id="features">
        <div className="wrap sec">
          <p className="eyebrow">{c.features}</p>
          <h2>{c.featuresTitle}</h2>
          <div className="fgrid">
            {c.featureItems.map(([title, body], index) => <div className="fcell" key={title}><span className="n">{String(index + 1).padStart(3, "0")}</span><h3>{title}</h3><p>{body}</p></div>)}
          </div>
        </div>
      </section>

      <section id="why">
        <div className="wrap sec">
          <p className="eyebrow">{c.why}</p>
          <h2>{c.whyTitle}</h2>
          <div className="compare">
            {c.comparisons.map(([name, body], index) => <div className={`row ${index === 3 ? "highlight" : ""}`} key={name}><div className="name">{name}</div><p>{body}</p></div>)}
          </div>
          <h3 className="tbl-head">{c.tableTitle}</h3>
          <div className="tbl-scroll">
            <table>
              <thead><tr>{c.tableHeaders.map((header) => <th key={header}>{header}</th>)}</tr></thead>
              <tbody>{c.tableRows.map((row) => <tr key={row[0]}>{row.map((cell) => <td key={cell}>{cell}</td>)}</tr>)}</tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="faq">
        <div className="wrap sec">
          <p className="eyebrow">{c.faq}</p>
          <h2>{c.faqTitle}</h2>
          <div className="faq">{c.faqItems.map(([question, answer]) => <details key={question}><summary>{question}</summary><p>{answer}</p></details>)}</div>
        </div>
      </section>

      <section id="contribute">
        <div className="wrap sec">
          <p className="eyebrow">{c.contribute}</p>
          <h2>{c.contributeTitle}</h2>
          <p className="contribute-copy">{c.contributeBody}</p>
          <div className="btn-row">
            <a className="btn primary" href="https://github.com/chenyuhao0628/displayweave">{c.github}</a>
            <a className="btn ghost" href="https://github.com/chenyuhao0628/displayweave/issues">{c.issue}</a>
          </div>
        </div>
      </section>

      <footer>
        <div className="wrap">
          <div className="links">
            <a href="https://github.com/chenyuhao0628/displayweave">GitHub</a>
            <a href={`https://github.com/chenyuhao0628/displayweave/releases/tag/${releaseTag}`}>Releases</a>
            <a href="https://github.com/chenyuhao0628/displayweave/issues">Issues</a>
            <a href="privacy.html">{c.privacy}</a>
            <a href="https://github.com/chenyuhao0628/displayweave/blob/main/LICENSE">GPL-3.0</a>
            <a href={languageHref}>{c.language}</a>
          </div>
          <p className="fine">{c.fine}</p>
        </div>
      </footer>
    </>
  )
}
