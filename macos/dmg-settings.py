# Impostazioni di dmgbuild per il DMG di No Distraction (vedi make-dmg.sh).
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

# Sfondo 660×400 più la barra del titolo; le icone stanno sulla freccia disegnata.
window_rect = ((200, 160), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (175, 175),
    "Applications": (485, 175),
}
