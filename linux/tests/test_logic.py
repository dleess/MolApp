"""Unit tests for everything that does not need a display: the wire protocol, the selection
parser, the command bar and the export encoders.

    cd linux && python3 -m unittest discover -s tests -v

The webview-backed end-to-end check is `test_smoke.py`.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from molapp.bridge import MolStarBridge, MolStarCommand  # noqa: E402
from molapp.controller import IDLE_STATUS, ViewerController  # noqa: E402
from molapp.export import bytes_from_data_url, encode_export  # noqa: E402
from molapp.models import (  # noqa: E402
    BACKGROUND_PRESETS,
    ExportFormat,
    MeasureKind,
    MolAppObject,
    MolAppObjectType,
    MoleculeRepresentation,
    MoleculeVisibilityFeature,
    NAMED_COLORS,
    ObjectRepresentation,
    PdbIdentifierError,
    StructureFileError,
    format_for,
    normalized_pdb_id,
    read_capped,
)
from molapp.selection import SelectionExpressionParser, SelectionParseError  # noqa: E402


class FakeRunner:
    """Stands in for the webview: records the scripts the bridge would have evaluated."""

    def __init__(self) -> None:
        self.scripts: list[str] = []
        self.async_sources: list[str] = []
        self.async_result: object | None = None
        self.async_error: str | None = None

    def evaluate(self, source: str) -> None:
        self.scripts.append(source)

    def call_async(self, source, on_done) -> None:
        self.async_sources.append(source)
        on_done(self.async_result, self.async_error)

    # Test helpers -----------------------------------------------------------------

    def commands(self) -> list[dict]:
        envelopes = []
        for script in self.scripts:
            start = script.find("(")
            end = script.rfind(")")
            if start < 0 or end < 0 or "handleNativeCommand" not in script:
                continue
            envelopes.append(json.loads(script[start + 1: end]))
        return envelopes

    def last_command(self) -> dict:
        return self.commands()[-1]


def ready_bridge() -> tuple[MolStarBridge, FakeRunner]:
    bridge = MolStarBridge()
    runner = FakeRunner()
    bridge.attach(runner)
    bridge.receive_message({"event": "viewerReady"})
    return bridge, runner


class WireFormatTests(unittest.TestCase):
    """Enum names are the protocol viewer.html reads; renaming a member renames the wire format."""

    def test_command_names(self) -> None:
        self.assertEqual(
            [command.name for command in MolStarCommand],
            [
                "loadLocalStructure",
                "loadPdbId",
                "setRepresentation",
                "toggleVisibility",
                "focusSelection",
                "setSelection",
                "clearSelection",
                "setObjectVisibility",
                "setObjectRepresentation",
                "setObjectColor",
                "setBackgroundColor",
                "surfacePotential",
                "startMorph",
                "stopMorph",
                "superpose",
                "secondaryStructure",
                "setMeasureMode",
                "clearMeasurements",
                "resetAll",
                "undo",
                "redo",
                "loadState",
                "transientModesStopped",
            ],
        )

    def test_representation_names(self) -> None:
        self.assertEqual(
            [value.name for value in ObjectRepresentation],
            ["ribbon", "surface", "stick", "ballAndStick", "sphere"],
        )
        self.assertEqual(
            [value.name for value in MoleculeRepresentation], ["ribbon", "surface", "stick"]
        )
        self.assertEqual(
            [value.name for value in MoleculeVisibilityFeature], ["protein", "water", "ligand"]
        )

    def test_palette_matches_the_other_shells(self) -> None:
        self.assertEqual(NAMED_COLORS["red"], "#D55E00")
        self.assertEqual(NAMED_COLORS["blue"], "#0072B2")
        self.assertEqual([preset.hex for preset in BACKGROUND_PRESETS][0], "#0B0F14")


class BridgeTests(unittest.TestCase):
    def test_commands_queue_until_the_viewer_is_ready(self) -> None:
        bridge = MolStarBridge()
        runner = FakeRunner()
        bridge.attach(runner)
        bridge.load_pdb_id("1CRN")
        self.assertEqual(runner.scripts, [])

        bridge.receive_message({"event": "viewerReady"})
        self.assertEqual(runner.last_command()["command"], "loadPdbId")
        self.assertEqual(runner.last_command()["payload"], {"pdbId": "1CRN"})

    def test_a_fatal_viewer_error_drops_the_queue(self) -> None:
        bridge = MolStarBridge()
        runner = FakeRunner()
        bridge.attach(runner)
        bridge.load_local_structure(data="ATOM", format="pdb", label="x.pdb")
        bridge.receive_message({"event": "viewerError", "message": "boom", "fatal": True})
        self.assertEqual(bridge.last_error_message, "boom")

        # Nothing may be queued afterwards either: loadLocalStructure embeds the whole file, and a
        # dead viewer will never drain it.
        bridge.load_pdb_id("1CRN")
        bridge.receive_message({"event": "viewerReady"})
        self.assertEqual(runner.scripts, [])

    def test_objects_replaced_rebuilds_the_panel(self) -> None:
        bridge, _ = ready_bridge()
        bridge.receive_message(
            {
                "event": "objectsReplaced",
                "objects": [
                    {
                        "name": "1CRN",
                        "type": "structure",
                        "isVisible": True,
                        "representation": "surface",
                        "colorHex": "#D55E00",
                    },
                    {"name": "sele", "type": "selection", "isVisible": False},
                ],
                "visibility": {"water": False},
            }
        )
        self.assertEqual(
            bridge.objects,
            [
                MolAppObject("1CRN", MolAppObjectType.structure, True, ObjectRepresentation.surface, "#D55E00"),
                MolAppObject("sele", MolAppObjectType.selection, False, ObjectRepresentation.ballAndStick),
            ],
        )
        self.assertEqual(bridge.visible_structure_names, ["1CRN"])
        self.assertEqual(bridge.feature_visibility, {"water": False})

    def test_a_hand_edited_state_file_cannot_crash_the_handler(self) -> None:
        bridge, _ = ready_bridge()
        bridge.receive_message(
            {
                "event": "objectsReplaced",
                "objects": [
                    {"name": "ok", "type": "structure", "representation": 7, "colorHex": 12},
                    {"name": "no type"},
                    "not an object",
                ],
            }
        )
        self.assertEqual(len(bridge.objects), 1)
        self.assertEqual(bridge.objects[0].representation, ObjectRepresentation.ribbon)
        self.assertIsNone(bridge.objects[0].color_hex)

    def test_added_objects_are_idempotent_by_name(self) -> None:
        bridge, _ = ready_bridge()
        for _ in range(2):
            bridge.receive_message(
                {"event": "objectsAdded", "objects": [{"name": "NAP", "representation": "sphere"}]}
            )
        self.assertEqual(len(bridge.objects), 1)
        self.assertEqual(bridge.objects[0].representation, ObjectRepresentation.sphere)

    def test_unknown_events_are_not_mistaken_for_command_results(self) -> None:
        bridge, _ = ready_bridge()
        bridge.receive_message({"event": "somethingThisShellDoesNotHandle"})
        self.assertIsNone(bridge.last_command_result)

    def test_measurement_events_bump_the_sequence(self) -> None:
        bridge, _ = ready_bridge()
        bridge.receive_message({"event": "measurement", "label": "A — B"})
        bridge.receive_message({"event": "measurement", "label": "A — B"})
        self.assertEqual(bridge.measurement_seq, 2)


class SelectionParserTests(unittest.TestCase):
    def parse(self, expression: str) -> dict:
        return SelectionExpressionParser(expression).parse().to_json()

    def test_chain_keeps_its_case_and_atom_is_upcased(self) -> None:
        self.assertEqual(self.parse("chain a"), {"kind": "chain", "value": "a"})
        self.assertEqual(self.parse("atom ca"), {"kind": "atom", "value": "CA"})
        self.assertEqual(self.parse("resn hoh"), {"kind": "residueName", "value": "HOH"})

    def test_residue_range_versus_negative_residue(self) -> None:
        self.assertEqual(self.parse("res 3-42"), {"kind": "residueRange", "value": "3-42"})
        self.assertEqual(self.parse("res -5"), {"kind": "residue", "value": "-5"})

    def test_precedence_and_grouping(self) -> None:
        self.assertEqual(
            self.parse("chain A & res 3 | resn ALA"),
            {
                "kind": "or",
                "left": [
                    {
                        "kind": "and",
                        "left": [{"kind": "chain", "value": "A"}],
                        "right": [{"kind": "residue", "value": "3"}],
                    }
                ],
                "right": [{"kind": "residueName", "value": "ALA"}],
            },
        )
        self.assertEqual(
            self.parse("!(chain A)"),
            {"kind": "not", "operand": [{"kind": "chain", "value": "A"}]},
        )

    def test_errors(self) -> None:
        for expression in ["chain", "(chain A", "chain A )", "bogus"]:
            with self.assertRaises(SelectionParseError):
                self.parse(expression)

    def test_extract_name(self) -> None:
        self.assertEqual(
            SelectionExpressionParser.extract_name("sele chain A"), ("sele", "chain A")
        )
        self.assertEqual(SelectionExpressionParser.extract_name("chain A"), ("sele", "chain A"))
        self.assertEqual(
            SelectionExpressionParser.extract_name("core res 1-9"), ("core", "res 1-9")
        )
        # A name cannot contain a tokenizer symbol; the tokenizer would have split it.
        self.assertEqual(
            SelectionExpressionParser.extract_name("a&b chain A"), ("sele", "a&b chain A")
        )


class CommandBarTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge, self.runner = ready_bridge()
        self.controller = ViewerController(self.bridge)

    def run_command(self, text: str) -> None:
        self.controller.set_command_text(text)
        self.controller.execute_command()

    def test_load_normalises_the_pdb_id(self) -> None:
        self.run_command("load 1crn")
        self.assertEqual(self.runner.last_command()["payload"], {"pdbId": "1CRN"})
        self.assertEqual(self.controller.status_message, "Loading 1CRN")

    def test_load_rejects_a_bad_id(self) -> None:
        self.run_command("load nope1")
        self.assertEqual(self.controller.error_message, "Enter a 4-character PDB ID.")

    def test_scene_and_per_object_representations(self) -> None:
        self.bridge.receive_message(
            {"event": "objectsReplaced", "objects": [{"name": "1CRN", "type": "structure"}]}
        )
        self.run_command("repr surface")
        self.assertEqual(
            self.runner.last_command()["payload"],
            {"representation": "surface", "targets": ["1CRN"]},
        )
        self.run_command("repr ballandstick 1CRN")
        self.assertEqual(
            self.runner.last_command()["payload"],
            {"name": "1CRN", "representation": "ballAndStick"},
        )

    def test_object_names_keep_their_case(self) -> None:
        self.run_command("hide My Ligand")
        self.assertEqual(
            self.runner.last_command()["payload"], {"name": "My Ligand", "isVisible": False}
        )

    def test_feature_toggles_go_through_the_feature_command(self) -> None:
        self.run_command("hide water")
        command = self.runner.last_command()
        self.assertEqual(command["command"], "toggleVisibility")
        self.assertEqual(command["payload"], {"feature": "water", "isVisible": False})
        # Hiding what is already hidden must not send a second, un-toggling command.
        before = len(self.runner.commands())
        self.run_command("hide water")
        self.assertEqual(len(self.runner.commands()), before)

    def test_color_rejects_an_unknown_name_and_a_short_hex(self) -> None:
        self.run_command("color gren 1CRN")
        self.assertIn("Usage: color", self.controller.error_message or "")
        self.run_command("color #12345 1CRN")
        self.assertIn("Usage: color", self.controller.error_message or "")

        self.run_command("color red 1CRN")
        self.assertEqual(
            self.runner.last_command()["payload"], {"name": "1CRN", "colorHex": "#D55E00"}
        )
        self.run_command("color default 1CRN")
        self.assertEqual(
            self.runner.last_command()["payload"], {"name": "1CRN", "colorHex": None}
        )

    def test_background_presets_and_hex(self) -> None:
        self.run_command("background white")
        self.assertEqual(self.runner.last_command()["payload"], {"colorHex": "#FFFFFF"})
        self.run_command("bg #123456")
        self.assertEqual(self.runner.last_command()["payload"], {"colorHex": "#123456"})
        self.run_command("bg puce")
        self.assertIn("Usage: background", self.controller.error_message or "")

    def test_select_builds_an_ast(self) -> None:
        self.run_command("select core chain A & res 3-42")
        payload = self.runner.last_command()["payload"]
        self.assertEqual(payload["type"], "expression")
        self.assertEqual(payload["label"], "core: chain A & res 3-42")
        self.assertEqual(payload["ast"]["kind"], "and")

    def test_select_reports_a_parse_error(self) -> None:
        self.run_command("select sele chain")
        self.assertEqual(self.controller.error_message, "Missing value for chain")

    def test_measure_modes(self) -> None:
        self.run_command("measure angle")
        self.assertEqual(self.controller.measure_kind, MeasureKind.angle)
        self.assertEqual(self.runner.last_command()["payload"], {"enabled": True, "kind": "angle"})
        self.run_command("measure off")
        self.assertIsNone(self.controller.measure_kind)
        self.assertEqual(self.runner.last_command()["payload"], {"enabled": False})

    def test_unknown_command(self) -> None:
        self.run_command("frobnicate")
        self.assertEqual(self.controller.error_message, "Unknown command: frobnicate")

    def test_the_command_bar_clears_even_for_no_op_branches(self) -> None:
        self.run_command("hide water")
        self.assertEqual(self.controller.command_text, "")
        self.run_command("hide water")
        self.assertEqual(self.controller.command_text, "")


class ControllerStateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge, self.runner = ready_bridge()
        self.controller = ViewerController(self.bridge)

    def test_a_failed_command_drops_the_optimistic_status(self) -> None:
        self.controller.surface_potential()
        self.assertTrue(self.controller.status_message.endswith("…"))
        self.bridge.receive_message(
            {"id": "1", "command": "surfacePotential", "success": False, "error": "nope"}
        )
        self.assertEqual(self.controller.status_message, IDLE_STATUS)
        self.assertEqual(self.controller.error_message, "nope")

    def test_a_failed_measure_mode_disarms_the_banner(self) -> None:
        self.controller.toggle_measure(MeasureKind.distance)
        self.bridge.receive_message(
            {"id": "1", "command": "setMeasureMode", "success": False, "error": "not ready"}
        )
        self.assertIsNone(self.controller.measure_kind)

    def test_transient_modes_stopped_clears_measure_and_morph(self) -> None:
        self.controller.toggle_measure(MeasureKind.angle)
        self.controller.is_morphing = True
        self.bridge.receive_message(
            {"id": "1", "command": "transientModesStopped", "success": True}
        )
        self.assertIsNone(self.controller.measure_kind)
        self.assertFalse(self.controller.is_morphing)

    def test_js_driven_visibility_reaches_the_menu_state(self) -> None:
        self.bridge.receive_message(
            {"event": "featureVisibility", "feature": "water", "isVisible": False}
        )
        self.assertFalse(self.controller.visibility_states[MoleculeVisibilityFeature.water])

    def test_superpose_needs_two_visible_structures(self) -> None:
        self.controller.superpose()
        self.assertEqual(
            self.controller.error_message, "Show at least two structures to superpose."
        )

    def test_actions_are_scoped_to_visible_structures(self) -> None:
        self.bridge.receive_message(
            {
                "event": "objectsReplaced",
                "objects": [
                    {"name": "1CRN", "type": "structure", "isVisible": True},
                    {"name": "1UBQ", "type": "structure", "isVisible": False},
                ],
            }
        )
        self.controller.surface_potential()
        self.assertEqual(self.runner.last_command()["payload"], {"targets": ["1CRN"]})

    def test_export_without_objects_reports_instead_of_capturing(self) -> None:
        self.controller.export_image(ExportFormat.png, lambda _name: "/dev/null")
        self.assertEqual(self.controller.error_message, "Nothing to export yet.")
        self.assertEqual(self.runner.async_sources, [])

    def test_a_cancelled_save_dialog_announces_nothing(self) -> None:
        self.bridge.receive_message(
            {"event": "objectsReplaced", "objects": [{"name": "1CRN", "type": "structure"}]}
        )
        self.runner.async_result = _one_pixel_data_url()
        self.controller.export_image(ExportFormat.png, lambda _name: None)
        self.assertEqual(self.controller.status_message, IDLE_STATUS)
        self.assertIsNone(self.controller.error_message)

    def test_export_writes_the_chosen_file(self) -> None:
        self.bridge.receive_message(
            {"event": "objectsReplaced", "objects": [{"name": "1CRN", "type": "structure"}]}
        )
        self.runner.async_result = _one_pixel_data_url()
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "molecule.png")
            self.controller.export_image(ExportFormat.png, lambda _name: path)
            self.assertTrue(os.path.getsize(path) > 0)
        self.assertEqual(self.controller.status_message, "Saved molecule.png")

    def test_a_capture_failure_is_reported(self) -> None:
        self.bridge.receive_message(
            {"event": "objectsReplaced", "objects": [{"name": "1CRN", "type": "structure"}]}
        )
        self.runner.async_result = None
        self.controller.export_image(ExportFormat.png, lambda _name: "/dev/null")
        self.assertEqual(self.controller.error_message, "Could not capture the display.")


class LocalFileTests(unittest.TestCase):
    def test_format_for(self) -> None:
        self.assertEqual(format_for("a.pdb"), "pdb")
        self.assertEqual(format_for("a.CIF"), "mmcif")
        self.assertEqual(format_for("a.mmcif"), "mmcif")
        with self.assertRaises(StructureFileError):
            format_for("a.txt")
        with self.assertRaises(StructureFileError):
            format_for("noextension")

    def test_read_capped_rejects_an_empty_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "empty.pdb")
            open(path, "wb").close()
            with self.assertRaises(StructureFileError):
                read_capped(path)

    def test_read_capped_is_lossy_rather_than_fatal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "latin1.pdb")
            with open(path, "wb") as handle:
                handle.write(b"REMARK caf\xe9\n")
            self.assertIn("REMARK caf", read_capped(path))

    def test_pdb_identifier(self) -> None:
        self.assertEqual(normalized_pdb_id(" 1crn "), "1CRN")
        with self.assertRaises(PdbIdentifierError):
            normalized_pdb_id("crn")


class ExportTests(unittest.TestCase):
    def test_data_url_decoding(self) -> None:
        self.assertIsNone(bytes_from_data_url("not a data url"))
        self.assertIsNone(bytes_from_data_url("data:image/png;base64,!!!!"))
        self.assertTrue(bytes_from_data_url(_one_pixel_data_url()).startswith(b"\x89PNG"))

    def test_every_container_encodes(self) -> None:
        png = bytes_from_data_url(_one_pixel_data_url())
        assert png is not None
        signatures = {
            ExportFormat.png: b"\x89PNG",
            ExportFormat.jpeg: b"\xff\xd8\xff",
            ExportFormat.gif: b"GIF8",
            ExportFormat.svg: b"<svg",
            ExportFormat.pdf: b"%PDF",
        }
        for export_format, signature in signatures.items():
            data = encode_export(png, export_format)
            self.assertTrue(data.startswith(signature), export_format.title)


def _one_pixel_data_url() -> str:
    import base64
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGBA", (2, 2), (11, 15, 20, 255)).save(buffer, "PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


if __name__ == "__main__":
    unittest.main()
