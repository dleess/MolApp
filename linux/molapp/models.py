"""Domain model, ported from `flutter_app/lib/src/models.dart` (and the Swift original).

Enum *names* are the wire format — they are what `viewer.html` reads — so renaming a member
renames the protocol. `test_logic.py` asserts the names for that reason.
"""

from __future__ import annotations

import enum
import os
import re
from typing import NamedTuple


class MoleculeRepresentation(enum.Enum):
    """Scene-wide representation offered by Display ▸ Representation. A strict subset of
    :class:`ObjectRepresentation`: the whole-scene menu only ever offered these three."""

    ribbon = "Ribbon"
    surface = "Surface"
    stick = "Stick"

    @property
    def title(self) -> str:
        return self.value

    @classmethod
    def from_raw(cls, raw: str) -> "MoleculeRepresentation | None":
        return cls.__members__.get(raw)


class MoleculeVisibilityFeature(enum.Enum):
    """Structural features Display ▸ Visibility can show or hide across the whole scene."""

    protein = "Protein"
    water = "Water"
    ligand = "Ligand"

    @property
    def title(self) -> str:
        return self.value

    @classmethod
    def from_raw(cls, raw: str) -> "MoleculeVisibilityFeature | None":
        return cls.__members__.get(raw)


class ObjectRepresentation(enum.Enum):
    """Per-object representation shown as the Rib/Sur/Stk/B+S/Sph buttons in the Objects panel."""

    ribbon = ("Ribbon", "Rib")
    surface = ("Surface", "Sur")
    stick = ("Stick", "Stk")
    ballAndStick = ("Ball+Stick", "B+S")
    sphere = ("Sphere", "Sph")

    @property
    def title(self) -> str:
        return self.value[0]

    @property
    def short_title(self) -> str:
        return self.value[1]

    @classmethod
    def from_raw(cls, raw: str) -> "ObjectRepresentation | None":
        return cls.__members__.get(raw)

    @classmethod
    def from_raw_ignoring_case(cls, raw: str) -> "ObjectRepresentation | None":
        """Case-insensitive lookup for `repr <name> <object>`, which lowercases its keywords."""
        needle = raw.lower()
        for value in cls:
            if value.name.lower() == needle:
                return value
        return None


class MolAppObjectType(enum.Enum):
    structure = "structure"
    selection = "selection"


class MolAppObject(NamedTuple):
    """A row in the Objects panel: a loaded structure or a named selection."""

    name: str
    type: MolAppObjectType
    is_visible: bool = True
    representation: ObjectRepresentation = ObjectRepresentation.ribbon
    color_hex: str | None = None

    @property
    def swatch_rgb(self) -> tuple[float, float, float] | None:
        """Swatch colour for the Objects panel. No explicit colour means Mol* is colouring by
        chain, which the panel shows as a neutral dot rather than pretending it is white."""
        return rgb_from_hex(self.color_hex)


class SelectionASTKind(enum.Enum):
    """Node kinds of the selection-expression AST, matching `queryFromAST` in viewer.html."""

    and_ = "and"
    or_ = "or"
    not_ = "not"
    chain = "chain"
    residue = "residue"
    residueRange = "residueRange"
    residueName = "residueName"
    atom = "atom"
    model = "model"


class SelectionAST(NamedTuple):
    """`left`/`right`/`operand` are single-element lists because the Swift original used arrays to
    break the recursive-value cycle; viewer.html reads `ast.left[0]`."""

    kind: SelectionASTKind
    left: "list[SelectionAST] | None" = None
    right: "list[SelectionAST] | None" = None
    operand: "list[SelectionAST] | None" = None
    value: str | None = None

    def to_json(self) -> dict:
        json: dict = {"kind": self.kind.value}
        if self.left is not None:
            json["left"] = [node.to_json() for node in self.left]
        if self.right is not None:
            json["right"] = [node.to_json() for node in self.right]
        if self.operand is not None:
            json["operand"] = [node.to_json() for node in self.operand]
        if self.value is not None:
            json["value"] = self.value
        return json


class MoleculeSelection(NamedTuple):
    """A selection, either picked in the viewport (atom/residue fields) or parsed from an
    expression (`ast`). Null fields are omitted, matching the Swift `encodeIfPresent` behaviour
    viewer.html's handlers were written against."""

    type: str
    label: str | None = None
    model: int | None = None
    chain: str | None = None
    residue_number: int | None = None
    atom_name: str | None = None
    ast: SelectionAST | None = None

    def to_json(self) -> dict:
        json: dict = {"type": self.type}
        if self.label is not None:
            json["label"] = self.label
        if self.model is not None:
            json["model"] = self.model
        if self.chain is not None:
            json["chain"] = self.chain
        if self.residue_number is not None:
            json["residueNumber"] = self.residue_number
        if self.atom_name is not None:
            json["atomName"] = self.atom_name
        if self.ast is not None:
            json["ast"] = self.ast.to_json()
        return json

    @staticmethod
    def from_json(json: dict | None) -> "MoleculeSelection | None":
        if not isinstance(json, dict) or not isinstance(json.get("type"), str):
            return None
        return MoleculeSelection(
            type=json["type"],
            label=json.get("label"),
            model=json.get("model"),
            chain=json.get("chain"),
            residue_number=json.get("residueNumber"),
            atom_name=json.get("atomName"),
        )


