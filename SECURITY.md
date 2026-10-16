[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

# Security Policy

## Supported release

Security fixes target the latest `main` and the current Preview release. Preview packages are development artifacts and do not receive a long-term support promise.

## Reporting a vulnerability

Do not post an exploitable vulnerability in a public issue. Use GitHub's private vulnerability reporting for `chenyuhao0628/displayweave` when available, or contact the repository maintainer privately through the address shown in the maintainer's GitHub profile. Include affected commit/version, platform, prerequisites, impact, reproduction steps, and any proposed mitigation. Avoid collecting unrelated screen content or device data.

## Current trust boundaries

- Published p8 uses plaintext local TCP and requires a trusted LAN. Post-p8 Apple source now defaults to mutually authenticated, certificate-pinned TLS with explicit invitation pairing; Android application integration remains in progress. See [source usage and boundaries](docs/secure-transport.md).
- Android USB requires ADB RSA authorization. This grants the Mac broad debugging trust, including shell/install capabilities outside DisplayWeave. Revoke USB debugging authorizations when no longer needed.
- The macOS Preview is ad-hoc signed and not notarized. Verify `SHA256SUMS.txt` and obtain packages only from the project Release.
- The Android Preview APK is signed with an offline project keystore. Verify the SHA-256 certificate fingerprint documented in the release checklist before first install or update.
- The iOS artifact is unsigned re-signing input and cannot be trusted or installed until the user supplies a valid signing identity. Third-party signing services add independent risk.
- Screen capture, Accessibility input injection, Local Network, and USB debugging permissions are powerful. Grant only the permissions needed for the selected transport and revoke them after testing.
- `CGVirtualDisplay` is a private API; platform changes can alter isolation or behavior.

## Sensitive material

Never commit Android keystores/passwords, Apple certificates/private keys, provisioning profiles containing private material, device identifiers from private logs, or captured user screens. Release scripts keep the Android keystore outside the repository and retrieve its password from Keychain.

## Release verification

Follow [docs/release-checklist.md](docs/release-checklist.md). A valid Preview publication requires source/build checks, APK v2 verification, macOS bundle verification, IPA archive hygiene, and SHA-256 validation.


## Mac LAN reception (source development build)

Receive mode advertises on the LAN and listens on TCP 9000. Post-p8 Apple source
requires authenticated TLS by default; explicit legacy compatibility is
unencrypted and should be enabled only on a trusted network. It accepts one
sender. Role changes, revocation and Stop receiving close owned connections;
remote shutdown is not exposed. Frame lengths, admission time and pending
sockets are bounded. See the [pairing guide](docs/secure-transport.md).
