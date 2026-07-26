import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Commands the native side sends to `window.molapp.handleNativeCommand` in viewer.html.
enum MolStarCommand {
  loadLocalStructure,
  loadPdbId,
  setRepresentation,
  toggleVisibility,
  focusSelection,
  setSelection,
  clearSelection,
  setObjectVisibility,
  setObjectRepresentation,
  setObjectColor,
  setBackgroundColor,
  surfacePotential,
  startMorph,
  stopMorph,
  superpose,
  secondaryStructure,
  setMeasureMode,
  clearMeasurements,
  resetAll,
  undo,
  redo,
  loadState,

  /// Posted by JS whenever it clears measure/morph mode, independent of the command that triggered
  /// it: a command can clear these and then fail, so success is not a reliable signal.
  transientModesStopped;

  static MolStarCommand? fromRaw(String? raw) => raw == null ? null : values.asNameMap()[raw];
}

@immutable
class MolStarCommandResult {
  const MolStarCommandResult({
    required this.id,
    required this.success,
    this.command,
    this.error,
    this.label,
  });

  final String id;
  final bool success;

  /// Null when JS reported a command name this build does not know.
  final MolStarCommand? command;
  final String? error;
  final String? label;

  static MolStarCommandResult fromJson(Map<String, dynamic> json) {
    return MolStarCommandResult(
      id: json['id'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      command: MolStarCommand.fromRaw(json['command'] as String?),
      error: json['error'] as String?,
      label: json['label'] as String?,
    );
  }
}

/// The JS side of the viewer, as the bridge needs it. Implemented per webview backend so the
/// bridge itself stays platform-free and unit-testable.
abstract class MolStarJsRunner {
  /// Fire-and-forget evaluation. Errors surface through [MolStarBridge.lastErrorMessage].
  Future<void> evaluate(String source);

  /// Awaited evaluation used by the two request/response calls (state + image capture).
  /// [source] is an async function body that returns a value.
  Future<Object?> callAsync(String source);
}

/// Transport and viewer-derived state: the Dart port of `MolStarBridge.swift`.
///
/// Commands are fire-and-forget through a serial script queue; JS answers with command results and
/// unsolicited events, both of which arrive at [receiveMessage].
class MolStarBridge extends ChangeNotifier {
  MolStarJsRunner? _runner;

  final List<String> _pendingScripts = <String>[];
  bool _isViewerReady = false;

  /// The viewer never came up at all (fatal init failure). Distinct from `!isViewerReady`, which is
  /// the normal "still booting" state that [_pendingScripts] exists to cover.
  bool _isViewerFatal = false;

  MolStarCommandResult? _lastCommandResult;
  String? _lastErrorMessage;
  MoleculeSelection? _currentSelection;
  List<MolAppObject> _objects = <MolAppObject>[];
  String? _hoverLabel;
  Offset? _hoverPoint;
  String? _lastMeasurement;
  int _measurementSeq = 0;
  int _measurePendingCount = 0;
  int _measureTargetCount = 2;
  List<String> _measurePendingLabels = const <String>[];
  Map<String, bool> _featureVisibility = <String, bool>{};

  bool get isViewerReady => _isViewerReady;
  bool get isViewerFatal => _isViewerFatal;
  MolStarCommandResult? get lastCommandResult => _lastCommandResult;
  String? get lastErrorMessage => _lastErrorMessage;
  MoleculeSelection? get currentSelection => _currentSelection;
  List<MolAppObject> get objects => List<MolAppObject>.unmodifiable(_objects);

  /// Stylus/mouse hover: the label comes from JS (Mol* hover), the point from the native hover
  /// handler. The tooltip shows only when both are present.
  String? get hoverLabel => _hoverLabel;
  Offset? get hoverPoint => _hoverPoint;

  /// Last completed measurement, as "atomA — atomB" (the value itself is drawn on the canvas).
  String? get lastMeasurement => _lastMeasurement;

  /// Bumped once per measurement event. Labels omit the model number and are null for unnamed
  /// atoms, so two genuinely different measurements can carry the same text — listeners must key
  /// off this counter rather than comparing labels, or the second one is silently swallowed.
  int get measurementSeq => _measurementSeq;

  /// Atoms already picked for the measurement being built, out of [measureTargetCount]. The pick
  /// marks are easy to miss on a large structure, so without this the armed atoms are invisible
  /// state and a leftover pick reads as the app remembering something the user thought they had
  /// left behind. Labels are null for unnamed atoms, hence [String] entries only.
  int get measurePendingCount => _measurePendingCount;
  int get measureTargetCount => _measureTargetCount;
  List<String> get measurePendingLabels => List<String>.unmodifiable(_measurePendingLabels);

