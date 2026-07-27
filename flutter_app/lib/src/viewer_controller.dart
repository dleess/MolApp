import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'export.dart';
import 'models.dart';
import 'molstar_bridge.dart';
import 'selection_expression_parser.dart';
import 'structure_file.dart';

const String kIdleStatus = 'Ready for structure loading';

/// UI-facing state and actions: the status line, the transient measure/morph modes, the PDB-id and
/// command-bar text, and the command parser. Menus and the command bar share these methods so both
/// behave identically — the same split the Kotlin `ViewerController` used.
class ViewerController extends ChangeNotifier {
  ViewerController(this.bridge) {
    bridge.addListener(_onBridgeChanged);
  }

  final MolStarBridge bridge;

  String pdbText = '';
  String commandText = '';
  String statusMessage = kIdleStatus;
  String? localErrorMessage;
  MeasureKind? measureKind;
  bool isMorphing = false;
  MoleculeRepresentation selectedRepresentation = MoleculeRepresentation.ribbon;

  Map<MoleculeVisibilityFeature, bool> visibilityStates = <MoleculeVisibilityFeature, bool>{
    for (final feature in MoleculeVisibilityFeature.values) feature: true,
  };

  MolStarCommandResult? _seenCommandResult;
  int _seenMeasurementSeq = 0;

  String? get errorMessage => localErrorMessage ?? bridge.lastErrorMessage;

  List<String> get visibleStructureNames => bridge.visibleStructureNames;

  @override
  void dispose() {
    bridge.removeListener(_onBridgeChanged);
    super.dispose();
  }

  void updateStatus(String message) {
    statusMessage = message;
    notifyListeners();
  }

  void updateError(String? message) {
    localErrorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _beginAction();
    notifyListeners();
  }

  /// Every action starts from a clean error state on both sides; callers notify once they have
  /// finished mutating their own fields.
  void _beginAction() {
    localErrorMessage = null;
    bridge.clearError();
  }

  /// An action that could not start or finish: drop the optimistic status and report why.
  void _failAction(String message) {
    statusMessage = kIdleStatus;
    updateError(message);
  }

  void setPdbText(String value) {
    pdbText = value;
    notifyListeners();
  }

  void setCommandText(String value) {
    commandText = value;
    notifyListeners();
  }

  // MARK: - Bridge reactions

  void _onBridgeChanged() {
    var changed = false;

    // Key off the counter, not the label: measuring the same pair again, or two pairs that happen
    // to render the same text, are still separate measurements the status line must report.
    if (bridge.measurementSeq != _seenMeasurementSeq) {
      _seenMeasurementSeq = bridge.measurementSeq;
      final measurement = bridge.lastMeasurement;
      if (measurement != null) {
        statusMessage = '${measureKind?.title ?? 'Distance'}: $measurement';
        changed = true;
      }
    }

    final result = bridge.lastCommandResult;
    if (result != null && !identical(result, _seenCommandResult)) {
      _seenCommandResult = result;
      changed = _applyCommandResult(result) || changed;
    }

    final visibility = bridge.featureVisibility;
    final rebuilt = <MoleculeVisibilityFeature, bool>{
      for (final feature in MoleculeVisibilityFeature.values) feature: true,
    };
    for (final entry in visibility.entries) {
      final feature = MoleculeVisibilityFeature.fromRaw(entry.key);
      if (feature != null) rebuilt[feature] = entry.value;
    }
    if (!mapEquals(rebuilt, visibilityStates)) {
      visibilityStates = rebuilt;
      changed = true;
    }

    // The bridge's own state (objects, selection, errors) changed too; the UI listens to both, so
    // only notify when this controller's state moved.
    if (changed) notifyListeners();
  }

