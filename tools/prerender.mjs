// Post-build static prerender: inject the SSR-rendered <App/> markup into the
// built site-dist/index.html so the shipped page is fully crawlable.
// the old hand-written static site). The client still boots React on top and
// runs the animation; this only fills the initial markup.
import fs from "node:fs/promises"
import { render } from "../dist-ssr/entry-server.js"

const file = "site-dist/index.html"
const src = await fs.readFile(file, "utf8")
if (!src.includes('<div id="root"></div>')) {
  throw new Error('prerender: could not find empty <div id="root"></div> to inject into')
}

const en = render("en")
const enOut = src
  .replace('<div id="root"></div>', `<div id="root">${en}</div>`)
  .replace('</head>', '  <link rel="alternate" hreflang="zh-CN" href="https://chenyuhao0628.github.io/displayweave/zh.html" />\n</head>')
await fs.writeFile(file, enOut)

const zh = render("zh")
const zhOut = src
  .replace('<html lang="en">', '<html lang="zh-CN">')
  .replace('<div id="root"></div>', `<div id="root">${zh}</div>`)
  .replace('<title>DisplayWeave — Local second displays for Mac, iPhone, iPad, and Android</title>', '<title>DisplayWeave — 将 iPhone、iPad 和 Android 变成 Mac 第二屏</title>')
  .replace(/<meta name="description" content="[^"]+" \/>/, '<meta name="description" content="DisplayWeave 是开源、本地优先的 Mac 第二屏项目，支持 iPhone、iPad 与 Android；Android 支持 HEVC 和实验性高刷新。" />')
  .replace('https://chenyuhao0628.github.io/displayweave/" />', 'https://chenyuhao0628.github.io/displayweave/zh.html" />')
  .replace('<meta property="og:locale" content="en_US" />', '<meta property="og:locale" content="zh_CN" />')
  .replace('<meta property="og:title" content="DisplayWeave — One Mac. Every screen." />', '<meta property="og:title" content="DisplayWeave — 一台 Mac，连接你的每一块屏幕" />')
  .replace(/<meta property="og:description" content="[^"]+" \/>/, '<meta property="og:description" content="将 iPhone、iPad 和 Android 变成 Mac 第二屏。Android 支持 WiFi、HEVC 和实验性高刷新，OnePlus 实测约 109-111 FPS。" />')
  .replace('<meta property="og:url" content="https://chenyuhao0628.github.io/displayweave/" />', '<meta property="og:url" content="https://chenyuhao0628.github.io/displayweave/zh.html" />')
  .replace('<meta name="twitter:title" content="DisplayWeave — One Mac. Every screen." />', '<meta name="twitter:title" content="DisplayWeave — 一台 Mac，连接你的每一块屏幕" />')
  .replace(/<meta name="twitter:description" content="[^"]+" \/>/, '<meta name="twitter:description" content="开源、本地优先的 Mac 第二屏项目，支持 iPhone、iPad 与 Android。" />')
  .replace('"description": "Independent, open-source, local-first second-display platform for macOS with iPhone, iPad, and Android receivers. Apple receivers support USB and WiFi; Android currently supports WiFi with HEVC and experimental high refresh."', '"description": "DisplayWeave 是独立维护、开源、本地优先的 Mac 第二屏项目，支持 iPhone、iPad 与 Android；Apple 支持 USB/WiFi，Android 当前支持 WiFi、HEVC 和实验性高刷新。"')
  .replace('</head>', '  <link rel="alternate" hreflang="en" href="https://chenyuhao0628.github.io/displayweave/" />\n</head>')
await fs.writeFile("site-dist/zh.html", zhOut)

console.log(`prerendered en=${en.length} zh=${zh.length} chars`)
