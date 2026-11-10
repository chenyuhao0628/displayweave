[English](android-receiver-session-controls.md) | [简体中文](android-receiver-session-controls.zh-CN.md)

# Android receiver session controls

Included in [v0.3.4 (23)](../releases/v0.3.4.md) and [v0.3.5 (24)](../releases/v0.3.5.md). High-FPS trials remain experimental.

Settings fades after four seconds while remaining persistently accessible in the top-right corner; tapping it restores full opacity and opens settings. Video viewport geometry is unchanged. Cursor updates retain only the latest position for each UI animation frame; TCP ordering is unchanged and latency improvement is unconfirmed.

Both FPS trials are disabled by default. The 60/90 FPS option checks the codec size/rate range when performance points reject a rate up to 90 FPS. Native 60 permits a trial up to 2400×1080 (including portrait) at 60 FPS if size is supported, bypassing declared throughput. Hello and selected-decoder reports use the same policy. Mac quality must also be 100% for native transmission. Disable the trial and reconnect if lag or errors occur. There is no throughput-based automatic rollback.

When a Mac session is connected, a connected-device foreground service maintains foreground priority while the Activity is hidden; idle backgrounding still stops the listener. Surface loss during an active session releases the decoder without closing the authenticated socket. Surface return configures a decoder and requests a keyframe; disconnecting while backgrounded stops the server and service immediately.

## Evidence and gaps

On one Redmi 10, Android 13 / MIUI, encrypted LAN, the operator confirmed switching apps for approximately ten seconds and returning preserved the connection and restored video. The sender showed a native 2400×1080 / 60 FPS target and a 50% / 90 FPS target; sustained rendered FPS was not established. Cursor improvement is unconfirmed.

The Activity still owns the server. Activity/process destruction stops the session; the service does not restore a killed session. Long background, screen-off/Doze, notification denial, OEM eviction, Surface races, and decoder failures remain unverified. This is not a fully service-owned background receiver.

The release runtime fixture checks retired-server callback isolation and 20 immediate foreground-service start/stop pairs. Stop commands wait for foreground promotion and use start IDs to protect newer requests. These are emulator lifecycle checks, not OEM background/endurance measurements.
