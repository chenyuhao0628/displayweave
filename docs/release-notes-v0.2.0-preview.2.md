[English](release-notes-v0.2.0-preview.2.md) | [简体中文](release-notes-v0.2.0-preview.2.zh-CN.md)

# DisplayWeave `v0.2.0-preview.2` release notes

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2)

## Mac hotfix

- Release builds now ignore the benchmark-only `testPattern` preference, even
  when an older preference domain previously migrated it as enabled.
- Preference migration no longer copies the debug-only test-pattern key.
- Rotation/reconfiguration closes the old pattern before removing its virtual
  display. Disconnect cancels pending pattern creation and closes any window,
  preventing macOS from moving an orphaned full-screen pattern to the main display.

This fixes the changing-color screen on iPhone and the pattern that could remain
on the Mac main display until the app exited. The iOS/OpenDisplay discovery,
framing, H.264, hello, and input protocols are unchanged.

## Application update

Macs already running `v0.2.0-preview.1` (build 2) can use Sparkle's in-app
**Check for Updates** to install this build 3 release. The appcast archive is
authenticated with the same embedded EdDSA public key. Mac distribution remains
ad-hoc signed and not notarized.

Android also advances from version code 2 to 3 and can use its in-app update
check. The package name and pinned signing certificate are unchanged. The iOS
artifact remains an unsigned re-signing input and is not automatically updated.

## Assets

| File | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `0c0bbd61625a90ef5264097da3f25db0d77c1383421e506a97aab0c6eb50b501` |
| `DisplayWeave-Android.apk` | `04a7433deb4fa893ef95f216d9b4e35e01ff5466bda56d801b88792b0122b2e1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7a188576fec361daff62efbbb978f9800ae4fac55d269ffbfecb1806646289f4` |
| `appcast.xml` | `523252198c6bbd987281a9a60225576a53ba18e1f6421fbb2604be837868ec1f` |
| `android-update.json` | `25764708231ddcbc3f8eb7796a7ce8a9108ca10a9bee06665ccba2c49da09bd1` |

Android signing certificate SHA-256 remains
`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.
