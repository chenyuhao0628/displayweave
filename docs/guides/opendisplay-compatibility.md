[English](opendisplay-compatibility.md) | [简体中文](opendisplay-compatibility.zh-CN.md)

# Connecting OpenDisplay and DisplayWeave

DisplayWeave exposes both connection choices on the main screen. Existing OpenDisplay installations do not need to be renamed or reinstalled to use their supported stream protocol. These connection choices were introduced in v0.3.0-preview.2 (17) and are retained in v0.3.1 (20).

| Sender → receiver | What to select |
| --- | --- |
| DisplayWeave → DisplayWeave | Use encrypted pairing; generate the invitation on the receiver and import it on the sending Mac |
| DisplayWeave → OpenDisplay | On the sending Mac, choose **Client compatibility → Both clients** and connect the device from the same list; no invitation for the OpenDisplay peer |
| OpenDisplay → DisplayWeave Mac/iOS/Android | On the DisplayWeave receiver's main screen choose **OpenDisplay compatibility**; then select it in OpenDisplay |
| DisplayWeave → mixed new and old receivers | Enable **Both clients** on the sender; paired DisplayWeave connections stay encrypted and unpaired OpenDisplay peers use the legacy protocol |

The sender's option allows both protocols. A receiver listens in the selected mode, one sender at a time; switching mode disconnects its current session. There is no automatic plaintext fallback after a TLS failure. Legacy mode is unencrypted and should be used on a trusted network. A connection plan with a known identity cannot bypass trust by removing its TLS advertisement or claiming a different/missing hello ID. An anonymous legacy peer has no authenticated identity. A receiver upgraded from OpenDisplay keeps its original install ID; pair it for encrypted use.

## Compatibility boundary

Discovery preserves `_opensidecar._tcp`, TCP port 9000 and the four-byte network-order frame length. Apple retains the legacy JSON/Annex-B video format; Android's DWV2 binary format is used only after independent capability negotiation. Early OpenDisplay hello messages without `id` are accepted only in an explicitly allowed legacy plan with no expected peer ID. Identified and encrypted plans still require matching identity; invalidated plans reject anonymous peers too.

Existing Mac preference-domain migration, iOS bundle ID, Android package/signing identity and update signature keys remain unchanged. Receiving a protocol-1 peer does not enable DisplayWeave-only secure desktop input or advanced Pencil actions.

## Evidence and limits

Compared upstream OpenDisplay `origin/main` at `b9eec1f` (v1.25.0 appcast commit): `Shared/StreamReceiver.swift::sendHello`, `Shared/Protocol.swift`, and `Mac/MacSender.swift::sendStreamConfiguration`. Tests cover pre-ID Apple hello, current upstream additive `pv`, `panel`, `videoCaps`, `cursorPort`, and `framesPerSecond`; unknown optional fields remain ignorable. The Mac receiver loopback test accepts upstream-style welcome/config and real synthetic H.264 frames. Security tests retain pinned identity, no downgrade after pairing/revocation, and reset invalidation.

This is connection/protocol compatibility, not a claim that every upstream-specific feature is implemented. Upstream UDP cursor, remote power, update notices and protocol-specific Pencil extensions are not advertised as DisplayWeave features. Physical upstream-binary Mac/iOS USB/LAN, rotation, input and endurance still require the matrix below. Do not label source/fixture checks as full hardware compatibility.

## Physical acceptance matrix

For both old→new and new→old: test Mac/iPhone/iPad receivers over LAN, Apple USB where supported, H.264 mirror/extend, rotate, touch/scroll, disconnect/reconnect and sleep/wake. For Android, use a Mac sender with H.264 over LAN and ADB USB where the sender supports Android USB. Record exact application versions, OS/device, transport, resolution, duration and actual video behavior. Test mixed old/new receivers concurrently. Virtual displays require an independent online display. Record unsupported features and SKIP honestly.
