"""The viewer window: the Mol* viewport with the chrome floating over it.

The layout is the one the iOS and Flutter shells present — a full-bleed 3D viewport with a menu
bar, an info card, an Objects panel, a command bar and the hover tooltip drawn on top of it — built
here from GTK widgets in a `Gtk.Overlay`.
"""

from __future__ import annotations

import os
from typing import Callable

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

from gi.repository import Gdk, GdkPixbuf, Gtk, Pango  # noqa: E402

from . import APP_VERSION  # noqa: E402
from .bridge import MolStarBridge  # noqa: E402
from .controller import COLOR_PICKER_KEYS, ViewerController  # noqa: E402
from .manual import show_manual  # noqa: E402
from .models import (  # noqa: E402
    BACKGROUND_PRESETS,
    ExportFormat,
    MeasureKind,
    MolAppObject,
    MoleculeRepresentation,
    MoleculeVisibilityFeature,
    NAMED_COLORS,
    ObjectRepresentation,
    STATE_EXTENSIONS,
    STRUCTURE_EXTENSIONS,
    rgb_from_hex,
)
from .webview import MolStarWebView  # noqa: E402

#: Every colour and size the chrome paints with, as one stylesheet. The chrome floats over a live
#: 3D canvas whose background is user-settable all the way to white, so these are compositing
#: decisions rather than theme colours — the same reasoning as `tokens.dart`, and the same values.
_CSS = b"""
window { background-color: #0B0F14; }

.panel {
  background-color: rgba(0, 0, 0, 0.85);
  border-radius: 8px;
  padding: 12px;
}
.menubar-strip { background-color: rgba(0, 0, 0, 0.85); }
.menubar-strip menubar { background-color: transparent; }
.menubar-strip menubar > menuitem {
  color: #FFFFFF;
  font-size: 15px;
  font-weight: 600;
  padding: 4px 10px;
}
.menubar-strip menubar > menuitem:hover { background-color: rgba(255, 255, 255, 0.18); }

.card-title { color: #FFFFFF; font-size: 17px; font-weight: 600; }
.status { color: rgba(255, 255, 255, 0.65); font-size: 13px; }
.error { color: rgba(255, 80, 80, 0.9); font-size: 12px; }
.section-title { color: #FFFFFF; font-size: 12px; font-weight: 600; }
.object-name { color: #FFFFFF; font-size: 12px; font-weight: 500; }
.object-type { color: rgba(255, 255, 255, 0.65); font-size: 10px; }
.empty { color: rgba(255, 255, 255, 0.65); font-size: 11px; }

.chip {
  color: rgba(255, 255, 255, 0.65);
  font-size: 10px;
  font-weight: 500;
  padding: 1px 5px;
  min-height: 0;
  min-width: 0;
  border: none;
  background-image: none;
  background-color: transparent;
  border-radius: 3px;
}
.chip-selected { color: #FFFFFF; background-color: rgba(255, 255, 255, 0.25); }

.flat-icon {
  border: none;
  background-image: none;
  background-color: transparent;
  padding: 2px;
  min-height: 0;
  min-width: 0;
  color: #FFFFFF;
}
.flat-icon:disabled { color: rgba(255, 255, 255, 0.45); }

.tooltip-chip {
  background-color: rgba(0, 0, 0, 0.85);
  color: #FFFFFF;
  font-size: 12px;
  font-weight: 500;
  border-radius: 999px;
  padding: 4px 8px;
}
.measure-banner {
  background-color: rgba(33, 150, 243, 0.85);
  color: #FFFFFF;
  font-size: 12px;
  font-weight: 600;
  border-radius: 999px;
  padding: 6px 12px;
}
.command-bar {
  background-color: rgba(0, 0, 0, 0.85);
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 10px;
  padding: 4px 10px;
}
.command-bar entry {
  background-color: transparent;
  background-image: none;
  border: none;
  box-shadow: none;
  color: #FFFFFF;
  font-size: 14px;
}
.manual-title { font-weight: 600; font-size: 15px; }
.manual-commands {
  background-color: rgba(127, 127, 127, 0.12);
  border-radius: 8px;
  padding: 10px;
}
.manual-syntax { font-family: monospace; font-weight: 600; font-size: 12px; }
.manual-detail { font-size: 12px; }
.manual-version { opacity: 0.5; font-size: 12px; }
"""

_EYE_ICONS = {True: "view-reveal-symbolic", False: "view-conceal-symbolic"}


