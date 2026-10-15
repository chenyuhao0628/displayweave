import type { Locale, SiteCopy } from "../content"

export default function SiteFooter({
  locale,
  copy,
}: {
  locale: Locale
  copy: SiteCopy["footer"]
}) {
  return (
    <footer>
      <div className="shell footer-grid">
        <div>
          <a
            className="brand footer-brand"
            href={locale === "zh" ? "zh.html" : "./"}
          >
            <img src="icon-256.png" alt="" />
            <span>DisplayWeave</span>
          </a>
          <p>{copy.line}</p>
        </div>
        <div>
          <a
            href={`https://github.com/chenyuhao0628/displayweave/blob/main/docs/README${locale === "zh" ? ".zh-CN" : ""}.md`}
          >
            {copy.docs}
          </a>
          <a href="https://github.com/chenyuhao0628/displayweave/issues">
            {copy.issues}
          </a>
          <a href="https://github.com/chenyuhao0628/displayweave">
            {copy.source}
          </a>
        </div>
        <span>© 2026 · GPL-3.0</span>
      </div>
    </footer>
  )
}
