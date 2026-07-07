# MolApp

Native iPadOS SwiftUI molecule viewer scaffold.

## Build

Build the app for the iPad simulator:

```sh
xcodebuild -project MolApp.xcodeproj -scheme MolApp -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4.1' build CODE_SIGNING_ALLOWED=NO
```

## Apple Pencil

- **Hover residue tooltip** (done): hovering the Pencil over an atom/residue shows its identity
  label near the cursor before selection. Requires a physical iPad + Apple Pencil — the Simulator
  does not emit hover events.
- **Distance / angle / dihedral measurement** (done): Measure ▸ Distance / Angle / Dihedral Mode,
  then tap 2 / 3 / 4 atoms with the Pencil to draw the measurement (Å or °) between them. Atom-level
  picking; tap more sets to add, or Clear Measurements to remove. Also available as the `measure`,
  `measure angle`, `measure dihedral`, and `measure clear` commands.

Still planned:

- Screenshot annotation and sharing for communicating marked-up structure views.
