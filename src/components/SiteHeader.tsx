import { useRef } from "react"
import type { Locale, SiteCopy } from "../content"

export default function SiteHeader({
  locale,
  copy,
}: {
  locale: Locale
  copy: SiteCopy
}) {
  const menu = useRef<HTMLDetailsElement>(null)
  const languageHref = locale === "en" ? "zh.html" : "./"
  const links = ["status", "transport", "evidence", "trust", "faq"] as const
  const navigation = links.map((id) => (
    <a key={id} href={`#${id}`}>
      {copy.nav[id]}
    </a>
  ))

  return (
    <header className="site-header">
      <a className="skip-link" href="#main">
        {locale === "zh" ? "跳到主要内容" : "Skip to content"}
      </a>
      <div className="shell nav-shell">
        <a className="brand" href={locale === "zh" ? "zh.html" : "./"}>
          <img src="icon-256.png" alt="" />
          <span>DisplayWeave</span>
        </a>
        <nav aria-label={locale === "zh" ? "主导航" : "Primary"}>
          {navigation}
        </nav>
        <div className="nav-actions">
          <a
            className="language"
            href={languageHref}
            lang={locale === "en" ? "zh-CN" : "en"}
          >
            {copy.language}
          </a>
          <a
            className="github-link"
            href="https://github.com/chenyuhao0628/displayweave"
          >
            GitHub
          </a>
          <a className="button button-small" href="#download">
            {copy.nav.download}
          </a>
        </div>
        <details
          className="mobile-menu"
          ref={menu}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              event.currentTarget.open = false
              event.currentTarget.querySelector("summary")?.focus()
            }
          }}
        >
          <summary>
            {locale === "zh" ? "菜单" : "Menu"}
            <span aria-hidden="true">＋</span>
          </summary>
          <nav
            aria-label={locale === "zh" ? "移动导航" : "Mobile"}
            onClick={(event) => {
              if ((event.target as HTMLElement).closest("a") && menu.current)
                menu.current.open = false
            }}
          >
            <a href="#download">{copy.nav.download}</a>
            {navigation}
            <a href={languageHref} lang={locale === "en" ? "zh-CN" : "en"}>
              {copy.language}
            </a>
            <a href="https://github.com/chenyuhao0628/displayweave">GitHub</a>
          </nav>
        </details>
      </div>
    </header>
  )
}