  bool _applyCommandResult(MolStarCommandResult result) {
    if (!result.success) {
      var changed = false;
      // In-flight status is set optimistically and only advanced on success, so a rejected command
      // would otherwise claim "Loading …" forever next to the error banner.
      if (statusMessage.endsWith('…') || statusMessage.startsWith('Loading')) {
        statusMessage = kIdleStatus;
        changed = true;
      }
      // measureKind is set optimistically in toggleMeasure; if JS never entered measure mode (e.g.
      // the command failed before the viewer was ready), clear it so the "tap N atoms" banner does
      // not stick with taps doing nothing.
      if (result.command == MolStarCommand.setMeasureMode && measureKind != null) {
        measureKind = null;
        changed = true;
      }
      return changed;
    }

    switch (result.command) {
      case MolStarCommand.loadLocalStructure:
        statusMessage = 'Loaded ${result.label ?? 'Structure'}';
      case MolStarCommand.loadPdbId:
        statusMessage = 'Loaded ${result.label ?? PdbIdentifier.displayName(pdbText)}';
      case MolStarCommand.setRepresentation:
        statusMessage = '${selectedRepresentation.title} representation';
      case MolStarCommand.surfacePotential:
        statusMessage = 'Electrostatic potential (screened Coulomb)';
      case MolStarCommand.startMorph:
        isMorphing = true;
        statusMessage = 'Morphing';
      case MolStarCommand.stopMorph:
        isMorphing = false;
        statusMessage = 'Morph stopped';
      case MolStarCommand.superpose:
        statusMessage = 'Superposed visible structures';
      case MolStarCommand.secondaryStructure:
        statusMessage = 'Secondary structure (helix/sheet/coil)';
      case MolStarCommand.resetAll:
        statusMessage = 'Reset — everything cleared';
      case MolStarCommand.undo:
        statusMessage = 'Undid last change';
      case MolStarCommand.redo:
        statusMessage = 'Redid last change';
      case MolStarCommand.loadState:
        statusMessage = 'State loaded';
      case MolStarCommand.transientModesStopped:
        // JS is the authority on these: it reports the moment it clears them, so a command that
        // clears and then fails cannot leave the UI claiming a mode the viewer dropped.
        measureKind = null;
        isMorphing = false;
      default:
        return false;
    }
    return true;
  }

  // MARK: - Actions

  void loadPdb() {
    try {
      final pdbId = PdbIdentifier.normalized(pdbText);
      pdbText = pdbId;
      statusMessage = 'Loading $pdbId';
      _beginAction();
      bridge.loadPdbId(pdbId);
      notifyListeners();
    } on PdbIdentifierException catch (error) {
      updateError(error.toString());
    }
  }

  void setRepresentation(MoleculeRepresentation representation) {
    selectedRepresentation = representation;
    _beginAction();
    bridge.setRepresentation(representation.name, targets: visibleStructureNames);
    notifyListeners();
  }

  void toggleVisibility(MoleculeVisibilityFeature feature) {
    final isVisible = !(visibilityStates[feature] ?? true);
    visibilityStates = <MoleculeVisibilityFeature, bool>{...visibilityStates, feature: isVisible};
    _beginAction();
    statusMessage = '${feature.title} ${isVisible ? 'shown' : 'hidden'}';
    bridge.toggleVisibility(feature: feature.name, isVisible: isVisible);
    notifyListeners();
  }

  void toggleMeasure(MeasureKind kind) {
    _beginAction();
    if (measureKind == kind) {
      measureKind = null;
      bridge.setMeasureMode(false);
      statusMessage = 'Measure mode off';
    } else {
      measureKind = kind;
      bridge.setMeasureMode(true, kind: kind.name);
      statusMessage = '${kind.title}: tap ${kind.atomCount} atoms';
    }
    notifyListeners();
  }

  void clearMeasurements() {
    _beginAction();
    bridge.clearMeasurements();
    updateStatus('Measurements cleared');
  }

  void surfacePotential() {
    _beginAction();
    statusMessage = 'Computing surface potential…';
    bridge.drawSurfacePotential(targets: visibleStructureNames);
    notifyListeners();
  }

  void secondaryStructure() {
    _beginAction();
    statusMessage = 'Assigning secondary structure…';
    bridge.computeSecondaryStructure(targets: visibleStructureNames);
    notifyListeners();
  }

  void superpose() {
    _beginAction();
    if (visibleStructureNames.length < 2) {
      updateError('Show at least two structures to superpose.');
      return;
    }
    statusMessage = 'Superposing structures…';
    bridge.superpose(targets: visibleStructureNames);
    notifyListeners();
  }

  void morphToggle() {
    _beginAction();
    if (isMorphing) {
      bridge.stopMorph();
    } else {
      statusMessage = 'Morphing trajectory…';
      bridge.startMorph(loop: false, targets: visibleStructureNames);
    }
    notifyListeners();
  }

  void setBackground(BackgroundPreset preset) {
    _beginAction();
    bridge.setBackgroundColor(preset.hex);
    updateStatus('Background: ${preset.title}');
  }

  void resetAll() {
    _beginAction();
    bridge.resetAll();
    updateStatus('Resetting…');
  }

  // MARK: - File actions

