[English](apple-video.md) | [简体中文](apple-video.zh-CN.md)

# Apple receiver HEVC and high refresh

Included in v0.3.0-preview.1: iOS/iPadOS offers H.264 and hardware-gated HEVC, and Apple receivers can negotiate up to 120fps within their capabilities. Physical high-refresh performance remains unverified; see [release evidence](release-notes-v0.3.0-preview.1.md).

The Mac sender's **Frame rate → Auto / 60 / 90 / 120** is a request. The chosen rate is bounded by the receiver screen, each codec envelope, user preference and pixel throughput (at most 4096×2304×60 pixels/second). The HEVC operating point also fits H.264 fallback. Large rasters may therefore negotiate 60 or 30 fps; lowering encoded quality can make a higher target feasible. Decoder throughput is an advertised conservative budget, not a measured performance result.

Both Apple receivers use the same bounded Annex-B parser and format creation. iOS explicitly advertises `appleVideoV1`; older peers retain H.264 and legacy framing. Hardware HEVC must be available at both ends. Decode failure requests H.264 once, retains that fallback for the connection, and closes the connection if fallback does not arrive within three seconds. Invalid dimensions, odd sizes, unsupported codec names, excessive FPS and mismatching parameter-set dimensions are rejected. Bitrate-only configuration updates preserve the current decoder references.

The iOS app enables `CADisableMinimumFrameDurationOnPhone` and sets a display link's `preferredFrameRateRange` while connected. That link presents cursor changes and stops when disconnected or detached from a window. Video remains on the system sample-buffer layer or the existing opt-in Metal path. Core Animation chooses actual refresh; low power, thermal state and display scheduling can reduce it. Receiver FPS counts video handoff, not photons. Only the existing Metal presented callback reports presented-frame timing on devices; simulator timing cannot establish physical performance.

Verification: 39 Swift suites including the new Apple capability/configuration/fallback policy; real synthetic H.264/HEVC bitstreams; Mac loopback high-rate configuration, out-of-envelope rejection and codec fallback; Mac universal Debug and iOS Simulator builds. iPad Simulator checks exercise invalid lengths, replacement, fragmented control, capability/configuration validation and synthetic codec fallback. Physical acceptance remains 30/60/90/120 targets at fixed raster/codec/bitrate, both renderers, low-power/thermal transitions, rotation and sustained presented FPS on a ProMotion device and high-refresh Mac screen.

Official reference checked 2026-10-16: [Apple: optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays). The local SDK's `CADisplayLink.h` and VideoToolbox APIs were also inspected. Requested refresh never guarantees actual panel cadence.
