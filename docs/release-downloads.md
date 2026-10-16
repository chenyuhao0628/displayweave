[English](release-downloads.md) | [简体中文](release-downloads.zh-CN.md)

# Release downloads

DisplayWeave release binaries are published as GitHub Release assets on
`chenyuhao0628/displayweave`. There is no off-platform download host.

- Layout: `https://github.com/chenyuhao0628/displayweave/releases/download/<tag>/<artifact>`
- Mac update artifact: `DisplayWeave-macOS.zip`
- Android update artifact: `DisplayWeave-Android.apk`

The checked-in update feeds — `public/appcast.xml` and
`public/android-update.json` — point only at that GitHub release path. Each
download is verified by size, SHA-256, package name, version code, minimum SDK
and the pinned signing certificate through one shared verification path. An
integrity or identity failure stops the update instead of switching to another
source.

Repository policy: do not add off-GitHub download links for zipped or
executable content to documentation, release notes, feeds, or application code.
Distribution stays on GitHub Releases.

See [local publication](local-release.md) for reproducible commands and
validation requirements.
