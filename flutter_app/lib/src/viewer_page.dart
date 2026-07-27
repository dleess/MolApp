import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'manual_page.dart';
import 'models.dart';
import 'molstar_bridge.dart';
import 'molstar_web_view.dart';
import 'tokens.dart';
import 'viewer_controller.dart';

class MoleculeViewerPage extends StatefulWidget {
  const MoleculeViewerPage({super.key, this.viewportBuilder});

  /// The Mol* viewport. Overridden by widget tests, which have no platform webview to embed;
  /// everything else in this page is then exercised exactly as it ships.
  final Widget Function(MolStarBridge bridge)? viewportBuilder;

  @override
  State<MoleculeViewerPage> createState() => _MoleculeViewerPageState();
}

class _MoleculeViewerPageState extends State<MoleculeViewerPage> {
  late final MolStarBridge _bridge;
  late final ViewerController _controller;
  final TextEditingController _pdbField = TextEditingController();
  final TextEditingController _commandField = TextEditingController();
  bool _isObjectsPanelExpanded = true;

  @override
  void initState() {
    super.initState();
    _bridge = MolStarBridge();
    _controller = ViewerController(_bridge)..addListener(_syncTextFields);
  }

  /// The controller rewrites both fields on its own (normalising a PDB id, clearing the command
  /// bar after a run), so mirror it back into the editing controllers.
  void _syncTextFields() {
    if (_pdbField.text != _controller.pdbText) {
      _pdbField.value = TextEditingValue(
        text: _controller.pdbText,
        selection: TextSelection.collapsed(offset: _controller.pdbText.length),
      );
    }
    if (_commandField.text != _controller.commandText) {
      _commandField.value = TextEditingValue(
        text: _controller.commandText,
        selection: TextSelection.collapsed(offset: _controller.commandText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncTextFields)
      ..dispose();
    _bridge.dispose();
    _pdbField.dispose();
    _commandField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChromeTokens.viewport,
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_bridge, _controller]),
        child: widget.viewportBuilder?.call(_bridge) ?? MolStarWebView(bridge: _bridge),
        builder: (context, viewport) {
          final isCompact = MediaQuery.sizeOf(context).width < 700;
          final tooltip = _hoverTooltip();
          final banner = _measureBanner();
          // StackFit.expand is load-bearing: Scaffold hands its body loose constraints, and every
          // overlay here is Positioned, so a loose Stack would collapse to zero and the viewport
          // with it.
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              viewport!,
              // The chrome — and only the chrome — is inset. Without this the menu bar's
              // `top: 8` puts it inside the iPhone's 59pt status-bar inset, where the Dynamic
              // Island covers Display outright and the system swallows the taps, and inside the
              // iPadOS window-control pill, which lands on File. The viewport stays full-bleed
              // because it is a 3D scene, and so does the hover tooltip, whose coordinates come
              // from the webview and are therefore in the un-inset space.
              SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _menuBar(isCompact: isCompact),
                    _leftRail(),
                    _commandBar(),
                    ?banner,
                  ],
                ),
              ),
              ?tooltip,
            ],
          );
        },
      ),
    );
  }

  // MARK: - Overlays

  Widget? _hoverTooltip() {
    final label = _bridge.hoverLabel;
    final point = _bridge.hoverPoint;
    if (label == null || point == null) return null;
    return Positioned(
      left: point.dx,
      top: (point.dy - 28).clamp(16.0, double.infinity),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ChromeTokens.scrim,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: ChromeTokens.textPrimary,
              fontSize: ChromeTokens.sizeBody,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _measureBanner() {
    final kind = _controller.measureKind;
    if (kind == null) return null;
    // Name the atoms already armed rather than only counting down. "Remembering" a stale pick was
    // impossible to tell apart from a fresh start while the picks were invisible; spelling them out
    // makes a leftover obvious at a glance, and clicking empty space clears it.
    final picked = _bridge.measurePendingLabels;
    final remaining = kind.atomCount - _bridge.measurePendingCount;
    final text = picked.isEmpty
        ? '${kind.title} mode — pick ${kind.atomCount} atoms'
        : '${kind.title} mode — ${picked.join(', ')} '
            '(pick $remaining more)';
    return Positioned(
      // Rides under the menu bar, which moves on iPad. Left absolute it painted straight over the
      // menu labels there — the banner is the last child of this Stack, so it wins the paint.
      top: _menuBarTop(context) + 52,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ChromeTokens.banner,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.straighten, size: 14, color: ChromeTokens.textPrimary),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: ChromeTokens.textPrimary,
                    fontSize: ChromeTokens.sizeBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Menu bar

  Widget _menuBar({required bool isCompact}) {
    // A wide window has room for all six menus in a row; a narrow one does not, so scroll them
    // horizontally instead of letting the row overflow and clip.
    final menus = <Widget>[
      _fileMenu(),
      _editMenu(),
      _displayMenu(),
      _calculationMenu(),
      _measureMenu(),
      _helpMenu(),
    ];

    return Positioned(
      top: _menuBarTop(context),
      left: 0,
      right: 0,
      child: Container(
        color: ChromeTokens.scrim,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: isCompact
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: menus),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 16, right: 14),
                child: Row(children: menus),
              ),
      ),
    );
  }

  /// iPadOS 26 floats its window-control pill *inside* the app's own content at the top-leading
  /// corner and does not report it as a safe-area inset — measured on the simulator, `padding.left`
  /// stays 0 and `padding.top` is only ~11pt, and the pill grows to cover File and Edit outright
  /// the moment it is touched. Flutter surfaces no inset for it (`MediaQueryData` has no such
  /// field), so the row has to step below it on its own. The *display* size identifies an iPad,
  /// not `MediaQuery.sizeOf`, which in windowed mode reports the window and can be phone-sized.
  ///
  /// 56 is measured, not guessed: the pill grows on touch to window-relative y 10..51.5pt, and the
  /// safe-area top there is only ~9pt, so anything under 43 puts the row back under the expanded
  /// pill. On a full-screen iPad the pill is hidden and this is dead space at the top instead.
  static double _menuBarTop(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return 8;
    final display = View.of(context).display;
    final isTablet = display.size.shortestSide / display.devicePixelRatio >= 600;
    return isTablet ? 56 : 8;
  }

  Widget _menuButton(String title, List<Widget> children) {
    return MenuAnchor(
      menuChildren: children,
      builder: (context, controller, child) => TextButton(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          foregroundColor: ChromeTokens.textPrimary,
          textStyle: const TextStyle(fontSize: ChromeTokens.sizeMenu, fontWeight: FontWeight.w600),
        ),
        child: Text(title),
      ),
    );
  }

  MenuItemButton _item(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(icon, size: 18, color: destructive ? ChromeTokens.destructive : null),
      style: destructive ? MenuItemButton.styleFrom(foregroundColor: ChromeTokens.destructive) : null,
      child: Text(label),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: ChromeTokens.sizeSmall,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _fileMenu() {
    final hasObjects = _bridge.objects.isNotEmpty;
    return _menuButton('File', <Widget>[
      _item('Open Structure', Icons.folder_open, _controller.openStructure),
      _item(
        'Load PDB ID',
        Icons.download_outlined,
        _controller.pdbText.trim().isEmpty ? null : _controller.loadPdb,
      ),
      const Divider(height: 8),
      _item('Save State (.molapp)', Icons.save_outlined, hasObjects ? _controller.saveState : null),
      _item('Open State (.molapp)', Icons.folder_special_outlined, _controller.openState),
      const Divider(height: 8),
      SubmenuButton(
        leadingIcon: const Icon(Icons.image_outlined, size: 18),
        menuChildren: <Widget>[
          for (final format in ExportFormat.values)
            MenuItemButton(
              onPressed: hasObjects ? () => _controller.exportImage(format) : null,
              child: Text(format.title),
            ),
        ],
        child: const Text('Export Display'),
      ),
      _item('Print', Icons.print_outlined, hasObjects ? _controller.printDisplay : null),
      const Divider(height: 8),
      _item('Reset All', Icons.restart_alt, _controller.resetAll, destructive: true),
    ]);
  }

  Widget _editMenu() {
    return _menuButton('Edit', <Widget>[
      _item('Undo', Icons.undo, () {
        _controller.clearError();
        _bridge.undo();
      }),
      _item('Redo', Icons.redo, () {
        _controller.clearError();
        _bridge.redo();
      }),
      const Divider(height: 8),
      _item('Clear Selection', Icons.highlight_off, () {
        _controller.clearError();
        _bridge.clearSelection();
      }),
    ]);
  }

  Widget _displayMenu() {
    final canRepresent = _controller.visibleStructureNames.isNotEmpty;
    return _menuButton('Display', <Widget>[
      _sectionLabel('Representation'),
      for (final representation in MoleculeRepresentation.values)
        _item(
          representation.title,
          representation.icon,
          canRepresent ? () => _controller.setRepresentation(representation) : null,
        ),
      _sectionLabel('Visibility'),
      for (final feature in MoleculeVisibilityFeature.values)
        _item(
          '${(_controller.visibilityStates[feature] ?? true) ? 'Hide' : 'Show'} ${feature.title}',
          feature.icon,
          () => _controller.toggleVisibility(feature),
        ),
      _sectionLabel('Background'),
      for (final preset in backgroundPresets)
        MenuItemButton(
          onPressed: () => _controller.setBackground(preset),
          leadingIcon: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: colorFromHex(preset.hex),
              border: Border.all(color: ChromeTokens.presetSwatchBorder),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          child: Text(preset.title),
        ),
    ]);
  }

  Widget _calculationMenu() {
    final visible = _controller.visibleStructureNames;
    return _menuButton('Calculation', <Widget>[
      _item(
        'Surface Potential',
        Icons.bolt_outlined,
        visible.isEmpty ? null : _controller.surfacePotential,
      ),
      _item(
        'Secondary Structure',
        Icons.show_chart,
        visible.isEmpty ? null : _controller.secondaryStructure,
      ),
      _item(
        'Superpose Visible',
        Icons.filter_none,
        visible.length < 2 ? null : _controller.superpose,
      ),
      _sectionLabel('Morph'),
      _item(
        _controller.isMorphing ? 'Stop Morph' : 'Start Morph',
        _controller.isMorphing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
        !_controller.isMorphing && visible.isEmpty ? null : _controller.morphToggle,
      ),
    ]);
  }

  Widget _measureMenu() {
    return _menuButton('Measure', <Widget>[
      for (final kind in MeasureKind.values)
        _item(
          '${kind.title} Mode',
          _controller.measureKind == kind ? Icons.straighten : Icons.straighten_outlined,
          () => _controller.toggleMeasure(kind),
        ),
      _item('Clear Measurements', Icons.delete_outline, _controller.clearMeasurements),
    ]);
  }

  Widget _helpMenu() {
    return _menuButton('Help', <Widget>[
      _item('Manual', Icons.menu_book_outlined, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ManualPage()),
        );
      }),
      _item('Quick Help', Icons.help_outline, () {
        _controller.updateStatus('Open a PDB/mmCIF file or enter a PDB ID');
      }),
    ]);
  }

  /// The info card and the objects panel share one column so they cannot overlap.
  ///
  /// They used to be anchored independently — the card from the top, the panel from the bottom —
  /// which reads fine on a tall phone and collides by 88pt on a rotated one, the panel painting
  /// over Open Structure, the PDB field and Load PDB. minHeight makes the column fill the rail
  /// whenever there is room, so spaceBetween reproduces the old positions exactly; when there is
  /// not room the column takes its natural height and the rail scrolls instead of overlapping.
  ///
  /// `top` hangs off the menu bar rather than the screen so the iPad's extra offset carries
  /// through instead of letting the bar clip the card's top corners.
  Widget _leftRail() {
    return Positioned(
      left: 16,
      top: _menuBarTop(context) + 92,
      bottom: 120,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _infoCard(),
                _objectsPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Info card

  Widget _infoCard() {
    final error = _controller.errorMessage;
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChromeTokens.scrim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Molecule Viewer',
            style: TextStyle(
              color: ChromeTokens.textPrimary,
              fontSize: ChromeTokens.sizeTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _controller.statusMessage,
            style: TextStyle(color: ChromeTokens.textSecondary, fontSize: ChromeTokens.sizeStatus),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _controller.openStructure,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open Structure'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 108,
                height: 38,
                child: TextField(
                  controller: _pdbField,
                  onChanged: _controller.setPdbText,
                  onSubmitted: (_) => _controller.loadPdb(),
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(4),
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  ],
                  style: const TextStyle(
                    color: ChromeTokens.textPrimary,
                    fontSize: ChromeTokens.sizeField,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'PDB ID',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _controller.pdbText.trim().isEmpty ? null : _controller.loadPdb,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Load PDB'),
                style: OutlinedButton.styleFrom(foregroundColor: ChromeTokens.textPrimary),
              ),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: ChromeTokens.error, fontSize: ChromeTokens.sizeBody),
            ),
          ],
        ],
      ),
    );
  }

  // MARK: - Objects panel

  Widget _objectsPanel() {
    final objects = _bridge.objects;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ChromeTokens.scrim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _isObjectsPanelExpanded = !_isObjectsPanelExpanded),
            child: Row(
              children: <Widget>[
                const Icon(Icons.layers_outlined, size: 16, color: ChromeTokens.textPrimary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Objects',
                    style: TextStyle(
                      color: ChromeTokens.textPrimary,
                      fontSize: ChromeTokens.sizeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _isObjectsPanelExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: ChromeTokens.textPrimary,
                ),
              ],
            ),
          ),
          if (_isObjectsPanelExpanded)
            if (objects.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No objects',
                  style: TextStyle(
                    color: ChromeTokens.textSecondary,
                    fontSize: ChromeTokens.sizeSmall,
                  ),
                ),
              )
            else
              ConstrainedBox(
                // The panel is an overlay on the viewport; a long ligand list must scroll inside
                // it rather than push the command bar off screen.
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final object in objects) ...<Widget>[
                        _objectRow(object),
                        if (object != objects.last)
                          Divider(height: 10, color: ChromeTokens.hairline),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _objectRow(MolAppObject object) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                onTap: () => _bridge.setObjectVisibility(
                  name: object.name,
                  isVisible: !object.isVisible,
                ),
                child: Icon(
                  object.isVisible ? Icons.visibility : Icons.visibility_off,
                  size: 15,
                  color: object.isVisible ? ChromeTokens.textPrimary : ChromeTokens.textDisabled,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      object.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ChromeTokens.textPrimary,
                        fontSize: ChromeTokens.sizeBody,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      object.type.name,
                      style: TextStyle(
                        color: ChromeTokens.textSecondary,
                        fontSize: ChromeTokens.sizeMicro,
                      ),
                    ),
                  ],
                ),
              ),
              _colorSwatch(object),
            ],
          ),
          const SizedBox(height: 5),
          // Wrap, not Row: five labels plus their padding are a hair wider than the panel's 200pt
          // of content at the default text scale, and wider still when the user scales text up.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final repr in ObjectRepresentation.values)
                InkWell(
                  onTap: () => _bridge.setObjectRepresentation(
                    name: object.name,
                    representation: repr,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(
                      color: object.representation == repr
                          ? ChromeTokens.chipSelectedFill
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      repr.shortTitle,
                      style: TextStyle(
                        fontSize: ChromeTokens.sizeMicro,
                        fontWeight: FontWeight.w500,
                        color: object.representation == repr
                            ? ChromeTokens.textPrimary
                            : ChromeTokens.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(MolAppObject object) {
    return MenuAnchor(
      menuChildren: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Color',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: ChromeTokens.sizeBody),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final key in colorPickerKeys)
                      _colorDot(
                        object.name,
                        key,
                        key == 'default' ? null : namedColors[key],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: object.swatchColor,
            shape: BoxShape.circle,
            border: Border.all(color: ChromeTokens.dotBorder, width: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _colorDot(String objectName, String key, String? hex) {
    return Tooltip(
      message: key,
      child: InkWell(
        onTap: () {
          _bridge.setObjectColor(name: objectName, colorHex: hex);
          Navigator.of(context, rootNavigator: false).maybePop();
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: colorFromHex(hex) ?? ChromeTokens.dotFallback,
            shape: BoxShape.circle,
            border: Border.all(color: ChromeTokens.dotBorder, width: 0.5),
          ),
        ),
      ),
    );
  }

  // MARK: - Command bar

  Widget _commandBar() {
    final hasText = _controller.commandText.trim().isNotEmpty;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ChromeTokens.scrim,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ChromeTokens.hairline),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.terminal, size: 18, color: ChromeTokens.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commandField,
                  onChanged: _controller.setCommandText,
                  onSubmitted: (_) => _controller.executeCommand(),
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    color: ChromeTokens.textPrimary,
                    fontSize: ChromeTokens.sizeField,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter command (e.g. load 1crn, repr surface)...',
                    hintStyle: TextStyle(
                      color: ChromeTokens.textSecondary,
                      fontSize: ChromeTokens.sizeField,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  onPressed: () => _controller.setCommandText(''),
                  icon: Icon(Icons.cancel, size: 18, color: ChromeTokens.textSecondary),
                  tooltip: 'Clear',
                ),
              IconButton(
                onPressed: hasText ? _controller.executeCommand : null,
                icon: Icon(
                  Icons.arrow_circle_up,
                  size: 22,
                  color: hasText ? ChromeTokens.accent : ChromeTokens.textDisabled,
                ),
                tooltip: 'Run command',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
