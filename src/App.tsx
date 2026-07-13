import { useEffect, useState } from "react"
import ReleaseRail from "./components/ReleaseRail"
import SignalTopology from "./components/SignalTopology"
import StatusBoard from "./components/StatusBoard"
import TransportFlow from "./components/TransportFlow"
import { copy, releaseTag, type Locale } from "./content"

export type { Locale }

export default function App({ initialLocale = "en" }: { initialLocale?: Locale }) {
  const [starCount, setStarCount] = useState<string | null>(null)
  const c = copy[initialLocale]
  const languageHref = initialLocale === "en" ? "zh.html" : "./"

  useEffect(() => {
    document.documentElement.lang = initialLocale === "zh" ? "zh-CN" : "en"
    fetch("https://api.github.com/repos/chenyuhao0628/displayweave", { headers: { Accept: "application/vnd.github+json" } })
      .then(response => response.ok ? response.json() : null)
      .then(data => { if (data && typeof data.stargazers_count === "number") setStarCount(data.stargazers_count.toLocaleString()) })
      .catch(() => {})
  }, [initialLocale])

  return <>
    <header className="site-header">
      <a className="skip-link" href="#main">Skip to content</a>
      <div className="shell nav-shell">
        <a className="brand" href={initialLocale === "zh" ? "zh.html" : "./"}><img src="icon-256.png" alt="" /><span>DisplayWeave</span></a>
        <a className="mobile-language" href={languageHref}>{c.language}</a>
        <nav aria-label="Primary">
          <a href="#status">{c.nav.status}</a><a href="#transport">{c.nav.transport}</a><a href="#evidence">{c.nav.evidence}</a><a href="#trust">{c.nav.trust}</a><a href="#faq">{c.nav.faq}</a>
        </nav>
        <div className="nav-actions"><a className="language" href={languageHref}>{c.language}</a><a className="github-link" href="https://github.com/chenyuhao0628/displayweave">GitHub{starCount && <span>{starCount}</span>}</a><a className="button button-small" href="#download">{c.nav.download}</a></div>
      </div>
    </header>

    <main id="main">
      <section className="hero-section">
        <div className="shell hero-grid">
          <div className="hero-copy"><div className="version-line"><span>{releaseTag}</span><i />LOCAL DISPLAY FABRIC</div><h1>{c.hero.titleLines.map(line => <span key={line}>{line}</span>)}<em>{c.hero.accent}</em></h1><p>{c.hero.body}</p><div className="hero-actions"><a className="button" href="#download">{c.hero.primary}</a><a className="text-link" href="https://github.com/chenyuhao0628/displayweave">{c.hero.secondary}<span aria-hidden="true">↗</span></a></div><div className="compat-line"><span>macOS 14+</span><span>iOS / iPadOS 17+</span><span>Android 8+</span><span>GPL-3.0</span></div></div>
          <div className="hero-map"><span className="map-label">{c.hero.live}</span><SignalTopology copy={c.topology} /></div>
        </div>
      </section>

      <section className="release-section" id="download"><div className="shell"><ReleaseRail copy={c.release} /></div></section>
      <section className="status-section" id="status"><div className="shell"><StatusBoard copy={c.status} /></div></section>
      <section className="transport-section" id="transport"><div className="shell"><TransportFlow copy={c.transport} /></div></section>

      <section className="proof-section" id="evidence"><div className="shell proof-layout"><header className="section-heading"><span className="section-label">{c.proof.label}</span><h2>{c.proof.title}</h2></header><div className="metrics-grid">{c.proof.metrics.map(metric => <article key={metric.label}><strong>{metric.value}</strong><span>{metric.label}</span><p>{metric.body}</p></article>)}</div></div></section>

      <section className="trust-section" id="trust"><div className="shell trust-layout"><header className="section-heading"><span className="section-label">{c.trust.label}</span><h2>{c.trust.title}</h2><p>{c.trust.body}</p><div className="trust-links"><a href="THIRD_PARTY_NOTICES.md">{c.trust.source}</a><a href="SECURITY.md">{c.trust.security}</a></div></header><div className="trust-list">{c.trust.points.map((point, index) => <article key={point.title}><span>0{index + 1}</span><div><h3>{point.title}</h3><p>{point.body}</p></div></article>)}</div></div></section>

      <section className="faq-section" id="faq"><div className="shell faq-layout"><header className="section-heading"><span className="section-label">{c.faq.label}</span><h2>{c.faq.title}</h2></header><div className="faq-list">{c.faq.items.map(([question, answer]) => <details key={question}><summary>{question}<span aria-hidden="true">+</span></summary><p>{answer}</p></details>)}</div></div></section>
    </main>

    <footer><div className="shell footer-grid"><div><a className="brand footer-brand" href="./"><img src="icon-256.png" alt="" /><span>DisplayWeave</span></a><p>{c.footer.line}</p></div><div><a href={`https://github.com/chenyuhao0628/displayweave/blob/main/docs/README${initialLocale === "zh" ? ".zh-CN" : ""}.md`}>{c.footer.docs}</a><a href="https://github.com/chenyuhao0628/displayweave/issues">{c.footer.issues}</a><a href="https://github.com/chenyuhao0628/displayweave">{c.footer.source}</a></div><span>© 2026 · GPL-3.0</span></div></footer>
  </>
}
