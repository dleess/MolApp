#!/bin/sh
# Builds the Debian/Ubuntu package for the GTK shell: linux/dist/molapp_<version>_all.deb
#
# Architecture is `all`: the shell is pure Python, and everything native (GTK, WebKitGTK, Pillow)
# comes from the distro packages listed in Depends. There is nothing to compile, so there is no
# debhelper/dh-python machinery here either — the tree below *is* the package.
#
#   linux/packaging/build-deb.sh [output-dir]
#   sudo apt-get install -y ./linux/dist/molapp_1.1.4_all.deb
set -eu

here=$(dirname "$(readlink -f "$0")")
linux_dir=$(dirname "$here")
repo=$(dirname "$linux_dir")
out=${1:-$linux_dir/dist}

version=$(sed -n 's/^APP_VERSION = "\(.*\)"$/\1/p' "$linux_dir/molapp/__init__.py")
[ -n "$version" ] || { echo "build-deb: could not read APP_VERSION" >&2; exit 1; }
[ -f "$repo/MolApp/Resources/viewer.html" ] || {
  echo "build-deb: MolApp/Resources/viewer.html is missing — the package is nothing without it" >&2
  exit 1
}

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
# mktemp gives 0700; that mode would ride along on the package's own root entry.
chmod 755 "$root"

install -d "$root/usr/lib/molapp/molapp" \
           "$root/usr/share/molapp/web" \
           "$root/usr/bin" \
           "$root/usr/share/applications" \
           "$root/usr/share/icons/hicolor/256x256/apps" \
           "$root/usr/share/doc/molapp" \
           "$root/DEBIAN"

# The shell itself, and the shared web core it renders — the same files the other three shells run.
install -m 644 "$linux_dir"/molapp/*.py "$root/usr/lib/molapp/molapp/"
install -m 644 "$repo/MolApp/Resources/viewer.html" "$root/usr/share/molapp/web/"
install -d "$root/usr/share/molapp/web/molstar"
install -m 644 "$repo/MolApp/Resources/molstar/"* "$root/usr/share/molapp/web/molstar/"

# /usr/share/molapp/web is already the third candidate viewer_html_path() checks, so the installed
# app needs no configuration to find its assets.
cat > "$root/usr/bin/molapp" <<'LAUNCHER'
#!/bin/sh
PYTHONPATH="/usr/lib/molapp${PYTHONPATH:+:$PYTHONPATH}" exec /usr/bin/python3 -m molapp "$@"
LAUNCHER
chmod 755 "$root/usr/bin/molapp"

install -m 644 "$linux_dir/molapp.desktop" \
  "$root/usr/share/applications/com.donghan.molapp.desktop"
install -m 644 "$here/molapp.png" \
  "$root/usr/share/icons/hicolor/256x256/apps/com.donghan.molapp.png"
install -m 644 "$here/copyright" "$root/usr/share/doc/molapp/copyright"

# du reports what the package will occupy, in KiB — what Installed-Size means.
installed_size=$(du -ks "$root/usr" | cut -f1)

cat > "$root/DEBIAN/control" <<CONTROL
Package: molapp
Version: $version
Section: science
Priority: optional
Architecture: all
Maintainer: Donghan Lee <92695827+dleess@users.noreply.github.com>
Installed-Size: $installed_size
Depends: python3 (>= 3.10), python3-gi, python3-gi-cairo, gir1.2-gtk-3.0, gir1.2-webkit2-4.1, python3-pil
Homepage: https://github.com/dleess/MolApp
Description: Mol*-powered molecular structure viewer
 MolApp displays PDB and mmCIF structures with Mol*: ribbon, surface, stick,
 ball-and-stick and sphere representations, per-object colouring, electrostatic
 surface potential, secondary-structure assignment, superposition, trajectory
 morphing, and distance/angle/dihedral measurement.
 .
 This is the GTK 3 / WebKitGTK build; the same viewer also ships for iOS,
 Android, macOS and Windows.
CONTROL

mkdir -p "$out"
package="$out/molapp_${version}_all.deb"
# fakeroot so the files land as root:root rather than the building user.
fakeroot dpkg-deb --build --root-owner-group "$root" "$package" >/dev/null
echo "$package"