class MeasureKind(enum.Enum):
    """Measurement modes. The atom count is how many picks close one measurement."""

    distance = ("Distance", 2)
    angle = ("Angle", 3)
    dihedral = ("Dihedral", 4)

    @property
    def title(self) -> str:
        return self.value[0]

    @property
    def atom_count(self) -> int:
        return self.value[1]


class ExportFormat(enum.Enum):
    """Containers File ▸ Export Display can write the current viewport to."""

    png = ("PNG", "png", "image/png")
    jpeg = ("JPEG", "jpg", "image/jpeg")
    gif = ("GIF", "gif", "image/gif")
    svg = ("SVG", "svg", "image/svg+xml")
    pdf = ("PDF", "pdf", "application/pdf")

    @property
    def title(self) -> str:
        return self.value[0]

    @property
    def file_extension(self) -> str:
        return self.value[1]

    @property
    def mime_type(self) -> str:
        return self.value[2]


class PdbIdentifierError(Exception):
    def __init__(self) -> None:
        super().__init__("Enter a 4-character PDB ID.")


_PDB_PATTERN = re.compile(r"^[A-Z0-9]{4}$")


def normalized_pdb_id(raw_value: str) -> str:
    pdb_id = raw_value.strip().upper()
    if not _PDB_PATTERN.match(pdb_id):
        raise PdbIdentifierError()
    return pdb_id


def pdb_display_name(raw_value: str) -> str:
    try:
        return normalized_pdb_id(raw_value)
    except PdbIdentifierError:
        return raw_value.strip().upper()


class BackgroundPreset(NamedTuple):
    title: str
    hex: str


#: Viewport background presets (dark → light), shared by Display ▸ Background and the
#: `background` command so both offer the same names.
BACKGROUND_PRESETS: list[BackgroundPreset] = [
    BackgroundPreset("Dark", "#0B0F14"),
    BackgroundPreset("Black", "#000000"),
    BackgroundPreset("Gray", "#4D4D4D"),
    BackgroundPreset("Light", "#D9D9D9"),
    BackgroundPreset("White", "#FFFFFF"),
]

#: Okabe-Ito colourblind-safe qualitative palette, hex-for-hex the same table the other shells use.
NAMED_COLORS: dict[str, str] = {
    "red": "#D55E00",
    "green": "#009E73",
    "blue": "#0072B2",
    "yellow": "#F0E442",
    "white": "#FFFFFF",
    "cyan": "#56B4E9",
    "magenta": "#CC79A7",
    "orange": "#E69F00",
}

#: Order the colour-picker grid presents, "default" first (clears the override).
COLOR_PICKER_KEYS: list[str] = ["default", *NAMED_COLORS]

HEX_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")


def rgb_from_hex(hex_value: str | None) -> tuple[float, float, float] | None:
    if hex_value is None:
        return None
    digits = re.sub(r"[^0-9A-Fa-f]", "", hex_value)
    if len(digits) != 6:
        return None
    value = int(digits, 16)
    return ((value >> 16 & 0xFF) / 255, (value >> 8 & 0xFF) / 255, (value & 0xFF) / 255)


# MARK: - Local files

class StructureFileError(Exception):
    pass


#: The payload is copied several times downstream (JSON encode → script → webview IPC), so a large
#: file peaks at several times its size. Same cap as the other shells.
MAX_FILE_SIZE = 64 * 1024 * 1024

STRUCTURE_EXTENSIONS = ["pdb", "cif", "mmcif"]
STATE_EXTENSIONS = ["molapp"]


def _extension_of(file_name: str) -> str:
    dot = file_name.rfind(".")
    if dot < 0 or dot == len(file_name) - 1:
        return ""
    return file_name[dot + 1:].lower()


def format_for(file_name: str) -> str:
    """Mol* data-format string for a structure file name."""
    extension = _extension_of(file_name)
    if extension == "pdb":
        return "pdb"
    if extension in ("cif", "mmcif"):
        return "mmcif"
    suffix = "selected file" if not extension else "." + extension
    raise StructureFileError(f"Unsupported structure file type: {suffix}.")


def read_capped(path: str) -> str:
    """Reads a structure or state file as text, rejecting an oversized or empty one.

    Decoding is lossy on purpose: Mol* decodes with a non-fatal TextDecoder, so rejecting a file
    for one stray Latin-1 byte in a REMARK would be stricter than the viewer that consumes it.
    """
    label = os.path.basename(path)
    size = os.path.getsize(path)
    if size > MAX_FILE_SIZE:
        raise StructureFileError(
            f"Structure file is too large: {size // (1024 * 1024)} MB "
            f"(limit {MAX_FILE_SIZE // (1024 * 1024)} MB)."
        )
    with open(path, "rb") as handle:
        data = handle.read(MAX_FILE_SIZE + 1)
    if len(data) > MAX_FILE_SIZE:
        raise StructureFileError(
            f"Structure file is too large: {len(data) // (1024 * 1024)} MB "
            f"(limit {MAX_FILE_SIZE // (1024 * 1024)} MB)."
        )
    if not data:
        raise StructureFileError(f"Could not read {label}.")
    return data.decode("utf-8", errors="replace")