class MolAppWindow(Gtk.ApplicationWindow):
    def __init__(self, application: Gtk.Application) -> None:
        super().__init__(application=application, title="MolApp")
        self.set_default_size(1280, 860)

        self.bridge = MolStarBridge()
        self.controller = ViewerController(self.bridge)
        self.viewport = MolStarWebView(self.bridge)

        self._objects_snapshot: list[MolAppObject] | None = None
        self._is_info_card_visible = True
        self._is_objects_panel_expanded = True
        self._menu_items: dict[str, Gtk.MenuItem] = {}

        _install_css()
        self._build()
        self.bridge.add_listener(self._sync)
        self.controller.add_listener(self._sync)
        self._sync()

    # MARK: - Construction

    def _build(self) -> None:
        self.overlay = Gtk.Overlay()
        self.overlay.add(self.viewport.widget)
        self.overlay.connect("get-child-position", self._position_child)
        self.add(self.overlay)

        self._menu_strip = self._build_menu_bar()
        self._menu_strip.set_valign(Gtk.Align.START)
        self._menu_strip.set_halign(Gtk.Align.FILL)
        self.overlay.add_overlay(self._menu_strip)

        self._left_rail = self._build_left_rail()
        self.overlay.add_overlay(self._left_rail)

        self._command_bar = self._build_command_bar()
        self.overlay.add_overlay(self._command_bar)

        self._banner = Gtk.Label(label="")
        self._banner.get_style_context().add_class("measure-banner")
        self._banner.set_halign(Gtk.Align.CENTER)
        self._banner.set_valign(Gtk.Align.START)
        self._banner.set_margin_top(52)
        self._banner.set_no_show_all(True)
        self.overlay.add_overlay(self._banner)

        self._tooltip = Gtk.Label(label="")
        self._tooltip.get_style_context().add_class("tooltip-chip")
        self._tooltip.set_no_show_all(True)
        self.overlay.add_overlay(self._tooltip)
        # The tooltip is positional, never interactive: it must not eat clicks meant for the canvas.
        self._tooltip.set_sensitive(False)
        self._banner.set_sensitive(False)

    def _build_menu_bar(self) -> Gtk.Widget:
        accelerators = Gtk.AccelGroup()
        self.add_accel_group(accelerators)
        self._accelerators = accelerators

        bar = Gtk.MenuBar()
        bar.append(self._file_menu())
        bar.append(self._edit_menu())
        bar.append(self._display_menu())
        bar.append(self._calculation_menu())
        bar.append(self._measure_menu())
        bar.append(self._help_menu())

        strip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        strip.get_style_context().add_class("menubar-strip")
        strip.pack_start(bar, True, True, 0)
        return strip

    def _submenu(self, title: str) -> tuple[Gtk.MenuItem, Gtk.Menu]:
        item = Gtk.MenuItem(label=title)
        menu = Gtk.Menu()
        item.set_submenu(menu)
        return item, menu

    def _menu_item(
        self,
        menu: Gtk.Menu,
        label: str,
        on_activate: Callable[[], None],
        key: str | None = None,
        accelerator: tuple[int, Gdk.ModifierType] | None = None,
    ) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label=label)
        item.connect("activate", lambda _item: on_activate())
        if accelerator is not None:
            item.add_accelerator(
                "activate", self._accelerators, accelerator[0], accelerator[1], Gtk.AccelFlags.VISIBLE
            )
        menu.append(item)
        if key is not None:
            self._menu_items[key] = item
        return item

    @staticmethod
    def _section_label(menu: Gtk.Menu, text: str) -> None:
        item = Gtk.MenuItem(label=text.upper())
        item.set_sensitive(False)
        menu.append(item)

    def _file_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("File")
        self._menu_item(
            menu, "Open Structure", self._open_structure,
            accelerator=(Gdk.KEY_o, Gdk.ModifierType.CONTROL_MASK),
        )
        menu.append(Gtk.SeparatorMenuItem())
        self._menu_item(
            menu, "Save State (.molapp)", self._save_state, key="saveState",
            accelerator=(Gdk.KEY_s, Gdk.ModifierType.CONTROL_MASK),
        )
        self._menu_item(menu, "Open State (.molapp)", self._open_state)
        menu.append(Gtk.SeparatorMenuItem())

        export_item = Gtk.MenuItem(label="Export Display")
        export_menu = Gtk.Menu()
        export_item.set_submenu(export_menu)
        for export_format in ExportFormat:
            entry = Gtk.MenuItem(label=export_format.title)
            entry.connect(
                "activate", lambda _item, fmt=export_format: self._export_image(fmt)
            )
            export_menu.append(entry)
        menu.append(export_item)
        self._menu_items["export"] = export_item

        self._menu_item(menu, "Print", self._print_display, key="print")
        menu.append(Gtk.SeparatorMenuItem())
        self._menu_item(menu, "Reset All", self.controller.reset_all)
        menu.append(Gtk.SeparatorMenuItem())
        self._menu_item(
            menu, "Quit", self.destroy,
            accelerator=(Gdk.KEY_q, Gdk.ModifierType.CONTROL_MASK),
        )
        return item

    def _edit_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("Edit")
        self._menu_item(
            menu, "Undo", self._undo,
            accelerator=(Gdk.KEY_z, Gdk.ModifierType.CONTROL_MASK),
        )
        self._menu_item(
            menu, "Redo", self._redo,
            accelerator=(
                Gdk.KEY_z, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK,
            ),
        )
        menu.append(Gtk.SeparatorMenuItem())
        self._menu_item(menu, "Clear Selection", self._clear_selection)
        return item

    def _display_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("Display")
        self._section_label(menu, "Representation")
        for representation in MoleculeRepresentation:
            self._menu_item(
                menu,
                representation.title,
                lambda value=representation: self.controller.set_representation(value),
                key=f"repr:{representation.name}",
            )
        self._section_label(menu, "Visibility")
        for feature in MoleculeVisibilityFeature:
            self._menu_item(
                menu,
                f"Hide {feature.title}",
                lambda value=feature: self.controller.toggle_visibility(value),
                key=f"vis:{feature.name}",
            )

        background_item = Gtk.MenuItem(label="Background")
        background_menu = Gtk.Menu()
        background_item.set_submenu(background_menu)
        for preset in BACKGROUND_PRESETS:
            entry = Gtk.MenuItem(label=preset.title)
            entry.connect(
                "activate", lambda _item, value=preset: self.controller.set_background(value)
            )
            background_menu.append(entry)
        menu.append(background_item)
        return item

    def _calculation_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("Calculation")
        self._menu_item(
            menu, "Surface Potential", self.controller.surface_potential, key="surfpot"
        )
        self._menu_item(
            menu, "Secondary Structure", self.controller.secondary_structure, key="secstr"
        )
        self._menu_item(menu, "Superpose Visible", self.controller.superpose, key="superpose")
        self._section_label(menu, "Morph")
        self._menu_item(menu, "Start Morph", self.controller.morph_toggle, key="morph")
        return item

    def _measure_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("Measure")
        for kind in MeasureKind:
            self._menu_item(
                menu,
                f"{kind.title} Mode",
                lambda value=kind: self.controller.toggle_measure(value),
                key=f"measure:{kind.name}",
            )
        self._menu_item(menu, "Clear Measurements", self.controller.clear_measurements)
        return item

    def _help_menu(self) -> Gtk.MenuItem:
        item, menu = self._submenu("Help")
        self._menu_item(
            menu, "Manual", lambda: show_manual(self),
            accelerator=(Gdk.KEY_F1, Gdk.ModifierType(0)),
        )
        self._menu_item(
            menu,
            "Quick Help",
            lambda: self.controller.update_status("Open a PDB/mmCIF file or enter a PDB ID"),
        )
        return item

    # MARK: - Left rail

    def _build_left_rail(self) -> Gtk.Widget:
        rail = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        rail.set_halign(Gtk.Align.START)
        rail.set_valign(Gtk.Align.FILL)
        rail.set_margin_start(16)
        rail.set_margin_top(60)
        rail.set_margin_bottom(96)

        self._info_card = self._build_info_card()
        # Visibility is driven from _sync alone; without this a later show_all() on the window
        # would resurrect a card the user closed.
        self._info_card.set_no_show_all(True)
        rail.pack_start(self._info_card, False, False, 0)

        self._objects_panel, self._objects_body = self._build_objects_panel()
        # The panel sits at the bottom of the rail, as it does on iOS and in the Flutter shell.
        rail.pack_end(self._objects_panel, False, False, 0)
        return rail

    def _build_info_card(self) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.get_style_context().add_class("panel")
        card.set_size_request(320, -1)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        title = Gtk.Label(label="Molecule Viewer", xalign=0)
        title.get_style_context().add_class("card-title")
        header.pack_start(title, True, True, 0)
        close = _icon_button("window-close-symbolic", "Close structure loading")
        close.connect("clicked", lambda _button: self._set_info_card_visible(False))
        header.pack_end(close, False, False, 0)
        card.add(header)

        self._status_label = Gtk.Label(label=self.controller.status_message, xalign=0)
        self._status_label.get_style_context().add_class("status")
        self._status_label.set_line_wrap(True)
        self._status_label.set_max_width_chars(38)
        card.add(self._status_label)

        open_button = Gtk.Button(label="Open Structure")
        open_button.set_image(Gtk.Image.new_from_icon_name("document-open-symbolic", Gtk.IconSize.BUTTON))
        open_button.set_always_show_image(True)
        open_button.connect("clicked", lambda _button: self._open_structure())
        card.add(open_button)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._pdb_entry = Gtk.Entry()
        self._pdb_entry.set_placeholder_text("PDB ID")
        self._pdb_entry.set_max_length(4)
        self._pdb_entry.set_width_chars(6)
        self._pdb_entry.connect("changed", self._on_pdb_changed)
        self._pdb_entry.connect("activate", lambda _entry: self.controller.load_pdb())
        row.pack_start(self._pdb_entry, False, False, 0)

        self._load_pdb_button = Gtk.Button(label="Load PDB")
        self._load_pdb_button.connect("clicked", lambda _button: self.controller.load_pdb())
        row.pack_start(self._load_pdb_button, False, False, 0)
        card.add(row)

        self._error_label = Gtk.Label(label="", xalign=0)
        self._error_label.get_style_context().add_class("error")
        self._error_label.set_line_wrap(True)
        self._error_label.set_max_width_chars(38)
        self._error_label.set_no_show_all(True)
        card.add(self._error_label)
        return card

    def _build_objects_panel(self) -> tuple[Gtk.Widget, Gtk.Box]:
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        panel.get_style_context().add_class("panel")
        panel.set_size_request(220, -1)

        header = Gtk.Button()
        header.get_style_context().add_class("flat-icon")
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Objects", xalign=0)
        title.get_style_context().add_class("section-title")
        header_box.pack_start(title, True, True, 0)
        self._objects_chevron = Gtk.Image.new_from_icon_name("pan-up-symbolic", Gtk.IconSize.MENU)
        header_box.pack_end(self._objects_chevron, False, False, 0)
        header.add(header_box)
        header.connect("clicked", lambda _button: self._toggle_objects_panel())
        panel.add(header)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        # The panel is an overlay on the viewport; a long ligand list must scroll inside it rather
        # than push the command bar off screen.
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_max_content_height(260)
        scroller.set_propagate_natural_height(True)
        scroller.add(body)
        scroller.set_no_show_all(True)
        panel.add(scroller)
        self._objects_scroller = scroller
        return panel, body

    def _build_command_bar(self) -> Gtk.Widget:
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bar.get_style_context().add_class("command-bar")
        bar.set_halign(Gtk.Align.CENTER)
        bar.set_valign(Gtk.Align.END)
        bar.set_margin_bottom(24)
        bar.set_size_request(600, -1)

        icon = Gtk.Image.new_from_icon_name("utilities-terminal-symbolic", Gtk.IconSize.MENU)
        bar.pack_start(icon, False, False, 0)

        self._command_entry = Gtk.Entry()
        self._command_entry.set_placeholder_text("Enter command (e.g. load 1crn, repr surface)...")
        self._command_entry.set_has_frame(False)
        self._command_entry.connect(
            "changed", lambda entry: self.controller.set_command_text(entry.get_text())
        )
        self._command_entry.connect("activate", lambda _entry: self.controller.execute_command())
        bar.pack_start(self._command_entry, True, True, 0)

        self._clear_command = _icon_button("edit-clear-symbolic", "Clear")
        self._clear_command.set_no_show_all(True)
        self._clear_command.connect("clicked", lambda _button: self.controller.set_command_text(""))
        bar.pack_start(self._clear_command, False, False, 0)

        self._run_command = _icon_button("go-up-symbolic", "Run command")
        self._run_command.connect("clicked", lambda _button: self.controller.execute_command())
        bar.pack_start(self._run_command, False, False, 0)
        return bar

    # MARK: - Overlay positioning

    def _position_child(self, _overlay, child, allocation) -> bool:
        """Only the hover tooltip is positional; every other overlay child uses its own alignment."""
        if child is not self._tooltip or self.bridge.hover_point is None:
            return False
        x, y = self.bridge.hover_point
        width, height = child.get_preferred_size()[1].width, child.get_preferred_size()[1].height
        allocation.x = int(x)
        allocation.y = int(max(16, y - 28))
        allocation.width = width
        allocation.height = height
        return True

    # MARK: - Actions

    def _undo(self) -> None:
        self.controller.clear_error()
        self.bridge.undo()

    def _redo(self) -> None:
        self.controller.clear_error()
        self.bridge.redo()

    def _clear_selection(self) -> None:
        self.controller.clear_error()
        self.bridge.clear_selection()

    def _set_info_card_visible(self, is_visible: bool) -> None:
        self._is_info_card_visible = is_visible
        self._sync()

    def _toggle_objects_panel(self) -> None:
        self._is_objects_panel_expanded = not self._is_objects_panel_expanded
        self._sync()

    def _on_pdb_changed(self, entry: Gtk.Entry) -> None:
        # PDB IDs are 4 alphanumerics, uppercase — the same filter the other shells apply as you type.
        filtered = "".join(character for character in entry.get_text() if character.isalnum()).upper()
        if filtered != entry.get_text():
            entry.set_text(filtered)
            return
        self.controller.set_pdb_text(filtered)

    def _open_structure(self) -> None:
        self._set_info_card_visible(True)
        path = self._ask_open_path("Open Structure", STRUCTURE_EXTENSIONS, "Structures")
        if path:
            self.controller.load_structure_file(path)

    def _open_state(self) -> None:
        path = self._ask_open_path("Open State", STATE_EXTENSIONS, "MolApp state")
        if path:
            self.controller.load_state_file(path)

    def _save_state(self) -> None:
        self.controller.save_state(self._ask_save_path)

    def _export_image(self, export_format: ExportFormat) -> None:
        self.controller.export_image(export_format, self._ask_save_path)

    def _print_display(self) -> None:
        self.controller.print_display(self._print_png)

    def _ask_open_path(self, title: str, extensions: list[str], label: str) -> str | None:
        dialog = Gtk.FileChooserDialog(
            title=title, transient_for=self, action=Gtk.FileChooserAction.OPEN
        )
        dialog.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.ACCEPT
        )
        file_filter = Gtk.FileFilter()
        file_filter.set_name(f"{label} ({', '.join('*.' + e for e in extensions)})")
        for extension in extensions:
            file_filter.add_pattern(f"*.{extension}")
        dialog.add_filter(file_filter)
        all_files = Gtk.FileFilter()
        all_files.set_name("All files")
        all_files.add_pattern("*")
        dialog.add_filter(all_files)

        path = dialog.get_filename() if dialog.run() == Gtk.ResponseType.ACCEPT else None
        dialog.destroy()
        return path

    def _ask_save_path(self, suggested_name: str) -> str | None:
        dialog = Gtk.FileChooserDialog(
            title="Save", transient_for=self, action=Gtk.FileChooserAction.SAVE
        )
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.ACCEPT)
        dialog.set_current_name(suggested_name)
        dialog.set_do_overwrite_confirmation(True)
        path = dialog.get_filename() if dialog.run() == Gtk.ResponseType.ACCEPT else None
        dialog.destroy()
        return path

    def _print_png(self, png: bytes) -> None:
        """Sends the captured viewport to the GTK print dialog, scaled to fit the page."""
        loader = GdkPixbuf.PixbufLoader.new_with_type("png")
        loader.write(png)
        loader.close()
        pixbuf = loader.get_pixbuf()

        operation = Gtk.PrintOperation()
        operation.set_n_pages(1)
        operation.set_job_name("MolApp")

        def on_draw(_operation, context, _page) -> None:
            cairo_context = context.get_cairo_context()
            scale = min(
                context.get_width() / pixbuf.get_width(),
                context.get_height() / pixbuf.get_height(),
            )
            cairo_context.translate(
                (context.get_width() - pixbuf.get_width() * scale) / 2,
                (context.get_height() - pixbuf.get_height() * scale) / 2,
            )
            cairo_context.scale(scale, scale)
            Gdk.cairo_set_source_pixbuf(cairo_context, pixbuf, 0, 0)
            cairo_context.paint()

        operation.connect("draw-page", on_draw)
        operation.run(Gtk.PrintOperationAction.PRINT_DIALOG, self)

    # MARK: - State → widgets

    def _sync(self) -> None:
        controller = self.controller
        has_objects = bool(self.bridge.objects)
        visible = controller.visible_structure_names

        self._status_label.set_text(controller.status_message)
        error = controller.error_message
        self._error_label.set_text(error or "")
        self._error_label.set_visible(bool(error))

        if self._pdb_entry.get_text() != controller.pdb_text:
            self._pdb_entry.set_text(controller.pdb_text)
        self._load_pdb_button.set_sensitive(bool(controller.pdb_text.strip()))

        if self._command_entry.get_text() != controller.command_text:
            self._command_entry.set_text(controller.command_text)
        has_command = bool(controller.command_text.strip())
        self._clear_command.set_visible(has_command)
        self._run_command.set_sensitive(has_command)

        self._menu_items["saveState"].set_sensitive(has_objects)
        self._menu_items["export"].set_sensitive(has_objects)
        self._menu_items["print"].set_sensitive(has_objects)
        for representation in MoleculeRepresentation:
            self._menu_items[f"repr:{representation.name}"].set_sensitive(bool(visible))
        for feature in MoleculeVisibilityFeature:
            is_visible = controller.visibility_states.get(feature, True)
            self._menu_items[f"vis:{feature.name}"].set_label(
                f"{'Hide' if is_visible else 'Show'} {feature.title}"
            )
        self._menu_items["surfpot"].set_sensitive(bool(visible))
        self._menu_items["secstr"].set_sensitive(bool(visible))
        self._menu_items["superpose"].set_sensitive(len(visible) >= 2)
        self._menu_items["morph"].set_label("Stop Morph" if controller.is_morphing else "Start Morph")
        self._menu_items["morph"].set_sensitive(controller.is_morphing or bool(visible))

        # The card opts out of the window's show_all so that closing it sticks, which also makes
        # show_all() on the card itself a no-op — its children have to be shown one level down.
        _show_or_hide(self._info_card, self._is_info_card_visible)

        self._sync_banner()
        self._sync_tooltip()
        self._sync_objects()

    def _sync_banner(self) -> None:
        kind = self.controller.measure_kind
        if kind is None:
            self._banner.set_visible(False)
            return
        # Name the atoms already armed rather than only counting down: a leftover pick is otherwise
        # invisible state, and reads as the app remembering something the user left behind.
        picked = self.bridge.measure_pending_labels
        remaining = kind.atom_count - self.bridge.measure_pending_count
        if picked:
            text = f"{kind.title} mode — {', '.join(picked)} (pick {remaining} more)"
        else:
            text = f"{kind.title} mode — pick {kind.atom_count} atoms"
        self._banner.set_text(text)
        self._banner.set_visible(True)

    def _sync_tooltip(self) -> None:
        label = self.bridge.hover_label
        if label is None or self.bridge.hover_point is None:
            self._tooltip.set_visible(False)
            return
        self._tooltip.set_text(label)
        self._tooltip.set_visible(True)
        self.overlay.queue_resize()

    def _sync_objects(self) -> None:
        objects = list(self.bridge.objects)
        self._objects_chevron.set_from_icon_name(
            "pan-up-symbolic" if self._is_objects_panel_expanded else "pan-down-symbolic",
            Gtk.IconSize.MENU,
        )
        _show_or_hide(self._objects_scroller, self._is_objects_panel_expanded)
        if objects == self._objects_snapshot:
            return
        self._objects_snapshot = objects

        for child in self._objects_body.get_children():
            self._objects_body.remove(child)

        if not objects:
            empty = Gtk.Label(label="No objects", xalign=0)
            empty.get_style_context().add_class("empty")
            self._objects_body.add(empty)
        else:
            for obj in objects:
                self._objects_body.add(self._object_row(obj))
        self._objects_body.show_all()

    def _object_row(self, obj: MolAppObject) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        eye = _icon_button(_EYE_ICONS[obj.is_visible], "Toggle visibility")
        eye.set_sensitive(True)
        eye.get_style_context().add_class("flat-icon")
        if not obj.is_visible:
            eye.set_opacity(0.45)
        eye.connect(
            "clicked",
            lambda _button, name=obj.name, visible=obj.is_visible: self.bridge.set_object_visibility(
                name, not visible
            ),
        )
        header.pack_start(eye, False, False, 0)

        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        name = Gtk.Label(label=obj.name, xalign=0)
        name.get_style_context().add_class("object-name")
        name.set_ellipsize(Pango.EllipsizeMode.END)
        labels.add(name)
        type_label = Gtk.Label(label=obj.type.value, xalign=0)
        type_label.get_style_context().add_class("object-type")
        labels.add(type_label)
        header.pack_start(labels, True, True, 0)

        header.pack_end(self._color_swatch(obj), False, False, 0)
        row.add(header)

        chips = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for representation in ObjectRepresentation:
            chip = Gtk.Button(label=representation.short_title)
            chip.get_style_context().add_class("chip")
            if obj.representation is representation:
                chip.get_style_context().add_class("chip-selected")
            chip.connect(
                "clicked",
                lambda _button, name=obj.name, value=representation: (
                    self.bridge.set_object_representation(name, value)
                ),
            )
            chips.add(chip)
        row.add(chips)
        return row

    def _color_swatch(self, obj: MolAppObject) -> Gtk.Widget:
        button = Gtk.Button()
        button.get_style_context().add_class("flat-icon")
        button.set_tooltip_text("Color")
        button.add(_color_dot(obj.color_hex, 14))

        popover = Gtk.Popover.new(button)
        grid = Gtk.Grid(row_spacing=8, column_spacing=8)
        grid.set_margin_start(12)
        grid.set_margin_end(12)
        grid.set_margin_top(12)
        grid.set_margin_bottom(12)
        heading = Gtk.Label(label="Color", xalign=0)
        heading.get_style_context().add_class("section-title")
        grid.attach(heading, 0, 0, 5, 1)
        for index, key in enumerate(COLOR_PICKER_KEYS):
            color_hex = None if key == "default" else NAMED_COLORS[key]
            dot = Gtk.Button()
            dot.get_style_context().add_class("flat-icon")
            dot.set_tooltip_text(key)
            dot.add(_color_dot(color_hex, 26))
            dot.connect(
                "clicked",
                lambda _button, name=obj.name, value=color_hex: (
                    self.bridge.set_object_color(name, value),
                    popover.popdown(),
                ),
            )
            grid.attach(dot, index % 5, 1 + index // 5, 1, 1)
        grid.show_all()
        popover.add(grid)
        button.connect("clicked", lambda _button: popover.popup())
        return button


def _show_or_hide(container: Gtk.Container, is_visible: bool) -> None:
    """Shows or hides a container that has opted out of `show_all` (`set_no_show_all`), which also
    makes `show_all()` on the container itself a no-op — so its children are shown one level down.
    Children with their own `no_show_all` (the error label) keep governing themselves."""
    if not is_visible:
        container.hide()
        return
    for child in container.get_children():
        child.show_all()
    container.show()


def _icon_button(icon_name: str, tooltip: str) -> Gtk.Button:
    button = Gtk.Button()
    button.set_image(Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU))
    button.set_tooltip_text(tooltip)
    button.get_style_context().add_class("flat-icon")
    button.set_relief(Gtk.ReliefStyle.NONE)
    return button


def _color_dot(color_hex: str | None, size: int) -> Gtk.Widget:
    """A circular swatch. No colour means Mol* is colouring by chain, which the panel shows as a
    neutral dot rather than pretending it is white."""
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)
    rgb = rgb_from_hex(color_hex)

    def on_draw(_widget, context) -> None:
        radius = size / 2
        if rgb is None:
            context.set_source_rgba(1, 1, 1, 0.3)
        else:
            context.set_source_rgb(*rgb)
        context.arc(radius, radius, radius - 0.5, 0, 2 * 3.141592653589793)
        context.fill_preserve()
        context.set_source_rgba(1, 1, 1, 0.35)
        context.set_line_width(1)
        context.stroke()

    area.connect("draw", on_draw)
    return area


def _install_css() -> None:
    provider = Gtk.CssProvider()
    provider.load_from_data(_CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )


class MolAppApplication(Gtk.Application):
    def __init__(self) -> None:
        from . import APP_ID

        super().__init__(application_id=APP_ID)
        self._window: MolAppWindow | None = None

    def do_activate(self) -> None:
        if self._window is None:
            self._window = MolAppWindow(self)
        self._window.show_all()
        self._window.present()


__all__ = ["APP_VERSION", "MolAppApplication", "MolAppWindow"]