  /// Feature (water/ligand/protein) visibility JS changed on its own (e.g. Surface auto-hides
  /// water); the UI observes this to keep its Display ▸ Visibility toggles in sync.
  Map<String, bool> get featureVisibility => Map<String, bool>.unmodifiable(_featureVisibility);

  /// Structures the user has left visible (eye-on) in the Objects panel. Global actions
  /// (representation, surface potential, morph) are scoped to this list so loading multiple PDBs
  /// and hiding some restricts actions to the ones still shown.
  List<String> get visibleStructureNames => _objects
      .where((o) => o.type == MolAppObjectType.structure && o.isVisible)
      .map((o) => o.name)
      .toList();

  /// Binds a freshly loaded page. Readiness is reset here rather than at the call sites: this is
  /// the one path every load and reload routes through, so the flag can never outlive its page.
  void attach(MolStarJsRunner runner) {
    _runner = runner;
    _isViewerReady = false;
    _isViewerFatal = false;
    notifyListeners();
  }

  void detach() {
    _runner = null;
    _isViewerReady = false;
  }

  void updateHoverPoint(Offset? point) {
    _hoverPoint = point;
    if (point == null && _hoverLabel != null) _hoverLabel = null;
    notifyListeners();
  }

  void clearError() {
    if (_lastErrorMessage == null) return;
    _lastErrorMessage = null;
    notifyListeners();
  }

  void reportError(String? message) {
    _lastErrorMessage = message;
    notifyListeners();
  }

  // MARK: - Commands

  void loadLocalStructure({required String data, required String format, String? label}) {
    _send(MolStarCommand.loadLocalStructure, <String, dynamic>{
      'data': data,
      'format': format,
      'label': ?label,
    });
  }

  void loadPdbId(String pdbId) {
    _send(MolStarCommand.loadPdbId, <String, dynamic>{'pdbId': pdbId});
  }

  void setRepresentation(String representation, {List<String> targets = const <String>[]}) {
    _send(MolStarCommand.setRepresentation, <String, dynamic>{
      'representation': representation,
      'targets': targets,
    });
  }

  void toggleVisibility({required String feature, required bool isVisible}) {
    _send(MolStarCommand.toggleVisibility, <String, dynamic>{
      'feature': feature,
      'isVisible': isVisible,
    });
  }

  void focusSelection() => _send(MolStarCommand.focusSelection, const <String, dynamic>{});

  void setSelection(MoleculeSelection selection) {
    _send(MolStarCommand.setSelection, selection.toJson());
  }

  void clearSelection() => _send(MolStarCommand.clearSelection, const <String, dynamic>{});

  /// Idempotent by name, so a re-split after a representation change will not duplicate a row.
  void addObject(MolAppObject object) {
    final index = _objects.indexWhere((o) => o.name == object.name);
    if (index >= 0) {
      _objects[index] = object;
    } else {
      _objects = <MolAppObject>[..._objects, object];
    }
    notifyListeners();
  }

  void setObjectVisibility({required String name, required bool isVisible}) {
    _send(MolStarCommand.setObjectVisibility, <String, dynamic>{
      'name': name,
      'isVisible': isVisible,
    });
  }

  void setObjectRepresentation({required String name, required ObjectRepresentation representation}) {
    _send(MolStarCommand.setObjectRepresentation, <String, dynamic>{
      'name': name,
      'representation': representation.name,
    });
  }

  void setObjectColor({required String name, required String? colorHex}) {
    _send(MolStarCommand.setObjectColor, <String, dynamic>{
      'name': name,
      // Sent explicitly as null: viewer.html treats null and undefined alike (reset to chain-id),
      // so keeping the key makes the "clear the color" intent legible on the wire.
      'colorHex': colorHex,
    });
  }

  void setBackgroundColor(String colorHex) {
    _send(MolStarCommand.setBackgroundColor, <String, dynamic>{'colorHex': colorHex});
  }

  void drawSurfacePotential({List<String> targets = const <String>[]}) {
    _send(MolStarCommand.surfacePotential, <String, dynamic>{'targets': targets});
  }

  void startMorph({
    double durationInS = 5,
    bool loop = false,
    List<String> targets = const <String>[],
  }) {
    _send(MolStarCommand.startMorph, <String, dynamic>{
      'durationInS': durationInS,
      'loop': loop,
      'targets': targets,
    });
  }

  void stopMorph() => _send(MolStarCommand.stopMorph, const <String, dynamic>{});

  void superpose({List<String> targets = const <String>[]}) {
    _send(MolStarCommand.superpose, <String, dynamic>{'targets': targets});
  }

