"""UI-facing state and actions: the status line, the transient measure/morph modes, the PDB-id and
command-bar text, and the command parser.

A port of `viewer_controller.dart` / the Kotlin `ViewerController`. Menus and the command bar share
these methods so both behave identically. File dialogs and printing are passed in as callables
rather than called directly, which keeps this module free of GTK and testable without a display.
"""

from __future__ import annotations

import os
import re
from typing import Callable

from .bridge import MolStarBridge, MolStarCommand, MolStarCommandResult
from .export import bytes_from_data_url, encode_export
from .models import (
    BACKGROUND_PRESETS,
    BackgroundPreset,
    COLOR_PICKER_KEYS,
    ExportFormat,
    HEX_PATTERN,
    MeasureKind,
    MoleculeRepresentation,
    MoleculeSelection,
    MoleculeVisibilityFeature,
    NAMED_COLORS,
    ObjectRepresentation,
    PdbIdentifierError,
    StructureFileError,
    format_for,
    normalized_pdb_id,
    pdb_display_name,
    read_capped,
)
from .selection import SelectionExpressionParser, SelectionParseError

IDLE_STATUS = "Ready for structure loading"

COLOR_USAGE = (
    "Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]"
)

#: Asks the user for a destination path, given a suggested file name. Returns None if cancelled.
AskSavePath = Callable[[str], "str | None"]


