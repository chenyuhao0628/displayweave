import type { SiteCopy } from "../content"

export default function TransportFlow({ copy }: { copy: SiteCopy["transport"] }) {
  return <div className="transport-layout">
    <header className="section-heading"><span className="section-label">{copy.label}</span><h2>{copy.title}</h2><p>{copy.intro}</p></header>
    <ol className="transport-flow">
      {copy.steps.map(step => <li key={step.code}><span className="flow-code">{step.code}</span><div><h3>{step.title}</h3><p>{step.body}</p></div></li>)}
    </ol>
  </div>
}
