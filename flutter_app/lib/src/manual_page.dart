import 'package:flutter/material.dart';

class _ManualCommand {
  const _ManualCommand(this.syntax, this.detail);

  final String syntax;
  final String detail;
}

class _ManualSection {
  const _ManualSection({
    required this.title,
    required this.icon,
    required this.body,
    this.commands = const <_ManualCommand>[],
  });

  final String title;
  final IconData icon;
  final String body;
  final List<_ManualCommand> commands;
}

const List<_ManualSection> _sections = <_ManualSection>[
  _ManualSection(
    title: 'Loading structures',
    icon: Icons.download_outlined,
    body: 'Open a local PDB/mmCIF file with File ▸ Open Structure, or fetch from the RCSB by '
        'entering a 4-character PDB ID and pressing Load PDB. Multiple structures can be loaded at '
        'once — each appears in the Objects panel.',
    commands: <_ManualCommand>[
      _ManualCommand('load 1UBQ', 'Fetch and display a PDB entry by ID'),
    ],
  ),
  _ManualSection(
    title: 'Saving & exporting',
    icon: Icons.upload_outlined,
    body: 'File ▸ Save State writes the whole session — every structure, selection, color, '
        'representation and visibility — to a .molapp file; File ▸ Open State restores it. '
        'Structures loaded from the RCSB are re-fetched on open, so restoring those needs a network '
        'connection. File ▸ Export Display saves a snapshot of the current view as PNG, JPEG, GIF, '
        'SVG or PDF, and File ▸ Print sends it to a printer. File ▸ Reset All clears everything back '
        'to an empty viewer.',
  ),
  _ManualSection(
    title: 'Undo & redo',
    icon: Icons.undo,
    body: 'Edit ▸ Undo and Edit ▸ Redo step backward and forward through changes — loading, hiding, '
        'recoloring, representation switches and state loads are all reversible (up to 25 steps). '
        'Edit ▸ Clear Selection drops the active selection without removing its named object.',
  ),
  _ManualSection(
    title: 'Objects panel',
    icon: Icons.layers_outlined,
    body: 'Every loaded structure and named selection is listed at the bottom-left. The eye toggles '
        "a structure's visibility. The colored dot opens a color picker. The Rib / Sur / Stk / B+S / "
        "Sph buttons switch that object's representation. Display ▸ Visibility toggles protein, "
        'water and ligand across the whole scene. Calculation and Display actions apply only to the '
        'structures currently shown (eye on).',
    commands: <_ManualCommand>[
      _ManualCommand('show NAME / hide NAME', 'Show or hide an object (or protein / water / ligand)'),
      _ManualCommand('repr surface NAME', "Set an object's representation"),
      _ManualCommand('color red NAME', "Recolor an object (or 'default')"),
    ],
  ),
  _ManualSection(
    title: 'Background',
    icon: Icons.palette_outlined,
    body: 'Display ▸ Background sets the viewport background color — Dark, Black, Gray, Light or '
        'White. A light background is handy for presentation slides or printing.',
    commands: <_ManualCommand>[
      _ManualCommand(
        'background white',
        'Set the viewport background (dark / black / gray / light / white, or #RRGGBB)',
      ),
    ],
  ),
  _ManualSection(
    title: 'Selections',
    icon: Icons.highlight_alt,
    body: 'Build a named selection from an expression. Combine terms with & (and), | (or), ! (not) '
        'and parentheses. Click an atom in the viewport to select it; double-click to focus.',
    commands: <_ManualCommand>[
      _ManualCommand('select sele chain A & resn ALA', 'Name a selection from an expression'),
      _ManualCommand('res 10-25 · residue 42 · atom CA', 'Residue range, single residue, atom name'),
      _ManualCommand('clear · focus', 'Clear the selection · frame it in view'),
    ],
  ),
  _ManualSection(
    title: 'Calculation',
    icon: Icons.functions,
    body: 'Analyses run on the visible structures. Surface Potential draws a molecular surface '
        'colored by a screened-Coulomb (APBS-like) electrostatic potential. Secondary Structure '
        'assigns helix / sheet / coil (DSSP when the model has none) and colors a cartoon. '
        'Superpose aligns visible structures onto the first by sequence alignment plus iterative Cα '
        'fitting — sequences need not match. Morph animates through the models of a multi-model '
        'structure (NMR ensemble / trajectory).',
    commands: <_ManualCommand>[
      _ManualCommand('surfpot', 'Electrostatic potential surface'),
      _ManualCommand('ss', 'Secondary structure (DSSP) coloring'),
      _ManualCommand('super', 'Superpose the visible structures'),
      _ManualCommand('morph · morph stop', 'Start / stop trajectory morph'),
    ],
  ),
  _ManualSection(
    title: 'Measure',
    icon: Icons.straighten,
    body: 'Pick a mode under Measure ▸ Distance / Angle / Dihedral, then click 2 / 3 / 4 atoms (or '
        'tap with the Apple Pencil or a finger) to draw the measurement — distance in ångströms, '
        'angle and dihedral in degrees. Keep picking sets to add more. A blue banner shows while '
        'measuring; Clear Measurements removes them all.',
    commands: <_ManualCommand>[
      _ManualCommand(
        'measure · measure angle · measure dihedral',
        'Enter distance / angle / dihedral mode',
      ),
      _ManualCommand(
        'measure off · measure clear',
        'Leave measure mode · remove all measurements',
      ),
    ],
  ),
];

class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'MolApp is a molecular structure viewer built on Mol*. Use the menu bar, the Objects '
            'panel, or the command line at the bottom of the window.',
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: 22),
          for (final section in _sections) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(section.icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(section.title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              section.body,
              style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
            ),
            if (section.commands.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final command in section.commands) ...<Widget>[
                      Text(
                        command.syntax,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        command.detail,
                        style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                      if (command != section.commands.last) const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}
