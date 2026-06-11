# Changelog

## [0.4.0](https://github.com/peetzweg/opensidecar/compare/v0.3.0...v0.4.0) (2026-06-11)


### Features

* built-in USB connectivity (drop the iproxy requirement) ([3ab674a](https://github.com/peetzweg/opensidecar/commit/3ab674acc15f271dd36d3001abee927aff762c41))
* built-in USB connectivity over usbmuxd, drop the iproxy requirement ([79e07a5](https://github.com/peetzweg/opensidecar/commit/79e07a5bf011ad341a45c3f0de4fb7eac3002463))
* editable device name for the WiFi connection picker ([eb6f036](https://github.com/peetzweg/opensidecar/commit/eb6f036f062954cdd43f0159763e50431a692de1))
* editable device name for the WiFi picker ([a470abc](https://github.com/peetzweg/opensidecar/commit/a470abc74a18b84194507669b645423f76c5b6f9))


### Bug Fixes

* cursor disappears after a reconnect ([288e3b1](https://github.com/peetzweg/opensidecar/commit/288e3b10b1e0538034e39715f99a869036d6b51e))
* device-name field needed two taps to edit ([0855813](https://github.com/peetzweg/opensidecar/commit/0855813fafb457f04cec8710617c0de9ef24dc91))
* re-send the cursor sprite to a reconnecting receiver ([2c13082](https://github.com/peetzweg/opensidecar/commit/2c130820deb94cebadada633a08c934e16d5c7db))
* wrap the performance overlay so it fits in portrait ([809368c](https://github.com/peetzweg/opensidecar/commit/809368cc8bdff47e6c59a732aac8df59f9431ba5))

## [0.3.0](https://github.com/peetzweg/opensidecar/compare/v0.2.0...v0.3.0) (2026-06-10)


### Features

* app presentation modes and menu bar panel sizing fix ([cc7caa5](https://github.com/peetzweg/opensidecar/commit/cc7caa593b99c1f2cecc2eb5e5fa55ecc6fd6fbe))
* end session when the device disconnects, rename Phone target to iOS ([5b99719](https://github.com/peetzweg/opensidecar/commit/5b99719cb5a630b3bfc103aca5844d4e82513456))
* experimental Metal renderer with true glass-time latency metric ([e9b784c](https://github.com/peetzweg/opensidecar/commit/e9b784c6b444c86b6527889827db0cd111d9e7f4))
* local cursor echo — pointer rendered on-device off the video path ([f043be5](https://github.com/peetzweg/opensidecar/commit/f043be5da9263fa3e5e86ca4f8d9b3759eee8f6e))
* menu bar app, true latency telemetry, quality presets, low-latency encoder ([d826668](https://github.com/peetzweg/opensidecar/commit/d826668f189078287682148744eeb341a50e32c0))
* transport badge and expanded debug overlay, Release deployment ([547355d](https://github.com/peetzweg/opensidecar/commit/547355d51f55c7eeaa07ffce4a7e336e6159617f))


### Bug Fixes

* Metal renderer A/B verdict — system layer wins, Metal stays opt-in ([49b4b8d](https://github.com/peetzweg/opensidecar/commit/49b4b8d83d59d780fb5059575dd8c13ab7afd041))
* rebuild the capture pipeline when the stream dies ([bc0f9d8](https://github.com/peetzweg/opensidecar/commit/bc0f9d8416d1fa301ed5e6859978738af64f06bb))


### Performance Improvements

* sustain true 60fps capture and cut input latency ([964d567](https://github.com/peetzweg/opensidecar/commit/964d5678e891055ea126b2ffa10fba97ade6a283))

## [0.2.0](https://github.com/peetzweg/opensidecar/compare/v0.1.0...v0.2.0) (2026-06-10)


### Features

* Arrange Displays shortcut in the Mac app ([c64bdec](https://github.com/peetzweg/opensidecar/commit/c64bdec442499408811ff64badaaae5954e129d5))
* opt-in performance overlay on the iPhone ([770b5d1](https://github.com/peetzweg/opensidecar/commit/770b5d1609aeda27e082e01cf7c5ee1dcf0df82f))
* permission status UI, iOS settings screen, system light/dark mode ([f5a4131](https://github.com/peetzweg/opensidecar/commit/f5a41311ed8bc2cd749f6168b37d8ed5339ff7f9))
* rebrand to a neutral Apple white-and-blue palette ([d2543a0](https://github.com/peetzweg/opensidecar/commit/d2543a067afd3ae286b451b95672200d5e47b3ef))


### Bug Fixes

* automatic recovery from stale and half-open connections ([8b49ccb](https://github.com/peetzweg/opensidecar/commit/8b49ccb540ee4e335d486472d470857dd8324808))

## 0.1.0 (2026-06-10)


### Features

* automated releases with downloadable macOS and iOS builds ([377b5d3](https://github.com/peetzweg/opensidecar/commit/377b5d3621b8cf826cc7f74ff3fdc23607577d08))
