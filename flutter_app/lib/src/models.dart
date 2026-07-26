import 'package:flutter/material.dart';

/// Scene-wide representation offered by Display ▸ Representation. A strict subset of
/// [ObjectRepresentation]: the whole-scene menu only ever offered these three.
enum MoleculeRepresentation {
  ribbon('ribbon', 'Ribbon', Icons.gesture),
  surface('surface', 'Surface', Icons.blur_on),
  stick('stick', 'Stick', Icons.remove);

  const MoleculeRepresentation(this.raw, this.title, this.icon);

  final String raw;
  final String title;
  final IconData icon;

  static MoleculeRepresentation? fromRaw(String raw) {
    for (final value in values) {
      if (value.raw == raw) return value;
    }
    return null;
  }
}

/// Structural features Display ▸ Visibility can show or hide across the whole scene.
enum MoleculeVisibilityFeature {
  protein('protein', 'Protein', Icons.polymer),
  water('water', 'Water', Icons.water_drop_outlined),
  ligand('ligand', 'Ligand', Icons.hexagon_outlined);

  const MoleculeVisibilityFeature(this.raw, this.title, this.icon);

  final String raw;
  final String title;
  final IconData icon;

  static MoleculeVisibilityFeature? fromRaw(String raw) {
    for (final value in values) {
      if (value.raw == raw) return value;
    }
    return null;
  }
}

/// Per-object representation shown as the Rib/Sur/Stk/B+S/Sph buttons in the Objects panel.
enum ObjectRepresentation {
  ribbon('ribbon', 'Ribbon', 'Rib'),
  surface('surface', 'Surface', 'Sur'),
  stick('stick', 'Stick', 'Stk'),
  ballAndStick('ballAndStick', 'Ball+Stick', 'B+S'),
  sphere('sphere', 'Sphere', 'Sph');

  const ObjectRepresentation(this.raw, this.title, this.shortTitle);

  final String raw;
  final String title;
  final String shortTitle;

  static ObjectRepresentation? fromRaw(String raw) {
    for (final value in values) {
      if (value.raw == raw) return value;
    }
    return null;
  }

  /// Case-insensitive lookup for the `repr <name> <object>` command, which lowercases its keywords.
  static ObjectRepresentation? fromRawIgnoringCase(String raw) {
    final needle = raw.toLowerCase();
    for (final value in values) {
      if (value.raw.toLowerCase() == needle) return value;
    }
    return null;
  }
}

enum MolAppObjectType { structure, selection }

/// A row in the Objects panel: a loaded structure or a named selection.
@immutable
class MolAppObject {
  const MolAppObject({
    required this.name,
    required this.type,
    this.isVisible = true,
    this.representation = ObjectRepresentation.ribbon,
    this.colorHex,
  });

  final String name;
  final MolAppObjectType type;
  final bool isVisible;
  final ObjectRepresentation representation;
  final String? colorHex;

  MolAppObject copyWith({
    bool? isVisible,
    ObjectRepresentation? representation,
    String? colorHex,
    bool clearColor = false,
  }) {
    return MolAppObject(
      name: name,
      type: type,
      isVisible: isVisible ?? this.isVisible,
      representation: representation ?? this.representation,
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
    );
  }

  /// Swatch color for the Objects panel. No explicit color means Mol* is coloring by chain, which
  /// the panel shows as a neutral dot rather than pretending it is white.
  Color get swatchColor => colorFromHex(colorHex) ?? Colors.white.withValues(alpha: 0.3);

  @override
  bool operator ==(Object other) =>
      other is MolAppObject &&
      other.name == name &&
      other.type == type &&
      other.isVisible == isVisible &&
      other.representation == representation &&
      other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(name, type, isVisible, representation, colorHex);
}

/// Node kinds of the selection-expression AST, matching `queryFromAST` in viewer.html.
enum SelectionASTKind {
  and,
  or,
  not,
  chain,
  residue,
  residueRange,
  residueName,
  atom,
  model,
}

/// Selection-expression AST. `left`/`right`/`operand` are single-element lists because the Swift
/// original used arrays to break the recursive-value cycle; viewer.html reads `ast.left[0]`.
@immutable
class SelectionAST {
  const SelectionAST({
    required this.kind,
    this.left,
    this.right,
    this.operand,
    this.value,
  });

