import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// The site is served from the DisplayWeave repository via GitHub Pages.
// The Pages Actions workflow uploads build/site/client. Relative base keeps URLs working
// under the repository subpath without hardcoding it. Site output is isolated
// from the source documentation in docs/.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "build/site/client",
    emptyOutDir: true,
  },
})
