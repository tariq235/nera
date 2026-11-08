# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# dmgbuild settings for Nera's disk image: Nera on the left, Applications on the right, over the background
# drawn by dmg-background.swift. Run by make-dmg.sh with -D app=<Nera.app> -D background=<background.tiff>.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
notes = defines.get("notes")  # noqa: F821
files = [app] + ([notes] if notes else [])
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (640, 448))  # 420 of content plus the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (170, 180), "Applications": (470, 180)}
if notes:
    icon_locations[os.path.basename(notes)] = (320, 335)
hide_extension = [os.path.basename(app)]
