#!/usr/bin/env python3
"""Write deterministic Finder layout metadata for the guided macOS DMG."""

from __future__ import annotations

import os
import sys

from ds_store import DSStore
from mac_alias import Alias


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} MOUNT_POINT", file=sys.stderr)
        return 64

    mount_point = os.path.realpath(sys.argv[1])
    background = os.path.join(
        mount_point, ".background", "DisplayWeave.png"
    )
    if not os.path.isfile(background):
        print(f"missing DMG background: {background}", file=sys.stderr)
        return 2

    background_alias = Alias.for_file(background).to_bytes()
    window_settings = {
        "ShowStatusBar": False,
        "WindowBounds": "{{120, 120}, {760, 500}}",
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 180,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icon_view_settings = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": background_alias,
        "backgroundColorRed": 0.055,
        "backgroundColorGreen": 0.075,
        "backgroundColorBlue": 0.12,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": False,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 13.0,
        "iconSize": 104.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }

    ds_store_path = os.path.join(mount_point, ".DS_Store")
    with DSStore.open(ds_store_path, "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = window_settings
        store["."]["icvp"] = icon_view_settings
        store["."]["icvl"] = ("type", b"icnv")
        store["DisplayWeave.app"]["Iloc"] = (190, 245)
        store["Applications"]["Iloc"] = (570, 245)
        store["安装与首次运行说明.rtf"]["Iloc"] = (90, 400)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