  void computeSecondaryStructure({List<String> targets = const <String>[]}) {
    _send(MolStarCommand.secondaryStructure, <String, dynamic>{'targets': targets});
  }

  void setMeasureMode(bool enabled, {String? kind}) {
    _send(MolStarCommand.setMeasureMode, <String, dynamic>{
      'enabled': enabled,
      'kind': ?kind,
    });
  }

  void clearMeasurements() => _send(MolStarCommand.clearMeasurements, const <String, dynamic>{});

  void resetAll() => _send(MolStarCommand.resetAll, const <String, dynamic>{});

  void undo() => _send(MolStarCommand.undo, const <String, dynamic>{});

  void redo() => _send(MolStarCommand.redo, const <String, dynamic>{});

  void loadState(String json) {
    _send(MolStarCommand.loadState, <String, dynamic>{'json': json});
  }

  // Request/response (not fire-and-forget): the caller needs the returned value, so these bypass
  // the serial script queue and await the JS result directly.

  Future<String?> serializeState() async {
    final runner = _runner;
    if (runner == null) return null;
    try {
      final result = await runner.callAsync(
        'return (window.molapp && window.molapp.serializeMolAppState)'
        ' ? await window.molapp.serializeMolAppState() : null;',
      );
      return result as String?;
    } catch (error) {
      reportError(error.toString());
      return null;
    }
  }

  Future<String?> captureImageDataURL() async {
    final runner = _runner;
    if (runner == null) return null;
    try {
      final result = await runner.callAsync('return await window.molapp.captureImageDataURL();');
      return result as String?;
    } catch (error) {
      reportError(error.toString());
      return null;
    }
  }

  /// Stylus/mouse hover position, forwarded so Mol* can report what is under the cursor.
  Future<void> sendHover(double x, double y) async {
    await _runner?.evaluate('window.molapp?.handlePencilHover?.($x, $y);');
  }

  Future<void> sendHoverEnd() async {
    await _runner?.evaluate('window.molapp?.handlePencilHoverEnd?.();');
  }

  /// Trackpad/mouse-wheel and pinch zoom, forwarded as a relative scale the way the iPad pinch
  /// recognizer did. Mol*'s own wheel handling covers the plain-scroll case.
  Future<void> sendPinch(double scale, double x, double y) async {
    await _runner?.evaluate('window.molapp?.handleNativePinch?.($scale, $x, $y);');
  }

  void _send(MolStarCommand command, Map<String, dynamic> payload) {
    final String json;
    try {
      json = jsonEncode(<String, dynamic>{
        'id': _nextCommandId(),
        'command': command.name,
        'payload': payload,
      });
    } catch (error) {
      reportError('Unable to encode ${command.name} command.');
      return;
    }
    _enqueueScript('window.molapp.handleNativeCommand($json); void 0;');
  }

  var _commandCounter = 0;
  String _nextCommandId() => 'cmd-${_commandCounter++}-${DateTime.now().microsecondsSinceEpoch}';

  void _enqueueScript(String script) {
    // Queueing against a viewer that never booted grows without bound: loadLocalStructure embeds
    // the whole structure file in the script, and nothing will ever drain it.
    if (_isViewerFatal) return;
    _pendingScripts.add(script);
    _flushPendingScripts();
  }

  void _flushPendingScripts() {
    final runner = _runner;
    if (!_isViewerReady || _pendingScripts.isEmpty || runner == null) return;
    final scripts = List<String>.of(_pendingScripts);
    _pendingScripts.clear();
    for (final script in scripts) {
      runner.evaluate(script).catchError((Object error) {
        reportError(error.toString());
      });
    }
  }

  // MARK: - Inbound events

