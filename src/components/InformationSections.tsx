import type { SiteCopy } from "../content"

export function EvidenceSection({ copy }: { copy: SiteCopy["proof"] }) {
  return (
    <section className="proof-section" id="evidence">
      <div className="shell proof-layout">
        <header className="section-heading">
          <span className="section-label">{copy.label}</span>
          <h2>{copy.title}</h2>
        </header>
        <div className="metrics-grid">
          {copy.metrics.map((metric) => (
            <article key={metric.label}>
              <strong>{metric.value}</strong>
              <span>{metric.label}</span>
              <p>{metric.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}

export function TrustSection({ copy }: { copy: SiteCopy["trust"] }) {
  return (
    <section className="trust-section" id="trust">
      <div className="shell trust-layout">
        <header className="section-heading">
          <span className="section-label">{copy.label}</span>
          <h2>{copy.title}</h2>
          <p>{copy.body}</p>
          <div className="trust-links">
            <a href="THIRD_PARTY_NOTICES.md">{copy.source}</a>
            <a href="SECURITY.md">{copy.security}</a>
          </div>
        </header>
        <div className="trust-list">
          {copy.points.map((point, index) => (
            <article key={point.title}>
              <span>0{index + 1}</span>
              <div>
                <h3>{point.title}</h3>
                <p>{point.body}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}

export function FAQSection({ copy }: { copy: SiteCopy["faq"] }) {
  return (
    <section className="faq-section" id="faq">
      <div className="shell faq-layout">
        <header className="section-heading">
          <span className="section-label">{copy.label}</span>
          <h2>{copy.title}</h2>
        </header>
        <div className="faq-list">
          {copy.items.map(([question, answer]) => (
            <details key={question}>
              <summary>
                {question}
                <span aria-hidden="true">+</span>
              </summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