  Future<void> openStructure() async {
    try {
      final structure = await LocalStructureFileLoader.open();
      if (structure == null) return;
      statusMessage = 'Loading ${structure.label}';
      _beginAction();
      bridge.loadLocalStructure(
        data: structure.data,
        format: structure.format,
        label: structure.label,
      );
      notifyListeners();
    } catch (error) {
      updateError(error.toString());
    }
  }

  Future<void> openState() async {
    try {
      final json = await LocalStructureFileLoader.openStateJson();
      if (json == null) return;
      statusMessage = 'Loading state…';
      _beginAction();
      bridge.loadState(json);
      notifyListeners();
    } catch (error) {
      updateError(error.toString());
    }
  }

  Future<void> saveState() async {
    _beginAction();
    if (bridge.objects.isEmpty) {
      updateError('Nothing to save yet.');
      return;
    }
    updateStatus('Capturing state…');
    final json = await bridge.serializeState();
    if (json == null || json.isEmpty) {
      _failAction('Could not capture current state.');
      return;
    }
    try {
      final status = await deliverFile(
        bytes: utf8.encode(json),
        suggestedName: 'molecule.molapp',
        mimeType: 'application/json',
        shareTitle: 'MolApp state',
      );
      updateStatus(status ?? kIdleStatus);
    } catch (error) {
      _failAction(error.toString());
    }
  }

  Future<void> exportImage(ExportFormat format) async {
    _beginAction();
    if (bridge.objects.isEmpty) {
      updateError('Nothing to export yet.');
      return;
    }
    updateStatus('Rendering ${format.title}…');
    final png = await _capturePng();
    if (png == null) return;
    try {
      final status = await deliverFile(
        bytes: await encodeExport(png, format),
        suggestedName: 'molecule.${format.fileExtension}',
        mimeType: format.mimeType,
        shareTitle: 'MolApp ${format.title}',
      );
      // A null status means the user dismissed the save dialog, so there is nothing to announce.
      // Claiming "Exported PNG" for a file that was never written is worse than saying nothing.
      updateStatus(status ?? kIdleStatus);
    } catch (error) {
      _failAction(error.toString());
    }
  }

  Future<void> printDisplay() async {
    _beginAction();
    if (bridge.objects.isEmpty) {
      updateError('Nothing to print yet.');
      return;
    }
    updateStatus('Rendering for print…');
    final png = await _capturePng();
    if (png == null) return;
    try {
      await printImage(png);
      updateStatus(kIdleStatus);
    } catch (error) {
      _failAction(error.toString());
    }
  }

  Future<Uint8List?> _capturePng() async {
    final dataUrl = await bridge.captureImageDataURL();
    final png = dataUrl == null ? null : bytesFromDataUrl(dataUrl);
    if (png == null) {
      _failAction('Could not capture the display.');
      return null;
    }
    return png;
  }

  // MARK: - Command bar

