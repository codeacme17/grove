from pathlib import Path

application = Path(defines["app"]).resolve()
files = [str(application)]
symlinks = {"Applications": "/Applications"}
icon = str(application / "Contents/Resources/Grove.icns")
background = str(Path(defines["background"]).resolve())

format = "UDZO"
filesystem = "HFS+"
window_rect = ((180, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
scroll_position = (0, 0)
icon_size = 96
text_size = 13
label_pos = "bottom"
icon_locations = {application.name: (164, 202), "Applications": (476, 202)}
