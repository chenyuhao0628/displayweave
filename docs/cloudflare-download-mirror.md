# Cloudflare download mirror

DisplayWeave release binaries are mirrored as static files on Cloudflare Pages:

- Project: `displayweave-downloads`
- Custom domain: `downloads.urlget.cyou`
- Layout: `/releases/<tag>/<artifact>`
- Source template: `cloudflare-downloads/`

Pages is used only for immutable release files. The deployment must not contain a
`functions/` directory, so downloads do not consume Workers invocations. Each new
deployment must include every release tag that should remain available; a Pages
deployment replaces the previous static snapshot.

The Android p5 update feed remains on GitHub during migration because that client
only trusts GitHub release URLs. A later Android release may use the Cloudflare
mirror as its primary URL after the client has shipped support for the exact
`downloads.urlget.cyou` host.

Never commit Wrangler OAuth credentials or API tokens. Automated deployments
should use a scoped Cloudflare API token stored as a GitHub Actions secret.
