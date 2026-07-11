import { assetHref, releaseTag, type SiteCopy } from "../content"

export default function ReleaseRail({ copy }: { copy: SiteCopy["release"] }) {
  return <div className="release-shell">
    <div className="release-intro"><div><span className="section-label">{copy.label}</span><h2>{copy.title}</h2></div><p>{copy.intro}</p></div>
    <div className="release-rail">
      {copy.assets.map((asset, index) => <article className="release-item" key={asset.file}>
        <div className="release-index">0{index + 1}</div>
        <div className="release-platform"><span>{asset.role}</span><strong>{asset.platform}</strong></div>
        <div className="release-copy"><h3>{asset.title}</h3><p>{asset.description}</p><code>{asset.file}</code></div>
        <a className="button button-release" href={assetHref(asset.file)}>{asset.action}<span aria-hidden="true">↗</span></a>
      </article>)}
    </div>
    <div className="release-foot"><span>{releaseTag}</span><strong>{copy.warning}</strong><a href={assetHref("SHA256SUMS.txt")}>{copy.checksum}</a></div>
  </div>
}
