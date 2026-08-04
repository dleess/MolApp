"""Transport and viewer-derived state: the Python port of `molstar_bridge.dart` /
`MolStarBridge.swift`.

Commands are fire-and-forget through a serial script queue; JS answers with command results and
unsolicited events, both of which arrive at :meth:`MolStarBridge.receive_message`. The class knows
nothing about GTK or WebKit — :mod:`molapp.webview` supplies the runner — so it is unit-testable
without a display.
"""

from __future__ import annotations

import enum
import itertools
import json
from typing import Callable, Protocol

from .models import (
    MolAppObject,
    MolAppObjectType,
    MoleculeSelection,
    ObjectRepresentation,
)


class MolStarCommand(enum.Enum):
    """Commands sent to `window.molapp.handleNativeCommand` in viewer.html."""

    loadLocalStructure = "loadLocalStructure"
    loadPdbId = "loadPdbId"
    setRepresentation = "setRepresentation"
    toggleVisibility = "toggleVisibility"
    focusSelection = "focusSelection"
    setSelection = "setSelection"
    clearSelection = "clearSelection"
    setObjectVisibility = "setObjectVisibility"
    setObjectRepresentation = "setObjectRepresentation"
    setObjectColor = "setObjectColor"
    setBackgroundColor = "setBackgroundColor"
    surfacePotential = "surfacePotential"
    startMorph = "startMorph"
    stopMorph = "stopMorph"
    superpose = "superpose"
    secondaryStructure = "secondaryStructure"
    setMeasureMode = "setMeasureMode"
    clearMeasurements = "clearMeasurements"
    resetAll = "resetAll"
    undo = "undo"
    redo = "redo"
    loadState = "loadState"

    #: Posted by JS whenever it clears measure/morph mode, independent of the command that
    #: triggered it: a command can clear these and then fail, so success is not a reliable signal.
    transientModesStopped = "transientModesStopped"

    @classmethod
    def from_raw(cls, raw: str | None) -> "MolStarCommand | None":
        return None if raw is None else cls.__members__.get(raw)


class MolStarCommandResult:
    __slots__ = ("id", "success", "command", "error", "label")

    def __init__(
        self,
        id: str,
        success: bool,
        command: MolStarCommand | None = None,
        error: str | None = None,
        label: str | None = None,
    ) -> None:
        self.id = id
        self.success = success
        #: None when JS reported a command name this build does not know.
        self.command = command
        self.error = error
        self.label = label

    @staticmethod
    def from_json(json_message: dict) -> "MolStarCommandResult":
        return MolStarCommandResult(
            id=json_message.get("id") or "",
            success=json_message.get("success") is True,
            command=MolStarCommand.from_raw(json_message.get("command")),
            error=json_message.get("error"),
            label=json_message.get("label"),
        )


class MolStarJsRunner(Protocol):
    """The JS side of the viewer, as the bridge needs it. Implemented per webview backend so the
    bridge itself stays platform-free."""

    def evaluate(self, source: str) -> None:
        """Fire-and-forget evaluation. Errors surface through `last_error_message`."""

    def call_async(self, source: str, on_done: Callable[[object | None, str | None], None]) -> None:
        """Awaited evaluation used by the two request/response calls (state + image capture).
        `source` is an async function body that returns a value."""


