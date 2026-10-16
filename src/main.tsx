import { createRoot, hydrateRoot } from "react-dom/client"
import App from "./App"
import { localeForPathname } from "./locale"
import "./index.css"

const locale = localeForPathname(window.location.pathname)

document.documentElement.lang = locale === "zh" ? "zh-CN" : "en"
const root = document.getElementById("root")!
const app = <App initialLocale={locale} />
if (root.hasChildNodes()) hydrateRoot(root, app)
else createRoot(root).render(app)