  final SelectionASTKind kind;
  final List<SelectionAST>? left;
  final List<SelectionAST>? right;
  final List<SelectionAST>? operand;
  final String? value;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        if (left != null) 'left': left!.map((e) => e.toJson()).toList(),
        if (right != null) 'right': right!.map((e) => e.toJson()).toList(),
        if (operand != null) 'operand': operand!.map((e) => e.toJson()).toList(),
        if (value != null) 'value': value,
      };

  @override
  bool operator ==(Object other) =>
      other is SelectionAST &&
      other.kind == kind &&
      other.value == value &&
      _listEquals(other.left, left) &&
      _listEquals(other.right, right) &&
      _listEquals(other.operand, operand);

  @override
  int get hashCode => Object.hash(kind, value, left?.length, right?.length, operand?.length);

  static bool _listEquals(List<SelectionAST>? a, List<SelectionAST>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A selection, either picked in the viewport (atom/residue fields) or parsed from an expression
/// (`ast`). Encoded null fields are omitted, matching Swift's `encodeIfPresent` behaviour that
/// viewer.html's handlers were written against.
@immutable
class MoleculeSelection {
  const MoleculeSelection({
    required this.type,
    this.label,
    this.model,
    this.chain,
    this.residueNumber,
    this.atomName,
    this.ast,
  });

  final String type;
  final String? label;
  final int? model;
  final String? chain;
  final int? residueNumber;
  final String? atomName;
  final SelectionAST? ast;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (label != null) 'label': label,
        if (model != null) 'model': model,
        if (chain != null) 'chain': chain,
        if (residueNumber != null) 'residueNumber': residueNumber,
        if (atomName != null) 'atomName': atomName,
        if (ast != null) 'ast': ast!.toJson(),
      };

  static MoleculeSelection? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final type = json['type'];
    if (type is! String) return null;
    return MoleculeSelection(
      type: type,
      label: json['label'] as String?,
      model: (json['model'] as num?)?.toInt(),
      chain: json['chain'] as String?,
      residueNumber: (json['residueNumber'] as num?)?.toInt(),
      atomName: json['atomName'] as String?,
    );
  }
}

/// Measurement modes. The atom count is how many picks close one measurement.
enum MeasureKind {
  distance('distance', 'Distance', 2),
  angle('angle', 'Angle', 3),
  dihedral('dihedral', 'Dihedral', 4);

  const MeasureKind(this.raw, this.title, this.atomCount);

  final String raw;
  final String title;
  final int atomCount;
}

/// Containers File ▸ Export Display can write the current viewport to.
enum ExportFormat {
  png('png', 'PNG', 'png'),
  jpeg('jpeg', 'JPEG', 'jpg'),
  gif('gif', 'GIF', 'gif'),
  svg('svg', 'SVG', 'svg'),
  pdf('pdf', 'PDF', 'pdf');

  const ExportFormat(this.raw, this.title, this.fileExtension);

  final String raw;
  final String title;
  final String fileExtension;
}

class PdbIdentifierException implements Exception {
  const PdbIdentifierException();

  @override
  String toString() => 'Enter a 4-character PDB ID.';
}

abstract final class PdbIdentifier {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9]{4}$');

  static String normalized(String rawValue) {
    final pdbId = rawValue.trim().toUpperCase();
    if (!_pattern.hasMatch(pdbId)) throw const PdbIdentifierException();
    return pdbId;
  }

  static String displayName(String rawValue) {
    try {
      return normalized(rawValue);
    } on PdbIdentifierException {
      return rawValue.trim().toUpperCase();
    }
  }
}

@immutable
class BackgroundPreset {
  const BackgroundPreset(this.title, this.hex);

  final String title;
  final String hex;
}

/// Viewport background presets (dark → light), shared by Display ▸ Background and the
/// `background` command so both offer the same names.
const List<BackgroundPreset> backgroundPresets = <BackgroundPreset>[
  BackgroundPreset('Dark', '#0B0F14'),
  BackgroundPreset('Black', '#000000'),
  BackgroundPreset('Gray', '#4D4D4D'),
  BackgroundPreset('Light', '#D9D9D9'),
  BackgroundPreset('White', '#FFFFFF'),
];

/// Okabe-Ito colorblind-safe qualitative palette. Command names keep their familiar labels; the
/// hexes map to the nearest Okabe-Ito hue so every swatch stays distinguishable under
/// deuteranopia/protanopia. "white" is the light neutral in place of Okabe-Ito black (invisible on
/// the dark viewport).
const Map<String, String> namedColors = <String, String>{
  'red': '#D55E00',
  'green': '#009E73',
  'blue': '#0072B2',
  'yellow': '#F0E442',
  'white': '#FFFFFF',
  'cyan': '#56B4E9',
  'magenta': '#CC79A7',
  'orange': '#E69F00',
};

/// Order the color-picker grid presents, "Default" first (clears the override).
const List<String> colorPickerKeys = <String>[
  'default',
  'red',
  'green',
  'blue',
  'yellow',
  'white',
  'cyan',
  'magenta',
  'orange',
];

Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  final digits = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (digits.length != 6) return null;
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}
