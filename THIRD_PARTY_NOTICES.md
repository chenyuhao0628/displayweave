# Third-Party Notices

DisplayWeave is an independent community project derived from OpenDisplay and
informed by other open-source display-streaming projects. This file records the
primary upstream sources relevant to the repository.

## OpenDisplay

- Project: OpenDisplay
- Source: https://github.com/peetzweg/opendisplay
- License: GNU General Public License v3.0

DisplayWeave retains OpenDisplay's Git history, applicable copyright notices,
and GPL-3.0 licensing requirements. The repository root `LICENSE` contains the
license text governing the current DisplayWeave work. OpenDisplay is the source
project; DisplayWeave is independently named and maintained rather than
presented as an official OpenDisplay distribution.

## SideScreen

- Project: SideScreen
- Source: https://github.com/tranvuongquocdat/SideScreen
- License: MIT License

SideScreen was reviewed as a technical reference for end-to-end frame-rate
configuration, HEVC use, Android high-refresh rendering, transport separation,
and performance measurement. DisplayWeave did not import the SideScreen
repository wholesale. The current high-refresh implementation was adapted to
the existing OpenDisplay architecture. If future changes copy or substantially
adapt specific SideScreen source, the corresponding MIT copyright and license
notice must be retained alongside that code and recorded here.

## Sparkle

- Project: Sparkle
- Source: https://github.com/sparkle-project/Sparkle
- License: MIT License

The macOS target uses Sparkle as a Swift Package dependency for application
update support. Sparkle's own license and notices are distributed with the
embedded framework when included in an application build.
