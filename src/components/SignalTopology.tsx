import type { SiteCopy } from "../content"

export default function SignalTopology({ copy }: { copy: SiteCopy["topology"] }) {
  return <figure className="topology" aria-label={copy.active}>
    <figcaption><span className="live-dot" />{copy.active}</figcaption>
    <svg className="topology-lines" viewBox="0 0 680 410" aria-hidden="true">
      <path className="signal signal-usb" d="M285 205 C385 205 390 96 505 96" />
      <path className="signal signal-wifi" d="M285 205 C385 205 390 314 505 314" />
      <path className="signal-node" d="M285 205 H505" />
    </svg>
    <div className="device-node node-mac"><span className="node-kicker">SOURCE 00</span><strong>{copy.mac}</strong><small>{copy.source}</small></div>
    <div className="device-node node-android"><span className="node-kicker">USB 01</span><strong>{copy.android}</strong><small>{copy.usb}</small></div>
    <div className="device-node node-apple"><span className="node-kicker">LAN 02</span><strong>{copy.apple}</strong><small>{copy.wifi}</small></div>
    <div className="route-note"><span>{copy.fallback}</span><b>USB ↔ WIFI</b></div>
  </figure>
}
