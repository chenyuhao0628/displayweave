[English](mac-permissions.md) | [简体中文](mac-permissions.zh-CN.md)

# Mac signing and permission continuity

Starting with `v0.3.0-preview.3` (18), the Mac app uses a pinned Apple Development identity. Run and local packaging enforce that identity and compare upgrades. Earlier preview.2 assets remain ad-hoc signed and unchanged. The first migration from an ad-hoc copy may require authorization once more; subsequent fixed-signature builds preserve their code identity.

For v0.3.3 (22), packaging compared the exact downloaded build 21 app and verified the same designated requirement, team, bundle identity and arm64/x86_64 architectures. Build 21 → 22 privacy permissions were not interactively retested; older signed-overwrite observations below retain their original scope. See [release evidence](../releases/v0.3.3.md).

## Why upgrades lost permissions

The old ad-hoc app's designated requirement contained executable hashes, which changed between builds. Its unchanged bundle ID alone did not preserve the operating system's code identity. The new path signs successive builds with the same Apple-issued identity and checks their designated requirements. Debug keeps `app.displayweave.mac.debug`; Release keeps `app.displayweave.mac`. Preferences, pairing services, Bonjour, protocol and Sparkle keys are unchanged.

Apple [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) recommends an Apple-issued code-signing identity for reliable local-network identity tracking. [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains designated requirements. Notarization and permission continuity are separate concerns. A stable signature cannot override a user's denial, macOS policy changes or an explicit signing migration.

## Configure an existing identity

```bash
security find-identity -v -p codesigning
python3 tools/mac_signing.py configure --identity CERTIFICATE_SHA1
python3 tools/mac_signing.py xcode-settings
```

Replace the placeholder with an existing **Apple Development** or **Developer ID Application** certificate's 40-digit SHA-1. The command signs a temporary probe to obtain the real team and designated requirement; it does not infer the team from the certificate's display name. A local self-signed certificate is rejected. No key is created, exported or uploaded.

The public signing metadata is pinned outside Git at `~/Library/Application Support/DisplayWeave/Signing/mac-signing.json`, or at `DISPLAYWEAVE_MAC_SIGNING_CONFIG`. Keep this policy and the same Keychain identity for future builds. An absent/expired identity stops the build before any running development app is stopped. There is no ad-hoc fallback or automatic certificate selection. A renewed certificate can replace the fingerprint only if its team and both designated requirements remain identical; other changes require a separately tested migration.

The currently available Apple Development identity supports local unnotarized packaging, including the v0.3.2 stable release. It is not Developer ID distribution or notarization. Use [the production workflow](../releases/apple-distribution.md) when the required distribution credentials exist. GitHub-hosted release runners have no maintainer identity by default and now stop at signing preflight. Use the [local release workflow](../releases/local-release.md) until a runner is explicitly provisioned; this change does not export signing credentials to GitHub.

## Build and compare

The Run action and `tools/package-release.sh` consume the pinned policy. Signed Release apps use hardened runtime and the empty `Mac/OpenSidecarMac.entitlements`, including signing the embedded Sparkle framework. Verification checks every architecture, the leaf certificate, team, exact designated requirement, entitlements, bundle ID, feed and update key.

```bash
python3 tools/mac_signing.py verify /path/to/new/DisplayWeave.app
python3 tools/mac_signing.py compare /path/to/new/DisplayWeave.app \
  --baseline /path/to/previous/DisplayWeave.app
```

Update packaging requires `DISPLAYWEAVE_MAC_BASELINE_APP` to point to the previous published app. For the **first** migration from its ad-hoc signature, explicitly set `DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION=1`; the receipt marks reauthorization as necessary to check. Later releases compare against the prior signed app without this flag. The flag never permits a signed-to-ad-hoc downgrade. Reusing an existing output directory is rejected. Always publish a new version/build; never replace the preview.2 files.

## User permissions and duplicate entries

Use the installed `/Applications/DisplayWeave.app`. After the initial signing migration, check **Settings → Permissions & Diagnostics** and, when necessary, authorize Screen Recording and Accessibility in macOS settings, then quit and relaunch. Local Network's “Check needed” label means no receiver has been discovered; it is not proof that access is denied. Inspect the operating system's Local Network switch.

Historical builds can leave multiple entries with the same name. On the tested macOS 26.5.2, the Local Network page has no per-entry remove control; deleting obsolete app copies and Launch Services registrations does not erase these privacy records. Do not reset the entire system's privacy/network databases to hide them.

## Evidence and limits

- Regression before the fix: the actual Run script proceeded with `CODE_SIGN_IDENTITY=-` despite missing signing policy. After the fix, both Run and preview packaging fail before building when the policy is missing.
- Automated: all 20 cases in `python3 tools/test-mac-signing.py` pass, covering identity selection, absent/expired/self-signed identities, renewal continuity, all architectures, app/update identities, entitlements, explicit initial migration, immutable output and signed-to-ad-hoc rejection. The actual published preview.2 ZIP is also rejected as a downgrade from the signed local app.
- Artifacts: universal signed Release and Debug builds pass verification; the installed Release launches with the normal empty entitlements and signed Sparkle. Guided DMG creation, mounting and strict nested signature validation pass. The existing 12 production-distribution tests, bilingual documentation, release links and website build also pass.
- Real Keychain: `python3 tools/test-mac-signing-runtime.py` compiles two different signed binaries from the production security store. Their designated requirements match, and the second reads the first's unchanged transport identity and trusted peer without prompting. Only a random test namespace is created and removed.
- Interactive local acceptance on macOS 26.5.2: installed signed build `17`, confirmed Screen Recording and Accessibility allowed, then replaced it with a different signed executable/build `17.1` at the same path. Both permissions remained allowed without further authorization. Local Network retained the same three enabled DisplayWeave entries. The temporary previous app was deleted after validation.
- Release candidate `v0.3.0-preview.3` build `18` was then installed over signed `17.1` at the same path. Screen Recording and Accessibility again remained allowed without reauthorization; the same three Local Network entries stayed enabled. No previous-app backup was retained.
- Build `17.1` is a **local validation rebuild of preview.2**, not a published release. That experiment did not change public downloads; preview.3 (18) is the subsequent release of the signing fix. No certificate-expiry, cross-team migration, real receiver traffic, screen capture or virtual-display behavior is claimed by this test. No independent online display was established, so display/capture tests were skipped.