class ViewerController:
    def __init__(self, bridge: MolStarBridge) -> None:
        self.bridge = bridge
        bridge.add_listener(self._on_bridge_changed)

        self.pdb_text = ""
        self.command_text = ""
        self.status_message = IDLE_STATUS
        self.local_error_message: str | None = None
        self.measure_kind: MeasureKind | None = None
        self.is_morphing = False
        self.selected_representation = MoleculeRepresentation.ribbon
        self.visibility_states: dict[MoleculeVisibilityFeature, bool] = {
            feature: True for feature in MoleculeVisibilityFeature
        }

        self._listeners: list[Callable[[], None]] = []
        self._seen_command_result: MolStarCommandResult | None = None
        self._seen_measurement_seq = 0

    # MARK: - Observation

    def add_listener(self, listener: Callable[[], None]) -> None:
        self._listeners.append(listener)

    def _notify(self) -> None:
        for listener in list(self._listeners):
            listener()

    @property
    def error_message(self) -> str | None:
        return self.local_error_message or self.bridge.last_error_message

    @property
    def visible_structure_names(self) -> list[str]:
        return self.bridge.visible_structure_names

    def update_status(self, message: str) -> None:
        self.status_message = message
        self._notify()

    def update_error(self, message: str | None) -> None:
        self.local_error_message = message
        self._notify()

    def clear_error(self) -> None:
        self._begin_action()
        self._notify()

    def _begin_action(self) -> None:
        """Every action starts from a clean error state on both sides; callers notify once they
        have finished mutating their own fields."""
        self.local_error_message = None
        self.bridge.clear_error()

    def _fail_action(self, message: str) -> None:
        """An action that could not start or finish: drop the optimistic status and report why."""
        self.status_message = IDLE_STATUS
        self.update_error(message)

    def set_pdb_text(self, value: str) -> None:
        self.pdb_text = value
        self._notify()

    def set_command_text(self, value: str) -> None:
        self.command_text = value
        self._notify()

    # MARK: - Bridge reactions

    def _on_bridge_changed(self) -> None:
        changed = False

        # Key off the counter, not the label: measuring the same pair again, or two pairs that
        # happen to render the same text, are still separate measurements to report.
        if self.bridge.measurement_seq != self._seen_measurement_seq:
            self._seen_measurement_seq = self.bridge.measurement_seq
            measurement = self.bridge.last_measurement
            if measurement is not None:
                kind = self.measure_kind.title if self.measure_kind else "Distance"
                self.status_message = f"{kind}: {measurement}"
                changed = True

        result = self.bridge.last_command_result
        if result is not None and result is not self._seen_command_result:
            self._seen_command_result = result
            changed = self._apply_command_result(result) or changed

        rebuilt = {feature: True for feature in MoleculeVisibilityFeature}
        for raw, is_visible in self.bridge.feature_visibility.items():
            feature = MoleculeVisibilityFeature.from_raw(raw)
            if feature is not None:
                rebuilt[feature] = is_visible
        if rebuilt != self.visibility_states:
            self.visibility_states = rebuilt
            changed = True

        # The bridge's own state (objects, selection, errors) changed too; the UI listens to both,
        # so only notify when this controller's state moved.
        if changed:
            self._notify()

    def _apply_command_result(self, result: MolStarCommandResult) -> bool:
        if not result.success:
            changed = False
            # In-flight status is set optimistically and only advanced on success, so a rejected
            # command would otherwise claim "Loading …" forever next to the error banner.
            if self.status_message.endswith("…") or self.status_message.startswith("Loading"):
                self.status_message = IDLE_STATUS
                changed = True
            # measure_kind is set optimistically in toggle_measure; if JS never entered measure
            # mode, clear it so the "pick N atoms" banner does not stick with clicks doing nothing.
            if result.command is MolStarCommand.setMeasureMode and self.measure_kind is not None:
                self.measure_kind = None
                changed = True
            return changed

        command = result.command
        if command is MolStarCommand.loadLocalStructure:
            self.status_message = f"Loaded {result.label or 'Structure'}"
        elif command is MolStarCommand.loadPdbId:
            self.status_message = f"Loaded {result.label or pdb_display_name(self.pdb_text)}"
        elif command is MolStarCommand.setRepresentation:
            self.status_message = f"{self.selected_representation.title} representation"
        elif command is MolStarCommand.surfacePotential:
            self.status_message = "Electrostatic potential (screened Coulomb)"
        elif command is MolStarCommand.startMorph:
            self.is_morphing = True
            self.status_message = "Morphing"
        elif command is MolStarCommand.stopMorph:
            self.is_morphing = False
            self.status_message = "Morph stopped"
        elif command is MolStarCommand.superpose:
            self.status_message = "Superposed visible structures"
        elif command is MolStarCommand.secondaryStructure:
            self.status_message = "Secondary structure (helix/sheet/coil)"
        elif command is MolStarCommand.resetAll:
            self.status_message = "Reset — everything cleared"
        elif command is MolStarCommand.undo:
            self.status_message = "Undid last change"
        elif command is MolStarCommand.redo:
            self.status_message = "Redid last change"
        elif command is MolStarCommand.loadState:
            self.status_message = "State loaded"
        elif command is MolStarCommand.transientModesStopped:
            # JS is the authority on these: it reports the moment it clears them, so a command that
            # clears and then fails cannot leave the UI claiming a mode the viewer dropped.
            self.measure_kind = None
            self.is_morphing = False
        else:
            return False
        return True

    # MARK: - Actions

    def load_pdb(self) -> None:
        try:
            pdb_id = normalized_pdb_id(self.pdb_text)
        except PdbIdentifierError as error:
            self.update_error(str(error))
            return
        self.pdb_text = pdb_id
        self.status_message = f"Loading {pdb_id}"
        self._begin_action()
        self.bridge.load_pdb_id(pdb_id)
        self._notify()

    def set_representation(self, representation: MoleculeRepresentation) -> None:
        self.selected_representation = representation
        self._begin_action()
        self.bridge.set_representation(representation.name, targets=self.visible_structure_names)
        self._notify()

    def toggle_visibility(self, feature: MoleculeVisibilityFeature) -> None:
        is_visible = not self.visibility_states.get(feature, True)
        self.visibility_states = {**self.visibility_states, feature: is_visible}
        self._begin_action()
        self.status_message = f"{feature.title} {'shown' if is_visible else 'hidden'}"
        self.bridge.toggle_visibility(feature=feature.name, is_visible=is_visible)
        self._notify()

    def toggle_measure(self, kind: MeasureKind) -> None:
        self._begin_action()
        if self.measure_kind is kind:
            self.measure_kind = None
            self.bridge.set_measure_mode(False)
            self.status_message = "Measure mode off"
        else:
            self.measure_kind = kind
            self.bridge.set_measure_mode(True, kind=kind.name)
            self.status_message = f"{kind.title}: pick {kind.atom_count} atoms"
        self._notify()

    def clear_measurements(self) -> None:
        self._begin_action()
        self.bridge.clear_measurements()
        self.update_status("Measurements cleared")

    def surface_potential(self) -> None:
        self._begin_action()
        self.status_message = "Computing surface potential…"
        self.bridge.draw_surface_potential(targets=self.visible_structure_names)
        self._notify()

    def secondary_structure(self) -> None:
        self._begin_action()
        self.status_message = "Assigning secondary structure…"
        self.bridge.compute_secondary_structure(targets=self.visible_structure_names)
        self._notify()

    def superpose(self) -> None:
        self._begin_action()
        if len(self.visible_structure_names) < 2:
            self.update_error("Show at least two structures to superpose.")
            return
        self.status_message = "Superposing structures…"
        self.bridge.superpose(targets=self.visible_structure_names)
        self._notify()

    def morph_toggle(self) -> None:
        self._begin_action()
        if self.is_morphing:
            self.bridge.stop_morph()
        else:
            self.status_message = "Morphing trajectory…"
            self.bridge.start_morph(loop=False, targets=self.visible_structure_names)
        self._notify()

    def set_background(self, preset: BackgroundPreset) -> None:
        self._begin_action()
        self.bridge.set_background_color(preset.hex)
        self.update_status(f"Background: {preset.title}")

    def reset_all(self) -> None:
        self._begin_action()
        self.bridge.reset_all()
        self.update_status("Resetting…")

    # MARK: - File actions

    def load_structure_file(self, path: str) -> None:
        """Loads a structure the caller already picked. The picker itself lives in the window."""
        label = os.path.basename(path)
        try:
            data_format = format_for(label)
            data = read_capped(path)
        except (StructureFileError, OSError) as error:
            self.update_error(str(error))
            return
        self.status_message = f"Loading {label}"
        self._begin_action()
        self.bridge.load_local_structure(data=data, format=data_format, label=label)
        self._notify()

    def load_state_file(self, path: str) -> None:
        try:
            # Saved state embeds the structure text, so it is the same size class as a raw file and
            # needs the same cap.
            json_text = read_capped(path)
        except (StructureFileError, OSError) as error:
            self.update_error(str(error))
            return
        self.status_message = "Loading state…"
        self._begin_action()
        self.bridge.load_state(json_text)
        self._notify()

    def save_state(self, ask_path: AskSavePath) -> None:
        self._begin_action()
        if not self.bridge.objects:
            self.update_error("Nothing to save yet.")
            return
        self.update_status("Capturing state…")

        def on_state(json_text: str | None) -> None:
            if not json_text:
                self._fail_action("Could not capture current state.")
                return
            self._deliver(json_text.encode("utf-8"), "molecule.molapp", ask_path)

        self.bridge.serialize_state(on_state)

    def export_image(self, format: ExportFormat, ask_path: AskSavePath) -> None:
        self._begin_action()
        if not self.bridge.objects:
            self.update_error("Nothing to export yet.")
            return
        self.update_status(f"Rendering {format.title}…")

        def on_png(png: bytes | None) -> None:
            if png is None:
                return
            try:
                data = encode_export(png, format)
            except Exception as error:  # encoder failure surfaces as a status-line error
                self._fail_action(str(error))
                return
            self._deliver(data, f"molecule.{format.file_extension}", ask_path)

        self._capture_png(on_png)

    def print_display(self, print_png: Callable[[bytes], None]) -> None:
        self._begin_action()
        if not self.bridge.objects:
            self.update_error("Nothing to print yet.")
            return
        self.update_status("Rendering for print…")

        def on_png(png: bytes | None) -> None:
            if png is None:
                return
            try:
                print_png(png)
            except Exception as error:
                self._fail_action(str(error))
                return
            self.update_status(IDLE_STATUS)

        self._capture_png(on_png)

    def _capture_png(self, on_png: Callable[[bytes | None], None]) -> None:
        def on_data_url(data_url: str | None) -> None:
            png = bytes_from_data_url(data_url) if data_url else None
            if png is None:
                self._fail_action("Could not capture the display.")
                on_png(None)
                return
            on_png(png)

        self.bridge.capture_image_data_url(on_data_url)

    def _deliver(self, data: bytes, suggested_name: str, ask_path: AskSavePath) -> None:
        path = ask_path(suggested_name)
        # A cancelled dialog announces nothing: claiming "Exported PNG" for a file that was never
        # written is worse than saying nothing.
        if not path:
            self.update_status(IDLE_STATUS)
            return
        try:
            with open(path, "wb") as handle:
                handle.write(data)
        except OSError as error:
            self._fail_action(str(error))
            return
        self.update_status(f"Saved {os.path.basename(path)}")

    # MARK: - Command bar

    def execute_command(self) -> None:
        """Direct port of the Swift `executeCommand` / Kotlin `ViewerController.executeCommand`."""
        text = self.command_text.strip()
        if not text:
            return

        self.command_text = ""
        self._begin_action()

        components = [token for token in re.split(r"\s+", text.lower()) if token]
        # Object names (PDB IDs, file labels) are stored case-sensitively (uppercase for PDB IDs),
        # so keep an original-case token list for name arguments — only keywords are lowercased.
        raw_components = [token for token in re.split(r"\s+", text) if token]
        if not components:
            return
        command = components[0]

        if command == "load":
            if len(components) >= 2:
                self.pdb_text = components[1].upper()
                self.load_pdb()
            else:
                self.update_error("Usage: load [PDB_ID]")

        elif command == "repr":
            if len(components) >= 3:
                object_name = " ".join(raw_components[2:])
                representation = ObjectRepresentation.from_raw_ignoring_case(components[1])
                if representation is not None:
                    self.bridge.set_object_representation(object_name, representation)
                else:
                    names = ", ".join(value.name for value in ObjectRepresentation)
                    self.update_error(f"Invalid representation. Use: {names}")
            elif len(components) >= 2:
                scene_representation = MoleculeRepresentation.from_raw(components[1])
                if scene_representation is not None:
                    self.set_representation(scene_representation)
                else:
                    names = ", ".join(value.name for value in MoleculeRepresentation)
                    self.update_error(f"Invalid representation. Use: {names}")
            else:
                self.update_error("Usage: repr [ribbon|surface|stick|ballAndStick|sphere] [name?]")

        elif command in ("show", "hide"):
            if len(components) >= 2:
                is_visible = command == "show"
                feature = MoleculeVisibilityFeature.from_raw(components[1])
                if feature is not None:
                    if self.visibility_states.get(feature, True) != is_visible:
                        self.toggle_visibility(feature)
                else:
                    self.bridge.set_object_visibility(
                        " ".join(raw_components[1:]), is_visible=is_visible
                    )
            else:
                self.update_error(f"Usage: {command} [water|ligand|objectname]")

        elif command == "select":
            after_select = "" if len(text) <= 6 else text[6:].strip()
            if not after_select:
                self.update_error(
                    "Usage: select [name] [expression] (e.g. select sele chain A & resn ala)"
                )
            else:
                selection_name, expression = SelectionExpressionParser.extract_name(after_select)
                try:
                    # Keep original case: the parser lowercases only keyword tokens, so chain IDs
                    # (which can be lowercase) survive.
                    ast = SelectionExpressionParser(expression).parse()
                except SelectionParseError as error:
                    self.update_error(str(error))
                else:
                    self.bridge.set_selection(
                        MoleculeSelection(
                            type="expression",
                            label=f"{selection_name}: {expression}",
                            ast=ast,
                        )
                    )

        elif command == "color":
            if len(components) >= 3:
                color_arg = components[1]
                object_name = " ".join(raw_components[2:])
                # Reject an unknown colour name instead of silently painting it white: a typo like
                # "gren" must report the usage, not recolour indistinguishably from "white". A raw
                # hex is validated for the same reason: hexToMolStarColor in viewer.html is a bare
                # parseInt, so "#12345" reaches Mol* as NaN and paints the object black, silently.
                if color_arg == "default":
                    color_hex = None
                elif HEX_PATTERN.match(color_arg):
                    color_hex = color_arg
                elif color_arg in NAMED_COLORS:
                    color_hex = NAMED_COLORS[color_arg]
                else:
                    self.update_error(COLOR_USAGE)
                    return
                self.bridge.set_object_color(object_name, color_hex)
            else:
                self.update_error(COLOR_USAGE)

        elif command in ("background", "bg"):
            arg = components[1] if len(components) >= 2 else ""
            hex_value: str | None = None
            if arg.startswith("#"):
                hex_value = arg.upper()
            else:
                for preset in BACKGROUND_PRESETS:
                    if preset.title.lower() == arg:
                        hex_value = preset.hex
                        break
            if hex_value is not None and HEX_PATTERN.match(hex_value):
                self.bridge.set_background_color(hex_value)
                self.update_status("Background set")
            else:
                self.update_error("Usage: background [dark|black|gray|light|white|#RRGGBB]")

        elif command == "clear":
            self.bridge.clear_selection()

        elif command == "focus":
            self.bridge.focus_selection()

        elif command in ("surfpot", "potential"):
            self.surface_potential()

        elif command in ("ss", "dssp", "secstr"):
            self.secondary_structure()

        elif command in ("super", "superpose", "align"):
            self.superpose()

        elif command == "morph":
            arg = components[1] if len(components) >= 2 else "start"
            if arg == "stop":
                self.bridge.stop_morph()
            else:
                self.status_message = "Morphing trajectory…"
                self.bridge.start_morph(
                    loop="loop" in components, targets=self.visible_structure_names
                )

        elif command in ("measure", "dist"):
            arg = components[1] if len(components) >= 2 else "distance"
            if arg == "clear":
                self.clear_measurements()
            elif arg == "off":
                if self.measure_kind is not None:
                    self.toggle_measure(self.measure_kind)
            elif arg == "angle":
                if self.measure_kind is not MeasureKind.angle:
                    self.toggle_measure(MeasureKind.angle)
            elif arg in ("dihedral", "torsion"):
                if self.measure_kind is not MeasureKind.dihedral:
                    self.toggle_measure(MeasureKind.dihedral)
            else:
                if self.measure_kind is not MeasureKind.distance:
                    self.toggle_measure(MeasureKind.distance)

        else:
            self.update_error(f"Unknown command: {command}")

        # The command bar mirrors command_text, which was cleared above — but several branches are
        # no-ops (re-arming the mode already armed, hiding what is already hidden) and notify
        # nothing, so without this the typed text stays on screen.
        self._notify()


__all__ = [
    "COLOR_PICKER_KEYS",
    "COLOR_USAGE",
    "IDLE_STATUS",
    "ViewerController",
]
