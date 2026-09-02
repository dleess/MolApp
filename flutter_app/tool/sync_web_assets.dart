// Copies the shared web core (viewer.html + the Mol* bundle) from ../MolApp/Resources into
// assets/web/, so the 4.8 MB molstar bundle lives in git exactly once. Edit only ../MolApp/Resources.
//
//   dart run tool/sync_web_assets.dart
//
// Run it after checkout and whenever viewer.html changes; `flutter build` does not run it for you.

import 'dart:io';

const _files = ['viewer.html', 'molstar/molstar.js', 'molstar/molstar.css'];

void main(List<String> args) {
  final projectRoot = Directory.current;
  final source = Directory('${projectRoot.parent.path}/MolApp/Resources');
  if (!source.existsSync()) {
    stderr.writeln(
      'Source not found: ${source.path}\n'
      'Run this from the flutter_app/ directory of a full MolApp checkout.',
    );
    exit(1);
  }

  final destination = Directory('${projectRoot.path}/assets/web');
  Directory('${destination.path}/molstar').createSync(recursive: true);

  for (final name in _files) {
    final from = File('${source.path}/$name');
    if (!from.existsSync()) {
      stderr.writeln('Missing web asset: ${from.path}');
      exit(1);
    }
    final to = File('${destination.path}/$name');
    from.copySync(to.path);
    stdout.writeln('synced $name (${from.lengthSync()} bytes)');
  }
}
