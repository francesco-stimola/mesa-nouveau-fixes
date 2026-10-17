#!/usr/bin/env python3
"""Scripted GTK 4 session for the README's before/after GIF.

Usage: capture.py <output dir> before|after

Shows a window that looks like a small file manager, opens its main menu,
moves the highlight over the items and closes it again, capturing the
screen after every step. Run it once with the stock driver and once with
the patched one, both with GSK_RENDERER=ngl, then run compose.py:

  GSK_RENDERER=ngl ./capture.py shots before
  LD_LIBRARY_PATH=$HOME/nvfix-gl GSK_RENDERER=ngl ./capture.py shots after
  ./compose.py shots 14 ../../gtk-menus.gif
"""
import os
import sys

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

# GNOME Shell writes the screenshots, so the path must be absolute.
out, tag = os.path.abspath(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)

FILES = [
    ("folder", "Projects"),
    ("folder", "Photos"),
    ("x-office-document", "Report.odt"),
    ("x-office-spreadsheet", "Budget 2026.ods"),
    ("image-x-generic", "Holiday.jpg"),
    ("audio-x-generic", "Podcast.mp3"),
    ("text-x-generic", "Notes.txt"),
]
MENU = [
    ("New Folder", "Shift+Ctrl+N", "Create a folder here"),
    ("Select All", "Ctrl+A", "Select every item in this folder"),
    ("Show Hidden Files", "Ctrl+H", "Also list files whose name starts with a dot"),
    ("Sort by Name", "", "Sort the items alphabetically"),
    ("Preferences", "Ctrl+,", "Change how folders are shown"),
    ("Keyboard Shortcuts", "Ctrl+?", "List the keyboard shortcuts"),
    ("About Documents", "", "Version and credits"),
]
# (menu open, highlighted menu item, selected file)
STATES = [
    (False, -1, 0), (False, -1, 2), (True, -1, 2), (True, 0, 2), (True, 1, 2),
    (True, 2, 2), (True, 4, 2), (False, -1, 2), (False, -1, 4), (True, -1, 4),
    (True, 3, 4), (True, 5, 4), (True, 6, 4), (False, -1, 4),
]
CSS = b"""
* { transition: none; animation: none; }
window { background: #d8d8dc; }
.panel { background: white; border-radius: 10px; }
.bar { background: #ebebed; border-radius: 10px 10px 0 0; padding: 6px 8px; }
.title { font-weight: bold; }
.file { padding: 7px 12px; }
.sel { background: #3584e4; color: white; }
.item { padding: 7px 12px; border-radius: 6px; }
.hl { background: rgba(0, 0, 0, 0.09); }
.accel { color: alpha(currentColor, 0.55); }
.status { border-top: 1px solid #e0e0e2; padding: 8px 12px; color: #5e5e64; }
"""

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
# GNOME Shell only takes screenshots for a few well-known bus names.
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
              "RequestName", GLib.Variant("(su)", ("org.gnome.Screenshot", 4)),
              None, Gio.DBusCallFlags.NONE, -1, None)


def shot(path):
    bus.call_sync("org.gnome.Shell.Screenshot", "/org/gnome/Shell/Screenshot",
                  "org.gnome.Shell.Screenshot", "Screenshot",
                  GLib.Variant("(bbs)", (False, False, path)),
                  GLib.VariantType("(bs)"), Gio.DBusCallFlags.NONE, 20000, None)


class Demo:
    def __init__(self, app):
        self.app = app
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS, len(CSS))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        self.win = Gtk.ApplicationWindow(application=app, title="Documents")
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel.add_css_class("panel")
        panel.set_size_request(560, 380)
        panel.set_halign(Gtk.Align.START)
        panel.set_valign(Gtk.Align.START)
        panel.set_margin_top(20)
        panel.set_margin_start(20)

        bar = Gtk.Box(spacing=8)
        bar.add_css_class("bar")
        title = Gtk.Label(label="Documents", hexpand=True)
        title.add_css_class("title")
        self.button = Gtk.Button(icon_name="open-menu-symbolic")
        bar.append(Gtk.Button(icon_name="go-previous-symbolic"))
        bar.append(title)
        bar.append(self.button)
        panel.append(bar)

        self.files = []
        for icon, name in FILES:
            row = Gtk.Box(spacing=10)
            row.add_css_class("file")
            row.append(Gtk.Image(icon_name=icon, pixel_size=24))
            row.append(Gtk.Label(label=name, xalign=0))
            panel.append(row)
            self.files.append(row)
        self.status = Gtk.Label(xalign=0, vexpand=True, valign=Gtk.Align.END)
        self.status.add_css_class("status")
        panel.append(self.status)
        self.win.set_child(panel)

        self.popover = Gtk.Popover()
        self.popover.set_autohide(False)
        menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.items = []
        for label, accel, _ in MENU:
            item = Gtk.Box(spacing=24)
            item.add_css_class("item")
            item.append(Gtk.Label(label=label, xalign=0, hexpand=True))
            accel_label = Gtk.Label(label=accel, xalign=1)
            accel_label.add_css_class("accel")
            item.append(accel_label)
            menu.append(item)
            self.items.append(item)
        self.popover.set_child(menu)
        self.popover.set_parent(self.button)

        self.win.fullscreen()
        self.win.present()
        app.inhibit(self.win, Gtk.ApplicationInhibitFlags.IDLE, "GTK demo capture")
        self.step = 0
        GLib.timeout_add(2500, self.next)

    def next(self):
        open_, hl, sel = STATES[self.step]
        for i, row in enumerate(self.files):
            (row.add_css_class if i == sel else row.remove_css_class)("sel")
        for i, item in enumerate(self.items):
            (item.add_css_class if i == hl else item.remove_css_class)("hl")
        if open_ and hl >= 0:
            self.status.set_label(MENU[hl][2])
        else:
            self.status.set_label(f"“{FILES[sel][1]}” selected")
        if open_ and not self.popover.get_visible():
            self.popover.popup()
        elif not open_ and self.popover.get_visible():
            self.popover.popdown()
        # Redraw the window and the menu together for a few frames in a row,
        # as when the pointer moves over them.
        self.burst = 6
        GLib.timeout_add(16, self.redraw)
        return False

    def redraw(self):
        self.win.queue_draw()
        self.popover.queue_draw()
        self.burst -= 1
        if self.burst > 0:
            return True
        GLib.timeout_add(500, self.capture)
        return False

    def capture(self):
        shot(f"{out}/{tag}-{self.step:02d}.png")
        self.step += 1
        if self.step < len(STATES):
            GLib.timeout_add(50, self.next)
        else:
            self.app.quit()
        return False


app = Gtk.Application(application_id="org.example.GtkMenuDemo",
                      flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", lambda a: setattr(a, "demo", Demo(a)))
app.run([])
