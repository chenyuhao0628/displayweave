import type { EvidenceState, SiteCopy } from "../content"

const order: EvidenceState[] = ["verified", "experimental", "deferred"]

export default function StatusBoard({ copy }: { copy: SiteCopy["status"] }) {
  return <div className="status-layout">
    <header className="section-heading"><span className="section-label">{copy.label}</span><h2>{copy.title}</h2><p>{copy.intro}</p></header>
    <div className="status-board">
      {order.map(state => <section className={`status-column status-${state}`} key={state}>
        <h3><span className="status-light" />{copy.names[state]}</h3>
        {copy.items.filter(item => item.state === state).map(item => <article key={item.title}><h4>{item.title}</h4><p>{item.detail}</p></article>)}
      </section>)}
    </div>
  </div>
}