  /// Direct port of the Swift `executeCommand` / Kotlin `ViewerController.executeCommand`.
  void executeCommand() {
    final input = commandText.trim();
    if (input.isEmpty) return;

    commandText = '';
    _beginAction();

    final components =
        input.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    // Object names (PDB IDs, file labels) are stored case-sensitively (uppercase for PDB IDs), so
    // keep an original-case token list for name arguments — only keywords are lowercased.
    final rawComponents = input.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (components.isEmpty) return;
    final command = components.first;

    switch (command) {
      case 'load':
        if (components.length >= 2) {
          pdbText = components[1].toUpperCase();
          loadPdb();
        } else {
          updateError('Usage: load [PDB_ID]');
        }

      case 'repr':
        if (components.length >= 3) {
          final objName = rawComponents.skip(2).join(' ');
          final repr = ObjectRepresentation.fromRawIgnoringCase(components[1]);
          if (repr != null) {
            bridge.setObjectRepresentation(name: objName, representation: repr);
            notifyListeners();
          } else {
            updateError('Invalid representation. Use: '
                '${ObjectRepresentation.values.map((e) => e.name).join(', ')}');
          }
        } else if (components.length >= 2) {
          final repr = MoleculeRepresentation.fromRaw(components[1]);
          if (repr != null) {
            setRepresentation(repr);
          } else {
            updateError('Invalid representation. Use: '
                '${MoleculeRepresentation.values.map((e) => e.name).join(', ')}');
          }
        } else {
          updateError('Usage: repr [ribbon|surface|stick|ballAndStick|sphere] [name?]');
        }

      case 'show':
      case 'hide':
        if (components.length >= 2) {
          final isVisible = command == 'show';
          final feature = MoleculeVisibilityFeature.fromRaw(components[1]);
          if (feature != null) {
            if ((visibilityStates[feature] ?? true) != isVisible) toggleVisibility(feature);
          } else {
            bridge.setObjectVisibility(
              name: rawComponents.skip(1).join(' '),
              isVisible: isVisible,
            );
            notifyListeners();
          }
        } else {
          updateError('Usage: $command [water|ligand|objectname]');
        }

      case 'select':
        final afterSelect = input.length <= 6 ? '' : input.substring(6).trim();
        if (afterSelect.isEmpty) {
          updateError('Usage: select [name] [expression] (e.g. select sele chain A & resn ala)');
        } else {
          final (selectionName, expression) = SelectionExpressionParser.extractName(afterSelect);
          try {
            // Keep original case: the parser lowercases only keyword tokens, so chain IDs (which
            // can be lowercase, e.g. large-assembly auth_asym_id) survive.
            final ast = SelectionExpressionParser(expression).parse();
            bridge.setSelection(MoleculeSelection(
              type: 'expression',
              label: '$selectionName: $expression',
              ast: ast,
            ));
            notifyListeners();
          } on SelectionParseException catch (error) {
            updateError(error.message);
          }
        }

      case 'color':
        if (components.length >= 3) {
          final colorArg = components[1];
          final objName = rawComponents.skip(2).join(' ');
          // Reject an unknown color name instead of silently painting it white: a typo like "gren"
          // must report the usage, not recolor the object indistinguishably from "white".
          // A raw hex is validated for the same reason: hexToMolStarColor in viewer.html is a bare
          // parseInt, so "#12345" reaches Mol* as NaN and paints the object black with no error.
          final String? colorHex;
          if (colorArg == 'default') {
            colorHex = null;
          } else if (_hexPattern.hasMatch(colorArg)) {
            colorHex = colorArg;
          } else if (namedColors.containsKey(colorArg)) {
            colorHex = namedColors[colorArg];
          } else {
            updateError(_colorUsage);
            return;
          }
          bridge.setObjectColor(name: objName, colorHex: colorHex);
          notifyListeners();
        } else {
          updateError(_colorUsage);
        }

      case 'background':
      case 'bg':
        final arg = components.length >= 2 ? components[1] : '';
        String? hex;
        if (arg.startsWith('#')) {
          hex = arg.toUpperCase();
        } else {
          for (final preset in backgroundPresets) {
            if (preset.title.toLowerCase() == arg) {
              hex = preset.hex;
              break;
            }
          }
        }
        if (hex != null && _hexPattern.hasMatch(hex)) {
          bridge.setBackgroundColor(hex);
          updateStatus('Background set');
        } else {
          updateError('Usage: background [dark|black|gray|light|white|#RRGGBB]');
        }

      case 'clear':
        bridge.clearSelection();
        notifyListeners();

      case 'focus':
        bridge.focusSelection();
        notifyListeners();

      case 'surfpot':
      case 'potential':
        surfacePotential();

      case 'ss':
      case 'dssp':
      case 'secstr':
        secondaryStructure();

      case 'super':
      case 'superpose':
      case 'align':
        superpose();

      case 'morph':
        final arg = components.length >= 2 ? components[1] : 'start';
        if (arg == 'stop') {
          bridge.stopMorph();
          notifyListeners();
        } else {
          statusMessage = 'Morphing trajectory…';
          bridge.startMorph(loop: components.contains('loop'), targets: visibleStructureNames);
          notifyListeners();
        }

      case 'measure':
      case 'dist':
        final arg = components.length >= 2 ? components[1] : 'distance';
        switch (arg) {
          case 'clear':
            clearMeasurements();
          case 'off':
            final kind = measureKind;
            if (kind != null) toggleMeasure(kind);
          case 'angle':
            if (measureKind != MeasureKind.angle) toggleMeasure(MeasureKind.angle);
          case 'dihedral':
          case 'torsion':
            if (measureKind != MeasureKind.dihedral) toggleMeasure(MeasureKind.dihedral);
          default:
            if (measureKind != MeasureKind.distance) toggleMeasure(MeasureKind.distance);
        }

      default:
        updateError('Unknown command: $command');
    }

    // The command bar mirrors [commandText], which was cleared above — but several branches are
    // no-ops (re-arming the mode already armed, hiding what is already hidden) and notify nothing,
    // so without this the typed text stays on screen while the run button greys out.
    notifyListeners();
  }

  static final RegExp _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static const String _colorUsage =
      'Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]';
}
