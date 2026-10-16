[English](cloudflare-download-mirror.md) | [简体中文](cloudflare-download-mirror.zh-CN.md)

# Cloudflare download mirror

DisplayWeave release binaries are mirrored as static files on Cloudflare Pages:

- Project: `displayweave-downloads`
- Custom domain: `downloads.urlget.cyou`
- Layout: `/releases/<tag>/<artifact>`
- Source template: `cloudflare-downloads/`

Pages serves immutable release files and a static backup website under `/displayweave/`. The deployment must not contain a
`functions/` directory, so downloads do not consume Workers invocations. Each new
deployment must include every release tag that should remain available; a Pages
deployment replaces the previous static snapshot.

Android p6 uses the exact `downloads.urlget.cyou` release path as its primary APK
URL and the matching GitHub Release as its fallback. Fallback is limited to
connection, HTTP availability, and transport failures. Size, hash, package,
version, SDK, or certificate failures stop the update instead of changing source.
Android p5 must be upgraded to p6 manually once because p5 trusts only GitHub.

The backup website contains copies of the checked-in feeds. It does not change the GitHub Pages URLs embedded in installed apps. See [local publication](local-release.md) for the outage procedure.

Never commit Wrangler OAuth credentials or API tokens. Automated deployments
should use a scoped Cloudflare API token stored as a GitHub Actions secret.