  /// Entry point for everything JS posts back, whether a command result or an unsolicited event.
  void receiveMessage(Map<String, dynamic> message) {
    final event = message['event'];

    if (event == 'viewerReady') {
      _isViewerReady = true;
      _lastErrorMessage = null;
      _flushPendingScripts();
      notifyListeners();
      return;
    }

    if (event == 'viewerError') {
      if (message['fatal'] == true) {
        _isViewerReady = false;
        _isViewerFatal = true;
        _pendingScripts.clear();
      }
      _lastErrorMessage = message['message'] as String? ?? 'Mol* viewer error.';
      notifyListeners();
      return;
    }

    if (event == 'selectionChanged') {
      _currentSelection = MoleculeSelection.fromJson(
        (message['selection'] as Map?)?.cast<String, dynamic>(),
      );
      notifyListeners();
      return;
    }

    if (event == 'pencilHover') {
      final label = message['label'] as String?;
      if (_hoverLabel != label) {
        _hoverLabel = label;
        notifyListeners();
      }
      return;
    }

    if (event == 'measurement') {
      _lastMeasurement = message['label'] as String?;
      _measurementSeq += 1;
      notifyListeners();
      return;
    }

    if (event == 'measurePending') {
      final labels = <String>[
        for (final raw in (message['labels'] as List?) ?? const <Object?>[])
          if (raw is String) raw,
      ];
      final count = (message['count'] as num?)?.toInt() ?? 0;
      final target = (message['target'] as num?)?.toInt() ?? 2;
      if (count != _measurePendingCount ||
          target != _measureTargetCount ||
          !listEquals(labels, _measurePendingLabels)) {
        _measurePendingCount = count;
        _measureTargetCount = target;
        _measurePendingLabels = labels;
        notifyListeners();
      }
      return;
    }

    // JS split a structure's ligands into per-residue objects (e.g. NAP/JBC/SO4). Surface each as a
    // selection object so it gets its own eye/representation/color row in the Objects panel.
    if (event == 'objectsAdded') {
      final list = message['objects'];
      if (list is List) {
        for (final raw in list) {
          if (raw is! Map) continue;
          final name = raw['name'];
          if (name is! String) continue;
          addObject(MolAppObject(
            name: name,
            type: MolAppObjectType.selection,
            representation: _representationOf(raw) ?? ObjectRepresentation.ballAndStick,
          ));
        }
      }
      return;
    }

    // The master Ligand toggle changes per-ligand visibility in JS; mirror it onto the rows so the
    // panel eye icons follow (they are separate controls from the master toggle).
    if (event == 'objectsVisibility') {
      final list = message['items'];
      if (list is List) {
        var changed = false;
        for (final raw in list) {
          if (raw is! Map) continue;
          final name = raw['name'];
          final isVisible = raw['isVisible'];
          if (name is! String || isVisible is! bool) continue;
          final index = _objects.indexWhere((o) => o.name == name);
          if (index >= 0) {
            _objects[index] = _objects[index].copyWith(isVisible: isVisible);
            changed = true;
          }
        }
        if (changed) notifyListeners();
      }
      return;
    }

    // JS auto-changed a feature toggle (e.g. Surface hides water); mirror it so the menu label
    // ("Show/Hide Water") stays truthful.
    if (event == 'featureVisibility') {
      final feature = message['feature'];
      final isVisible = message['isVisible'];
      if (feature is String && isVisible is bool) {
        _featureVisibility = <String, bool>{..._featureVisibility, feature: isVisible};
        notifyListeners();
      }
      return;
    }

    // Undo/redo/reset rebuilt the JS scene; replace the whole panel from the restored state.
    if (event == 'objectsReplaced') {
      final list = message['objects'];
      if (list is List) {
        final rebuilt = <MolAppObject>[];
        for (final raw in list) {
          if (raw is! Map) continue;
          final name = raw['name'];
          final typeRaw = raw['type'];
          if (name is! String || typeRaw is! String) continue;
          final type = switch (typeRaw) {
            'structure' => MolAppObjectType.structure,
            'selection' => MolAppObjectType.selection,
            _ => null,
          };
          if (type == null) continue;
          rebuilt.add(MolAppObject(
            name: name,
            type: type,
            isVisible: raw['isVisible'] as bool? ?? true,
            representation: _representationOf(raw) ??
                (type == MolAppObjectType.structure
                    ? ObjectRepresentation.ribbon
                    : ObjectRepresentation.ballAndStick),
            colorHex: raw['colorHex'] is String ? raw['colorHex'] as String : null,
          ));
        }
        _objects = rebuilt;
        final visibility = message['visibility'];
        if (visibility is Map) {
          _featureVisibility = visibility.map(
            (key, value) => MapEntry(key as String, value as bool),
          );
        }
        notifyListeners();
      }
      return;
    }

    _receiveResult(MolStarCommandResult.fromJson(message));
  }

  /// `.molapp` state files are user-editable and viewer.html echoes their object metadata straight
  /// back, so these fields are type-checked here the same way `name` and `type` already are —
  /// a bare `as String?` on a hand-edited file throws inside the message handler.
  static ObjectRepresentation? _representationOf(Map<dynamic, dynamic> raw) {
    final value = raw['representation'];
    return value is String ? ObjectRepresentation.fromRaw(value) : null;
  }

  void _receiveResult(MolStarCommandResult result) {
    _lastCommandResult = result;
    _lastErrorMessage = result.success ? null : result.error;
    notifyListeners();
  }
}
