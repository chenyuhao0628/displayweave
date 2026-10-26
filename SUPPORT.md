[English](SUPPORT.md) | [简体中文](SUPPORT.zh-CN.md)

# Support

For v0.3.1, use the [current downloads](docs/releases/current.md), [pairing guide](docs/guides/secure-transport.md) and [troubleshooting paths](docs/README.md). Check Screen Recording, Accessibility when returning input, and Local Network permissions as applicable. Keep the receiving app in the foreground. For LAN connections, check the same network, multicast discovery and VPN/filter behavior.

## Report a reproducible issue

Include the app version/build on both devices, model and OS, send/receive role, mirror/extend mode, LAN or USB, selected resolution/codec/FPS/bitrate, requested versus measured FPS, steps and recovery behavior. Include relevant sanitized logs or crash text. Never attach invitations, private keys, device identifiers or full private screen captures.

Android supports both LAN and wired ADB-forward USB. For USB, record whether the receiver was in authorized `device` state, whether a data cable was used and what happened on reconnect. Wireless debugging is not a wired USB session. For aspect ratio/input issues, describe rotation, black bars and the touched area.

## Known boundaries

Wi-Fi performance depends on network conditions. Static desktops can produce fewer frames without indicating a disconnect. Mac-to-Mac, high refresh, real Pencil/Intel/multi-device performance and endurance still need broader physical acceptance. Mac v0.3.1 uses Apple Development signing and is unnotarized; iOS needs personal signing and may need reprovisioning. See [release verification and limits](docs/releases/v0.3.1.md) and [Mac permission recovery](docs/guides/mac-permissions.md).
