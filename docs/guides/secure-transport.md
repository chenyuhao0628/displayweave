[English](secure-transport.md) | [简体中文](secure-transport.zh-CN.md)

# Secure connections and pairing

Included in v0.3.1 on Apple and Android. Update sender and receiver, then follow the invitation workflow below. Older applications require an explicit insecure legacy choice; see [release notes](../releases/v0.3.1.md).

## Connect for the first time

1. On the receiving Mac, iPhone, iPad or Android device, open **Settings → Security and pairing** and generate a receiving invitation. Keep the receiver foregrounded and listening.
2. Copy the `DW1.` invitation to the sending Mac through a trusted channel. In its **Security and pairing** settings, import it and return to the device list.
3. Select the matching device over LAN or USB. The invitation pins the receiver's certificate; choosing the wrong cable/device fails verification. After successful pairing, both installations save trust and reconnect without an invitation. Two paired Macs can exchange sender/receiver roles.

An invitation expires after two minutes and can authorize one new peer. Five incorrect token attempts close the window. Invitations are memory-only, never discovery records or saved preferences. Clipboard copies expire after two minutes when the platform supports it; macOS clears its copy only if the clipboard has not changed. Do not publish an invitation. Close the window to cancel pending admission.

## Manage trust

Settings lists trusted and revoked peers with full certificate fingerprints. **Revoke** closes that peer's session and cancels pending admission. Revocation preserves history so an old pairing cannot silently become an unencrypted connection. Re-pairing requires a new invitation.

Transport certificates last one year. For expiry or lost identity material, explicitly **Reset local transport identity**, then revoke the old pairing on the other device and pair again. Reset closes sessions, invalidates old in-memory trust and preserves revoked peer records. Keychain errors fail closed; unlock the Keychain, use **Reload security state**, and retry. Transport identity is separate from app signing, Sparkle, Android updates and ADB authorization.

macOS uses its login Keychain. v0.3.0-preview.3 also pins its Apple signing identity; two distinct signed test binaries retained the same Keychain transport identity and paired peer. iOS uses the application's data-protection Keychain with `WhenUnlockedThisDeviceOnly`. No private key or trust record falls back to a file on an identity-storage error. A re-signed iOS app must retain a valid signing-generated application identifier; changing its signing/access-group identity can make previous Keychain data unavailable.

Android private keys are non-exportable Android Keystore entries; only public certificates and bounded peer records use app-private preferences. Cloud backup and device transfer exclude this data. **Reload security state** invalidates old in-memory objects; identity reset retains revoked history and can resume an explicitly recorded reset interrupted by a process exit. Android clears its owned invitation clipboard copy on consumption, expiry, cancellation or backgrounding, provided the clipboard has not changed.

## Old applications

Both receiver plaintext listening and sender plaintext permission start off. To use an older application, explicitly enable the relevant **insecure legacy compatibility** setting and use a trusted network. Changing the mode disconnects affected sessions. A new sender refuses legacy hello IDs with any pairing history, including revoked entries. TLS/authentication failures never enable legacy mode or retry in plaintext.

The port remains `9000`, Bonjour remains `_opensidecar._tcp`, and application framing is unchanged inside TLS. Secure receivers add `security=tls-v1` to discovery. Stripping this advertisement cannot change an already paired sender's certificate pin. ADB forwarding and usbmux carry the same authenticated stream; the Mac's usbmux relay accepts one loopback client and only forwards encrypted bytes.

## Verification boundary

Automated tests exercise actual platform TLS, pairing, malformed admission lengths, timeout, revocation, strict hello identity, bounded relay forwarding and synthetic H.264 in the Mac receiver. No desktop capture is used in those tests. Source UI is compiled separately from the user's installed app. Two-device LAN/USB performance and lifetime acceptance remain physical tests. See [the execution ledger](../archive/plans/feature-completion.md) and [protocol/security design](../reference/secure-transport-design.md).
