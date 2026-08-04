"""End-to-end check against the real WebKitGTK viewport and the real Mol* bundle.

This is the test that matters for a platform bring-up: it boots the actual window, pushes a
structure in as text (no network, no file picker), and checks that the object comes back, that a
per-object command lands, that state serialisation and image capture return, and that Reset clears
the scene — the Linux counterpart of `flutter_app/integration_test/viewer_bridge_test.dart`.

Needs a display. On a headless machine:

    xvfb-run -a python3 -m unittest tests.test_smoke -v

Set MOLAPP_SHOT=/path/to/shot.png to also write a screenshot of the window at the end.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import gi  # noqa: E402

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from molapp.models import ExportFormat, MolAppObjectType, ObjectRepresentation  # noqa: E402
from molapp.window import MolAppWindow  # noqa: E402

#: Two alanines with a full backbone: enough for Mol* to build a real structure (and a ribbon) with
#: no network and no fixture file.
_MINI_PDB = """\
HEADER    TEST STRUCTURE                          01-JAN-70   MINI
ATOM      1  N   ALA A   1      -0.677   1.230  -0.491  1.00  0.00           N
ATOM      2  CA  ALA A   1      -0.001   0.000   0.000  1.00  0.00           C
ATOM      3  C   ALA A   1       1.498   0.000   0.000  1.00  0.00           C
ATOM      4  O   ALA A   1       2.092   0.000   1.075  1.00  0.00           O
ATOM      5  CB  ALA A   1      -0.509  -0.746  -1.225  1.00  0.00           C
ATOM      6  N   ALA A   2       2.128   0.000  -1.169  1.00  0.00           N
ATOM      7  CA  ALA A   2       3.579   0.000  -1.298  1.00  0.00           C
ATOM      8  C   ALA A   2       4.220   1.230  -0.669  1.00  0.00           C
ATOM      9  O   ALA A   2       5.447   1.298  -0.560  1.00  0.00           O
ATOM     10  CB  ALA A   2       4.033  -0.126  -2.746  1.00  0.00           C
TER      11      ALA A   2
END
"""

TIMEOUT_SECONDS = 60


def pump_until(predicate, timeout_seconds: int = TIMEOUT_SECONDS) -> bool:
    """Runs the GTK main loop until `predicate()` is true, or the timeout expires."""
    deadline = GLib.get_monotonic_time() + timeout_seconds * 1_000_000
    while not predicate():
        if GLib.get_monotonic_time() > deadline:
            return False
        Gtk.main_iteration_do(False)
        GLib.usleep(5_000)
    return True


@unittest.skipUnless(
    os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"),
    "needs a display; run under xvfb-run on a headless machine",
)
class ViewerBridgeSmokeTests(unittest.TestCase):
    window: MolAppWindow

    @classmethod
    def setUpClass(cls) -> None:
        cls.application = Gtk.Application(application_id="com.donghan.molapp.test")
        cls.application.register()
        cls.window = MolAppWindow(cls.application)
        cls.window.show_all()
        assert pump_until(lambda: cls.window.bridge.is_viewer_ready), (
            "the Mol* viewer never reported viewerReady: " f"{cls.window.bridge.last_error_message}"
        )

    @classmethod
    def tearDownClass(cls) -> None:
        shot = os.environ.get("MOLAPP_SHOT")
        if shot:
            pump_until(lambda: False, timeout_seconds=2)
            gdk_window = cls.window.get_window()
            pixbuf = Gdk.pixbuf_get_from_window(
                gdk_window, 0, 0, gdk_window.get_width(), gdk_window.get_height()
            )
            if pixbuf is not None:
                pixbuf.savev(shot, "png", [], [])
        cls.window.destroy()

    # The checks run in one ordered sequence: each builds on the scene the previous one left.

    def test_01_the_viewer_boots(self) -> None:
        self.assertTrue(self.window.bridge.is_viewer_ready)
        self.assertFalse(self.window.bridge.is_viewer_fatal)
        self.assertIsNone(self.window.bridge.last_error_message)

    def test_02_a_structure_loads_and_reaches_the_objects_panel(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "MINI.pdb")
            with open(path, "w") as handle:
                handle.write(_MINI_PDB)
            self.window.controller.load_structure_file(path)
            self.assertTrue(
                pump_until(lambda: bool(self.window.bridge.objects)),
                f"structure never appeared: {self.window.controller.error_message}",
            )

        obj = self.window.bridge.objects[0]
        self.assertEqual(obj.name, "MINI.pdb")
        self.assertEqual(obj.type, MolAppObjectType.structure)

        # The status line follows the command *result*, which is a separate message from the
        # objectsReplaced event above and can land a turn later — so wait for it rather than
        # assuming the two arrive together.
        self.assertTrue(
            pump_until(lambda: self.window.controller.status_message == "Loaded MINI.pdb"),
            f"status stuck at {self.window.controller.status_message!r}",
        )

    def test_03_a_per_object_command_lands(self) -> None:
        name = self.window.bridge.objects[0].name
        self.window.bridge.set_object_representation(name, ObjectRepresentation.sphere)
        self.assertTrue(
            pump_until(
                lambda: self.window.bridge.objects[0].representation
                is ObjectRepresentation.sphere
            ),
            "the viewer never echoed the representation change back",
        )

    def test_04_the_command_bar_drives_the_viewer(self) -> None:
        self.window.controller.set_command_text("color red MINI.pdb")
        self.window.controller.execute_command()
        self.assertTrue(
            pump_until(lambda: self.window.bridge.objects[0].color_hex == "#D55E00"),
            "the viewer never echoed the colour change back",
        )
        self.assertIsNone(self.window.controller.error_message)

    def test_05_state_serialises(self) -> None:
        captured: list[str | None] = []
        self.window.bridge.serialize_state(captured.append)
        self.assertTrue(pump_until(lambda: bool(captured)), "serializeState never returned")
        self.assertIsNotNone(captured[0])
        self.assertIn("MINI.pdb", captured[0] or "")

    def test_06_the_viewport_captures_a_real_image(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "molecule.png")
            self.window.controller.export_image(ExportFormat.png, lambda _name: path)
            self.assertTrue(
                pump_until(lambda: os.path.exists(path)),
                f"nothing was written: {self.window.controller.error_message}",
            )
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
            self.assertGreater(pixbuf.get_width(), 200)
            # A blank canvas would still be a valid PNG, so require the molecule to have actually
            # rendered: the scene must contain something other than the background colour.
            self.assertTrue(_has_foreground(pixbuf), "the captured viewport is a flat background")

    def test_07_a_closed_info_card_survives_show_all(self) -> None:
        # The window re-runs show_all() every time the application is activated, which resurrected
        # both of these until they opted out of it.
        self.window._set_info_card_visible(False)
        self.window._toggle_objects_panel()
        self.window.show_all()
        self.assertFalse(self.window._info_card.get_visible())
        self.assertFalse(self.window._objects_scroller.get_visible())

        self.window._set_info_card_visible(True)
        self.window._toggle_objects_panel()
        self.assertTrue(self.window._info_card.get_visible())
        # Opting out of show_all also makes show_all() on the card a no-op, so its children have to
        # come back too, not just the card.
        self.assertTrue(all(child.get_visible() for child in self.window._info_card.get_children()[:4]))
        self.assertTrue(self.window._objects_scroller.get_visible())

    def test_08_reset_clears_the_scene(self) -> None:
        self.window.controller.reset_all()
        self.assertTrue(
            pump_until(lambda: not self.window.bridge.objects), "Reset All left objects behind"
        )


def _has_foreground(pixbuf: GdkPixbuf.Pixbuf) -> bool:
    """True when the image holds more than one colour — i.e. something was drawn."""
    pixels = pixbuf.get_pixels()
    channels = pixbuf.get_n_channels()
    first = pixels[0:3]
    # Sample rather than scan: a 2000×1500 capture is 9 MB of bytes and one differing pixel is all
    # this needs to find.
    for offset in range(0, len(pixels) - channels, channels * 97):
        if pixels[offset: offset + 3] != first:
            return True
    return False


if __name__ == "__main__":
    unittest.main()
