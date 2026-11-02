# -*- coding: utf-8 -*-
import os.path

# -----------------------------------------------------------------------------
# Velora Premium DMG Installer Configuration (dmgbuild)
# -----------------------------------------------------------------------------
# Recreates a clean, modern, minimal, Apple-inspired layout:
# - Target artwork size: 1440 x 920 px (720 x 460 pt @ 2x Retina)
# - Window dimensions: 720 x 488 pt (content area: 720 x 460 pt)
# - Icon size: 110 pt, text size: 13 pt
# - Left slot: Velora.app at (195, 240)
# - Right slot: Applications at (525, 240)
# - Center slot: Minimal horizontal arrow at (360, 240) baked into artwork
# -----------------------------------------------------------------------------

# Volume name & paths (configurable via -D flag)
app_path = defines.get('app_path', 'build/Velora.app')
bg_image = defines.get('bg_image', 'assets/dmg/background.png')
vol_icon = defines.get('vol_icon', 'assets/icons/AppIcon.icns')

# Disk image format & filesystem
format = defines.get('format', 'UDZO')
filesystem = 'HFS+'

# Files & Symlinks
files = [app_path]
symlinks = {
    'Applications': '/Applications'
}

# Volume icon
if os.path.exists(vol_icon):
    icon = vol_icon
    badge_icon = vol_icon

# Background image
# When background.png is provided, dmgbuild automatically pairs it with
# background@2x.png to create a combined HiDPI / Retina background.tiff
if os.path.exists(bg_image):
    background = bg_image

# Window geometry (Points): ((x, y), (width, height))
# Height 488 pt accounts for macOS title bar (~28 pt) so content view matches 460 pt exactly
window_rect = ((200, 120), (720, 488))

# Clean Finder UI presentation (hide toolbar, pathbar, statusbar, sidebar)
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# Icon styling
icon_size = 110.0
text_size = 13.0
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100.0

# Exact Finder icon coordinates:
# Velora.app on the left at (195, 240)
# Applications symlink on the right at (525, 240)
# Symmetrically aligned around the center arrow at (360, 240)
icon_locations = {
    'Velora.app': (195, 240),
    'Applications': (525, 240),
    '.background.tiff': (195, 240),
    '.VolumeIcon.icns': (525, 240)
}

# Hide .app extension in Finder and hide internal files
hide_extensions = ['Velora.app']
hide = [
    '.background.tiff',
    '.VolumeIcon.icns'
]
