# dmgbuild settings: icon on the left, Applications on the right, dark background with an arrow.
import os
app = os.environ["KITSUNE_APP"]
background = os.environ["KITSUNE_BG"]
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
background = background
window_rect = ((200, 120), (660, 400))
icon_size = 112
text_size = 13
icon_locations = {"Kitsune.app": (170, 190), "Applications": (490, 190)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
