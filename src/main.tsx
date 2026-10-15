import { createRoot, hydrateRoot } from "react-dom/client"
import App, { type Locale } from "./App"
import "./index.css"

const locale: Locale = window.location.pathname.endsWith("/zh.html")
  ? "zh"
  : "en"

document.documentElement.lang = locale === "zh" ? "zh-CN" : "en"
const root = document.getElementById("root")!
const app = <App initialLocale={locale} />
if (root.hasChildNodes()) hydrateRoot(root, app)
else createRoot(root).render(app)
