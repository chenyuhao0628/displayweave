import { renderToString } from "react-dom/server"
import App, { type Locale } from "./App"

// Preserve React's text boundaries for client hydration of both static routes.
export function render(locale: Locale = "en"): string {
  return renderToString(<App initialLocale={locale} />)
}
