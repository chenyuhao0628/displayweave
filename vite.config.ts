import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// The site is served from the DisplayWeave repository via GitHub Pages.
// (Pages "deploy from branch" → /docs). Relative base keeps asset URLs working
// under the repository subpath without hardcoding it. Site output is isolated
// from the source documentation in docs/.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "site-dist",
    emptyOutDir: true,
  },
})
