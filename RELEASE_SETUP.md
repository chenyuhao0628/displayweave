# Release Setup — OpenSidecar

## Distribution strategy

| Target | Method | Why |
|--------|--------|-----|
| iOS app | App Store (TestFlight → public) | Standard APIs, App Store safe |
| Mac app | Direct download (Developer ID + notarized) | Uses `CGVirtualDisplay` (private API) — banned from Mac App Store |

## Bundle IDs

| App | Bundle ID |
|-----|-----------|
| iOS | `com.peetzweg.opensidecar.ios` |
| Mac | `com.peetzweg.opensidecar.mac` |

Apple Developer account: `phil.czek@gmail.com`, Team ID: `FCL75KKM67`

---

## Checklist

### ✅ Done
- [x] Registered `com.peetzweg.opensidecar.ios` and `com.peetzweg.opensidecar.mac` in Apple Developer Portal (no capabilities needed)
- [x] Created iOS app in App Store Connect — SKU `opensidecar-ios`, iOS only
- [x] Created App Store Connect API key (key_id, issuer_id, .p8 downloaded)
- [x] Created private certs repo `peetzweg/opensidecar-certs` with deploy key
- [x] Ran `fastlane match appstore` for iOS — cert + profile installed ✓
- [x] Updated bundle IDs in code (`project.yml`, `Fastfile`, `Appfile`, `Matchfile`)
- [x] Fastfile, Gemfile, entitlements, workflow all updated and ready to commit

### 🔲 Mac cert (can defer — doesn't block iOS)
- [ ] Run `fastlane match developer_id` with `--platform macos` flag:
  ```sh
  source .env && bundle exec fastlane match developer_id \
    --app_identifier com.peetzweg.opensidecar.mac \
    --platform macos \
    --username phil.czek@gmail.com
  ```

### 🔲 Step A — GitHub repository secrets
Go to: github.com/peetzweg/opensidecar → Settings → Secrets and variables → Actions → New repository secret

| Secret | Value |
|--------|-------|
| `DEVELOPMENT_TEAM` | `FCL75KKM67` |
| `MATCH_GIT_URL` | `git@github.com:peetzweg/opensidecar-certs.git` |
| `MATCH_PASSWORD` | The password you chose when running match |
| `MATCH_DEPLOY_KEY` | Contents of `~/.ssh/opensidecar_match` (the **private** key) |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from App Store Connect |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from App Store Connect |
| `APP_STORE_CONNECT_KEY_CONTENT` | `base64 -i ~/path/to/AuthKey_XXX.p8 \| tr -d '\n'` |

### 🔲 Step B — Commit and push
```sh
git add Gemfile Gemfile.lock fastlane/ Mac/OpenSidecarMac.entitlements \
        iOS/OpenSidecariOS.entitlements project.yml \
        .github/workflows/release.yml .gitignore RELEASE_SETUP.md
git commit -m "feat: fastlane release pipeline for iOS TestFlight and Mac notarized builds"
git push
```

### 🔲 Step C — Trigger a release
release-please keeps a "release PR" open on main. Merging it tags a release, which kicks off the CI build. Check if one is already open:
```sh
gh pr list --label "autorelease: pending"
```

---

## Notes

**App name "OpenSidecar":** Safe to use. Apple holds USPTO trademark #88701277 on "Sidecar" (software category), but multiple third-party apps named "SideCar" and "Sidecar: Automotive assistant" are live on the App Store. The "Open" prefix provides clear differentiation. In App Store copy, avoid framing it as "a replacement for Apple Sidecar" — describe it as its own product.

**Mac app distribution:** Direct download via GitHub Releases (notarized .zip). No Mac App Store listing needed.

**Mac cert issue:** `fastlane match developer_id` fails without `--platform macos` flag — defaults to iOS platform which is wrong for Developer ID certs. Use the command above with that flag.
