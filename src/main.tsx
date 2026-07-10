import { createRoot } from "react-dom/client"
import App, { type Locale } from "./App"
import "./index.css"

const locale: Locale = window.location.pathname.endsWith("/zh.html") ? "zh" : "en"

createRoot(document.getElementById("root")!).render(<App initialLocale={locale} />)
