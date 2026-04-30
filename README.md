# MolApp

Native iPadOS SwiftUI molecule viewer scaffold.

## Build

Build the app for the iPad simulator:

```sh
xcodebuild -project MolApp.xcodeproj -scheme MolApp -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4.1' build CODE_SIGNING_ALLOWED=NO
```

## Apple Pencil Follow-Up

Apple Pencil support is planned as a follow-up release candidate and is not required for MVP completion.

Future Pencil capabilities:

- Hover residue tooltip for quickly previewing atom or residue identity before selection.
- Pencil-based distance and angle measurement for structural inspection workflows.
- Screenshot annotation and sharing for communicating marked-up structure views.
