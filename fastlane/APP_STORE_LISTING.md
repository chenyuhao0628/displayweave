# App Store Connect listing — reference

Canonical copy for the iOS app's App Store Connect / TestFlight text fields, kept in
version control so we know what's live and can edit deliberately.

> **Privacy:** the **Feedback email** and any contact addresses are intentionally
> **not** stored here. Set/maintain those directly in App Store Connect.

When you change a field in App Store Connect, update it here too.

---

## App Information (applies to all versions)

**Name**
```
OpenDisplay
```

**Subtitle** _(max 30 chars)_
```
Second monitor for your Mac
```

**Copyright** _(format: year + rights holder; App Store Connect adds the © itself — do not type it)_
```
2026 Philip Poloczek
```

**Content Rights** — does the app contain, show, or access third-party content?
> **No.** The app only displays the user's own Mac screen over a direct connection;
> it bundles and streams no third-party content.

**Category:** Utilities (primary)

---

## Version metadata (per release)

**Promotional Text** _(max 170 chars; editable without a new build)_
```
Turn the iPhone or iPad you already own into a real second display for your Mac — open source and private. Works over USB or Wi-Fi.
```

**Description**
```
OpenDisplay turns your iPhone or iPad into a second display for your Mac.

It's the open-source way to put your spare Apple device to work as a real extended monitor — drag windows onto it, keep chat, notes, or logs in view, and gain screen space anywhere you go. It's not a mirror: it's a genuine additional display your Mac treats like any other monitor.

• Real extended display — arrange it in your Mac's Display settings and drag windows across
• Connect over USB for the lowest latency, or over Wi-Fi with zero setup
• Retina-sharp, pixel-for-pixel rendering
• Touch and scroll — tap, drag, and two-finger scroll to control your Mac
• Works in portrait or landscape
• Private by design — a direct connection between your own devices, with no accounts, no servers, and no tracking

IMPORTANT: OpenDisplay requires the companion OpenDisplay app for Mac, running on your computer on the same cable or Wi-Fi network. Get it at https://peetzweg.github.io/opendisplay — without it, this app has nothing to connect to.

OpenDisplay is open source under the GPL-3.0 license. Read the code, report issues, or contribute at https://github.com/peetzweg/opendisplay
```

**Keywords** _(max 100 chars; comma-separated, no spaces after commas)_
```
second monitor,external display,extend screen,monitor,display,screen,ipad as display,usb,wireless
```

**Support URL**
```
https://peetzweg.github.io/opendisplay
```

**Marketing URL** _(optional)_
```
https://peetzweg.github.io/opendisplay
```

**Privacy Policy URL**
```
https://peetzweg.github.io/opendisplay/privacy.html
```

---

## TestFlight

**Beta App Description**
```
OpenDisplay turns your iPhone or iPad into a second display for your Mac.

To use this beta you also need the companion OpenDisplay app for Mac running on your computer, on the same USB cable or Wi-Fi network. Get it here:
https://peetzweg.github.io/opendisplay

Once both are running: connect over USB for the lowest latency or over Wi-Fi with no setup, drag windows onto the device, try touch and two-finger scroll, and rotate between portrait and landscape.

Please report anything that looks off — connection drops, latency, image sharpness, rotation, or touch accuracy. Thanks for testing!
```

**Feedback email** — _managed in App Store Connect; not stored here._

---

## Notes for future edits

- **App name change (2026-06-30):** Apple rejected the previous name "OpenSidecar"
  under Guideline 5.2.5 — "Sidecar" is confusingly similar to Apple's Sidecar feature.
  Renamed to **OpenDisplay**. The on-device name lives in `project.yml` (iOS
  `CFBundleDisplayName`, Mac `PRODUCT_NAME` / `BUNDLE_DISPLAY_NAME`) and **needs a new
  build** to take effect; the store **Name** field is set in App Store Connect. The repo,
  Pages site, and bundle IDs (`com.peetzweg.opensidecar.*`) intentionally keep the old
  slug — bundle IDs are permanent and renaming them would spawn a new ASC app.
- **Trademark caution:** keep Apple's feature name "Sidecar" and competitor brands
  ("Duet", "Luna") **out of every field** — name, subtitle, promo text, description,
  keywords. Comparing to those products is fine on the website, not in store metadata.
- **No price references (Guideline 2.3.7):** keep "free" / "no cost" / "discounted" out
  of the subtitle, promotional text, keywords, and especially the **screenshots** — the
  screenshots are what got flagged. Apple permits price claims only in the Description,
  but we lead with "open source" (a licensing fact) instead, which reads fine anywhere.
- The Description states the **Mac-app requirement** on purpose; App Review needs to
  know the app is non-functional without the companion. Keep that line.
- Field limits: Subtitle ≤ 30, Promotional Text ≤ 170, Keywords ≤ 100 (whole string,
  commas included).
