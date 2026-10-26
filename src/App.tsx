import SiteHeader from "./components/SiteHeader"
import SiteFooter from "./components/SiteFooter"
import {
  EvidenceSection,
  TrustSection,
  FAQSection,
} from "./components/InformationSections"
import DevelopmentNote from "./components/DevelopmentNote"
import ReleaseRail from "./components/ReleaseRail"
import SignalTopology from "./components/SignalTopology"
import StatusBoard from "./components/StatusBoard"
import TransportFlow from "./components/TransportFlow"
import { copy, releaseTag, type Locale } from "./content"

export type { Locale }

export default function App({
  initialLocale = "en",
}: {
  initialLocale?: Locale
}) {
  const c = copy[initialLocale]

  return (
    <>
      <SiteHeader locale={initialLocale} copy={c} />

      <main id="main" tabIndex={-1}>
        <section className="hero-section">
          <div className="shell hero-grid">
            <div className="hero-copy">
              <div className="version-line">
                <span>{releaseTag}</span>
                <i />
                LOCAL DISPLAY FABRIC
              </div>
              <h1>
                {c.hero.titleLines.map((line) => (
                  <span key={line}>{line}</span>
                ))}
                <em>{c.hero.accent}</em>
              </h1>
              <p>{c.hero.body}</p>
              <div className="hero-actions">
                <a className="button" href="#download">
                  {c.hero.primary}
                </a>
                <a
                  className="text-link"
                  href="https://github.com/chenyuhao0628/displayweave"
                >
                  {c.hero.secondary}
                  <span aria-hidden="true">↗</span>
                </a>
              </div>
              <div className="compat-line">
                <span>macOS 14+</span>
                <span>iOS / iPadOS 17+</span>
                <span>Android 8+</span>
                <span>GPL-3.0</span>
              </div>
            </div>
            <div className="hero-map">
              <span className="map-label">{c.hero.live}</span>
              <SignalTopology copy={c.topology} />
            </div>
          </div>
        </section>

        <DevelopmentNote locale={initialLocale} />
        <section className="release-section" id="download">
          <div className="shell">
            <ReleaseRail copy={c.release} />
          </div>
        </section>
        <section className="status-section" id="status">
          <div className="shell">
            <StatusBoard copy={c.status} />
          </div>
        </section>
        <section className="transport-section" id="transport">
          <div className="shell">
            <TransportFlow copy={c.transport} />
          </div>
        </section>

        <EvidenceSection copy={c.proof} />
        <TrustSection copy={c.trust} locale={initialLocale} />
        <FAQSection copy={c.faq} />
      </main>

      <SiteFooter locale={initialLocale} copy={c.footer} />
    </>
  )
}
