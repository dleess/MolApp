#!/bin/sh
# Builds the macOS disk image: flutter_app/dist/molapp-<version>-macos.dmg
#
# Run after `flutter build macos --release`. The image holds MolApp.app plus an
# /Applications symlink — the standard drag-to-install layout. Same idea as
# linux/packaging/build-deb.sh: the built tree *is* the package, nothing else.
#
#   flutter_app/macos/packaging/build-dmg.sh [output-dir]
set -eu

here=$(dirname "$(readlink -f "$0")")
flutter_dir=$(dirname "$(dirname "$here")")
out=${1:-$flutter_dir/dist}

version=$(sed -n 's/^version: \([0-9.]*\)+.*$/\1/p' "$flutter_dir/pubspec.yaml")
[ -n "$version" ] || { echo "build-dmg: could not read version from pubspec.yaml" >&2; exit 1; }

app="$flutter_dir/build/macos/Build/Products/Release/MolApp.app"
[ -d "$app" ] || {
  echo "build-dmg: $app is missing — run 'flutter build macos --release' first" >&2
  exit 1
}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

mkdir -p "$out"
dmg="$out/molapp-$version-macos.dmg"
hdiutil create -volname "MolApp $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
echo "$dmg"
