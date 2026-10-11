# dmgbuild settings for DevVault-macos.dmg: the drag-to-Applications
# window. Run through tool/release/macos_dmg.sh, which passes:
#   -D app=<path to DevVault.app>  -D background=<multi-resolution .tiff>
# The icon positions match test/tool/dmg_background_test.dart, which draws
# the arrow between them.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}

# The disk's own icon in Finder's sidebar and on the desktop: the app's.
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 150),
    "Applications": (490, 150),
}
hide_extensions = [app_name]