class MolStarBridge:
    def __init__(self) -> None:
        self._runner: MolStarJsRunner | None = None
        self._listeners: list[Callable[[], None]] = []
        self._pending_scripts: list[str] = []
        self._command_ids = itertools.count()

        self.is_viewer_ready = False
        #: The viewer never came up at all (fatal init failure). Distinct from `not
        #: is_viewer_ready`, which is the normal "still booting" state `_pending_scripts` covers.
        self.is_viewer_fatal = False

        self.last_command_result: MolStarCommandResult | None = None
        self.last_error_message: str | None = None
        self.current_selection: MoleculeSelection | None = None
        self.objects: list[MolAppObject] = []

        #: Hover: the label comes from JS (Mol* hover), the point from the injected pointer
        #: listener. The tooltip shows only when both are present.
        self.hover_label: str | None = None
        self.hover_point: tuple[float, float] | None = None

        #: Last completed measurement, as "atomA — atomB" (the value itself is drawn on canvas).
        self.last_measurement: str | None = None
        #: Bumped once per measurement event. Labels omit the model number and are None for unnamed
        #: atoms, so two genuinely different measurements can carry the same text — listeners must
        #: key off this counter or the second one is silently swallowed.
        self.measurement_seq = 0

        #: Atoms already picked for the measurement being built, out of `measure_target_count`.
        self.measure_pending_count = 0
        self.measure_target_count = 2
        self.measure_pending_labels: list[str] = []

        #: Feature (water/ligand/protein) visibility JS changed on its own (e.g. Surface auto-hides
        #: water); the UI observes this to keep Display ▸ Visibility in sync.
        self.feature_visibility: dict[str, bool] = {}

    # MARK: - Observation

    def add_listener(self, listener: Callable[[], None]) -> None:
        self._listeners.append(listener)

    def _notify(self) -> None:
        for listener in list(self._listeners):
            listener()

    @property
    def visible_structure_names(self) -> list[str]:
        """Structures the user has left visible (eye-on). Global actions (representation, surface
        potential, morph) are scoped to this list."""
        return [
            obj.name
            for obj in self.objects
            if obj.type is MolAppObjectType.structure and obj.is_visible
        ]

    # MARK: - Attachment

    def attach(self, runner: MolStarJsRunner) -> None:
        """Binds a freshly loaded page. Readiness is reset here rather than at the call sites: this
        is the one path every load and reload routes through, so the flag cannot outlive its page."""
        self._runner = runner
        self.is_viewer_ready = False
        self.is_viewer_fatal = False
        self._notify()

    def detach(self) -> None:
        self._runner = None
        self.is_viewer_ready = False

    def update_hover_point(self, point: tuple[float, float] | None) -> None:
        self.hover_point = point
        if point is None and self.hover_label is not None:
            self.hover_label = None
        self._notify()

    def clear_error(self) -> None:
        if self.last_error_message is None:
            return
        self.last_error_message = None
        self._notify()

    def report_error(self, message: str | None) -> None:
        self.last_error_message = message
        self._notify()

    # MARK: - Commands

    def load_local_structure(self, data: str, format: str, label: str | None = None) -> None:
        payload: dict = {"data": data, "format": format}
        if label is not None:
            payload["label"] = label
        self._send(MolStarCommand.loadLocalStructure, payload)

    def load_pdb_id(self, pdb_id: str) -> None:
        self._send(MolStarCommand.loadPdbId, {"pdbId": pdb_id})

    def set_representation(self, representation: str, targets: list[str] | None = None) -> None:
        self._send(
            MolStarCommand.setRepresentation,
            {"representation": representation, "targets": targets or []},
        )

    def toggle_visibility(self, feature: str, is_visible: bool) -> None:
        self._send(MolStarCommand.toggleVisibility, {"feature": feature, "isVisible": is_visible})

    def focus_selection(self) -> None:
        self._send(MolStarCommand.focusSelection, {})

    def set_selection(self, selection: MoleculeSelection) -> None:
        self._send(MolStarCommand.setSelection, selection.to_json())

    def clear_selection(self) -> None:
        self._send(MolStarCommand.clearSelection, {})

    def add_object(self, obj: MolAppObject) -> None:
        """Idempotent by name, so a re-split after a representation change will not duplicate a row."""
        for index, existing in enumerate(self.objects):
            if existing.name == obj.name:
                self.objects[index] = obj
                break
        else:
            self.objects.append(obj)
        self._notify()

    def set_object_visibility(self, name: str, is_visible: bool) -> None:
        self._send(MolStarCommand.setObjectVisibility, {"name": name, "isVisible": is_visible})

    def set_object_representation(self, name: str, representation: ObjectRepresentation) -> None:
        self._send(
            MolStarCommand.setObjectRepresentation,
            {"name": name, "representation": representation.name},
        )

    def set_object_color(self, name: str, color_hex: str | None) -> None:
        # colorHex is sent explicitly as null: viewer.html treats null and undefined alike (reset
        # to chain-id), so keeping the key makes the "clear the colour" intent legible on the wire.
        self._send(MolStarCommand.setObjectColor, {"name": name, "colorHex": color_hex})

    def set_background_color(self, color_hex: str) -> None:
        self._send(MolStarCommand.setBackgroundColor, {"colorHex": color_hex})

    def draw_surface_potential(self, targets: list[str] | None = None) -> None:
        self._send(MolStarCommand.surfacePotential, {"targets": targets or []})

    def start_morph(
        self, duration_in_s: float = 5, loop: bool = False, targets: list[str] | None = None
    ) -> None:
        self._send(
            MolStarCommand.startMorph,
            {"durationInS": duration_in_s, "loop": loop, "targets": targets or []},
        )

    def stop_morph(self) -> None:
        self._send(MolStarCommand.stopMorph, {})

    def superpose(self, targets: list[str] | None = None) -> None:
        self._send(MolStarCommand.superpose, {"targets": targets or []})

    def compute_secondary_structure(self, targets: list[str] | None = None) -> None:
        self._send(MolStarCommand.secondaryStructure, {"targets": targets or []})

    def set_measure_mode(self, enabled: bool, kind: str | None = None) -> None:
        payload: dict = {"enabled": enabled}
        if kind is not None:
            payload["kind"] = kind
        self._send(MolStarCommand.setMeasureMode, payload)

    def clear_measurements(self) -> None:
        self._send(MolStarCommand.clearMeasurements, {})

    def reset_all(self) -> None:
        self._send(MolStarCommand.resetAll, {})

    def undo(self) -> None:
        self._send(MolStarCommand.undo, {})

    def redo(self) -> None:
        self._send(MolStarCommand.redo, {})

    def load_state(self, json_text: str) -> None:
        self._send(MolStarCommand.loadState, {"json": json_text})

    # Request/response (not fire-and-forget): the caller needs the returned value, so these bypass
    # the serial script queue and read the JS result directly.

    def serialize_state(self, on_done: Callable[[str | None], None]) -> None:
        runner = self._runner
        if runner is None:
            on_done(None)
            return
        runner.call_async(
            "return (window.molapp && window.molapp.serializeMolAppState)"
            " ? await window.molapp.serializeMolAppState() : null;",
            lambda value, error: self._on_async_string(value, error, on_done),
        )

    def capture_image_data_url(self, on_done: Callable[[str | None], None]) -> None:
        runner = self._runner
        if runner is None:
            on_done(None)
            return
        runner.call_async(
            "return await window.molapp.captureImageDataURL();",
            lambda value, error: self._on_async_string(value, error, on_done),
        )

    def _on_async_string(
        self, value: object | None, error: str | None, on_done: Callable[[str | None], None]
    ) -> None:
        if error is not None:
            self.report_error(error)
            on_done(None)
            return
        on_done(value if isinstance(value, str) else None)

    def send_hover(self, x: float, y: float) -> None:
        """Pointer hover position, forwarded so Mol* can report what is under the cursor."""
        if self._runner is not None:
            self._runner.evaluate(f"window.molapp?.handlePencilHover?.({x}, {y});")

    def send_hover_end(self) -> None:
        if self._runner is not None:
            self._runner.evaluate("window.molapp?.handlePencilHoverEnd?.();")

    # MARK: - Script queue

    def _send(self, command: MolStarCommand, payload: dict) -> None:
        try:
            envelope = json.dumps(
                {"id": self._next_command_id(), "command": command.name, "payload": payload}
            )
        except (TypeError, ValueError):
            self.report_error(f"Unable to encode {command.name} command.")
            return
        self._enqueue_script(f"window.molapp.handleNativeCommand({envelope}); void 0;")

    def _next_command_id(self) -> str:
        return f"cmd-{next(self._command_ids)}"

    def _enqueue_script(self, script: str) -> None:
        # Queueing against a viewer that never booted grows without bound: loadLocalStructure
        # embeds the whole structure file in the script, and nothing will ever drain it.
        if self.is_viewer_fatal:
            return
        self._pending_scripts.append(script)
        self._flush_pending_scripts()

    def _flush_pending_scripts(self) -> None:
        runner = self._runner
        if not self.is_viewer_ready or not self._pending_scripts or runner is None:
            return
        scripts = list(self._pending_scripts)
        self._pending_scripts.clear()
        for script in scripts:
            runner.evaluate(script)

    # MARK: - Inbound events

    def receive_message(self, message: dict) -> None:
        """Entry point for everything JS posts back, command result or unsolicited event."""
        event = message.get("event")

        if event == "viewerReady":
            self.is_viewer_ready = True
            self.last_error_message = None
            self._flush_pending_scripts()
            self._notify()
            return

        if event == "viewerError":
            if message.get("fatal") is True:
                self.is_viewer_ready = False
                self.is_viewer_fatal = True
                self._pending_scripts.clear()
            self.last_error_message = message.get("message") or "Mol* viewer error."
            self._notify()
            return

        if event == "selectionChanged":
            self.current_selection = MoleculeSelection.from_json(message.get("selection"))
            self._notify()
            return

        if event == "pencilHover":
            label = message.get("label")
            if self.hover_label != label:
                self.hover_label = label
                self._notify()
            return

        if event == "measurement":
            self.last_measurement = message.get("label")
            self.measurement_seq += 1
            self._notify()
            return

        if event == "measurePending":
            labels = [raw for raw in (message.get("labels") or []) if isinstance(raw, str)]
            count = int(message.get("count") or 0)
            target = int(message.get("target") or 2)
            if (
                count != self.measure_pending_count
                or target != self.measure_target_count
                or labels != self.measure_pending_labels
            ):
                self.measure_pending_count = count
                self.measure_target_count = target
                self.measure_pending_labels = labels
                self._notify()
            return

        # JS split a structure's ligands into per-residue objects (e.g. NAP/JBC/SO4). Surface each
        # as a selection object so it gets its own eye/representation/colour row.
        if event == "objectsAdded":
            for raw in message.get("objects") or []:
                if not isinstance(raw, dict) or not isinstance(raw.get("name"), str):
                    continue
                self.add_object(
                    MolAppObject(
                        name=raw["name"],
                        type=MolAppObjectType.selection,
                        representation=_representation_of(raw) or ObjectRepresentation.ballAndStick,
                    )
                )
            return

        # The master Ligand toggle changes per-ligand visibility in JS; mirror it onto the rows so
        # the panel eye icons follow (they are separate controls from the master toggle).
        if event == "objectsVisibility":
            changed = False
            for raw in message.get("items") or []:
                if not isinstance(raw, dict):
                    continue
                name = raw.get("name")
                is_visible = raw.get("isVisible")
                if not isinstance(name, str) or not isinstance(is_visible, bool):
                    continue
                for index, existing in enumerate(self.objects):
                    if existing.name == name:
                        self.objects[index] = existing._replace(is_visible=is_visible)
                        changed = True
            if changed:
                self._notify()
            return

        # JS auto-changed a feature toggle (e.g. Surface hides water); mirror it so the menu label
        # ("Show/Hide Water") stays truthful.
        if event == "featureVisibility":
            feature = message.get("feature")
            is_visible = message.get("isVisible")
            if isinstance(feature, str) and isinstance(is_visible, bool):
                self.feature_visibility[feature] = is_visible
                self._notify()
            return

        # Undo/redo/reset rebuilt the JS scene; replace the whole panel from the restored state.
        if event == "objectsReplaced":
            rebuilt: list[MolAppObject] = []
            for raw in message.get("objects") or []:
                if not isinstance(raw, dict):
                    continue
                name = raw.get("name")
                type_raw = raw.get("type")
                if not isinstance(name, str) or type_raw not in ("structure", "selection"):
                    continue
                obj_type = MolAppObjectType(type_raw)
                default_representation = (
                    ObjectRepresentation.ribbon
                    if obj_type is MolAppObjectType.structure
                    else ObjectRepresentation.ballAndStick
                )
                color_hex = raw.get("colorHex")
                rebuilt.append(
                    MolAppObject(
                        name=name,
                        type=obj_type,
                        is_visible=raw.get("isVisible") is not False,
                        representation=_representation_of(raw) or default_representation,
                        color_hex=color_hex if isinstance(color_hex, str) else None,
                    )
                )
            self.objects = rebuilt
            visibility = message.get("visibility")
            if isinstance(visibility, dict):
                self.feature_visibility = {
                    key: value for key, value in visibility.items() if isinstance(value, bool)
                }
            self._notify()
            return

        # An event this shell does not handle (the shared viewer serves four shells, and each reads
        # events the others have no UI for) is not a command result — ignore it rather than
        # reporting a bogus failed command, which is what the Swift shell guards against too.
        if isinstance(event, str):
            return

        self._receive_result(MolStarCommandResult.from_json(message))

    def _receive_result(self, result: MolStarCommandResult) -> None:
        self.last_command_result = result
        self.last_error_message = None if result.success else result.error
        self._notify()


def _representation_of(raw: dict) -> ObjectRepresentation | None:
    """`.molapp` state files are user-editable and viewer.html echoes their object metadata straight
    back, so this field is type-checked the same way `name` and `type` already are."""
    value = raw.get("representation")
    return ObjectRepresentation.from_raw(value) if isinstance(value, str) else None
