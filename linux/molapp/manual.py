"""Help ▸ Manual. Same sections, same wording as `manual_page.dart` / `ManualView.swift`."""

from __future__ import annotations

from typing import NamedTuple

import gi

gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from . import APP_VERSION  # noqa: E402


class ManualCommand(NamedTuple):
    syntax: str
    detail: str


class ManualSection(NamedTuple):
    title: str
    body: str
    commands: tuple[ManualCommand, ...] = ()


INTRO = (
    "MolApp is a molecular structure viewer built on Mol*. Use the menu bar, the Objects panel, "
    "or the command line at the bottom of the window."
)

SECTIONS: tuple[ManualSection, ...] = (
    ManualSection(
        title="Loading structures",
        body=(
            "Open a local PDB/mmCIF file with File ▸ Open Structure, or fetch from the RCSB by "
            "entering a 4-character PDB ID and pressing Load PDB. Multiple structures can be "
            "loaded at once — each appears in the Objects panel."
        ),
        commands=(ManualCommand("load 1UBQ", "Fetch and display a PDB entry by ID"),),
    ),
    ManualSection(
        title="Saving & exporting",
        body=(
            "File ▸ Save State writes the whole session — every structure, selection, color, "
            "representation and visibility — to a .molapp file; File ▸ Open State restores it. "
            "Structures loaded from the RCSB are re-fetched on open, so restoring those needs a "
            "network connection. File ▸ Export Display saves a snapshot of the current view as "
            "PNG, JPEG, GIF, SVG or PDF, and File ▸ Print sends it to a printer. File ▸ Reset All "
            "clears everything back to an empty viewer."
        ),
    ),
    ManualSection(
        title="Undo & redo",
        body=(
            "Edit ▸ Undo and Edit ▸ Redo step backward and forward through changes — loading, "
            "hiding, recoloring, representation switches and state loads are all reversible (up to "
            "25 steps). Edit ▸ Clear Selection drops the active selection without removing its "
            "named object."
        ),
    ),
    ManualSection(
        title="Objects panel",
        body=(
            "Every loaded structure and named selection is listed at the bottom-left. The eye "
            "toggles a structure's visibility. The colored dot opens a color picker. The Rib / Sur "
            "/ Stk / B+S / Sph buttons switch that object's representation. Display ▸ Visibility "
            "toggles protein, water and ligand across the whole scene. Calculation and Display "
            "actions apply only to the structures currently shown (eye on)."
        ),
        commands=(
            ManualCommand(
                "show NAME / hide NAME", "Show or hide an object (or protein / water / ligand)"
            ),
            ManualCommand("repr surface NAME", "Set an object's representation"),
            ManualCommand("color red NAME", "Recolor an object (or 'default')"),
        ),
    ),
    ManualSection(
        title="Background",
        body=(
            "Display ▸ Background sets the viewport background color — Dark, Black, Gray, Light or "
            "White. A light background is handy for presentation slides or printing."
        ),
        commands=(
            ManualCommand(
                "background white",
                "Set the viewport background (dark / black / gray / light / white, or #RRGGBB)",
            ),
        ),
    ),
    ManualSection(
        title="Selections",
        body=(
            "Build a named selection from an expression. Combine terms with & (and), | (or), ! "
            "(not) and parentheses. Click an atom in the viewport to select it; double-click to "
            "focus."
        ),
        commands=(
            ManualCommand("select sele chain A & resn ALA", "Name a selection from an expression"),
            ManualCommand(
                "res 10-25 · residue 42 · atom CA", "Residue range, single residue, atom name"
            ),
            ManualCommand("clear · focus", "Clear the selection · frame it in view"),
        ),
    ),
    ManualSection(
        title="Calculation",
        body=(
            "Analyses run on the visible structures. Surface Potential draws a molecular surface "
            "colored by a screened-Coulomb (APBS-like) electrostatic potential. Secondary "
            "Structure assigns helix / sheet / coil (DSSP when the model has none) and colors a "
            "cartoon. Superpose aligns visible structures onto the first by sequence alignment "
            "plus iterative Cα fitting — sequences need not match. Morph animates through the "
            "models of a multi-model structure (NMR ensemble / trajectory)."
        ),
        commands=(
            ManualCommand("surfpot", "Electrostatic potential surface"),
            ManualCommand("ss", "Secondary structure (DSSP) coloring"),
            ManualCommand("super", "Superpose the visible structures"),
            ManualCommand("morph · morph stop", "Start / stop trajectory morph"),
        ),
    ),
    ManualSection(
        title="Measure",
        body=(
            "Pick a mode under Measure ▸ Distance / Angle / Dihedral, then click 2 / 3 / 4 atoms to "
            "draw the measurement — distance in ångströms, angle and dihedral in degrees. Keep "
            "picking sets to add more. A blue banner shows while measuring; Clear Measurements "
            "removes them all."
        ),
        commands=(
            ManualCommand(
                "measure · measure angle · measure dihedral",
                "Enter distance / angle / dihedral mode",
            ),
            ManualCommand(
                "measure off · measure clear", "Leave measure mode · remove all measurements"
            ),
        ),
    ),
)


def show_manual(parent: Gtk.Window) -> None:
    dialog = Gtk.Dialog(title="Manual", transient_for=parent, modal=True)
    dialog.set_default_size(620, 680)
    dialog.add_button("Done", Gtk.ResponseType.CLOSE)

    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    content.set_margin_start(20)
    content.set_margin_end(20)
    content.set_margin_top(16)
    content.set_margin_bottom(16)
    content.add(_paragraph(INTRO, dim=True))

    for section in SECTIONS:
        title = Gtk.Label(label=section.title, xalign=0)
        title.get_style_context().add_class("manual-title")
        content.add(title)
        content.add(_paragraph(section.body, dim=True))
        if section.commands:
            commands = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            commands.get_style_context().add_class("manual-commands")
            for command in section.commands:
                syntax = Gtk.Label(label=command.syntax, xalign=0)
                syntax.get_style_context().add_class("manual-syntax")
                commands.add(syntax)
                commands.add(_paragraph(command.detail, dim=True, small=True))
            content.add(commands)

    version = Gtk.Label(label=f"MolApp version {APP_VERSION}")
    version.get_style_context().add_class("manual-version")
    content.add(version)

    scroller = Gtk.ScrolledWindow()
    scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroller.add(content)
    box = dialog.get_content_area()
    box.pack_start(scroller, True, True, 0)

    dialog.show_all()
    dialog.run()
    dialog.destroy()


def _paragraph(text: str, dim: bool = False, small: bool = False) -> Gtk.Label:
    label = Gtk.Label(label=text, xalign=0)
    label.set_line_wrap(True)
    label.set_max_width_chars(72)
    if dim:
        label.get_style_context().add_class("dim-label")
    if small:
        label.get_style_context().add_class("manual-detail")
    return label
