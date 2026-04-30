# PRD: iPadOS Mol* Molecule Viewer

## Introduction

Build a native iPadOS molecule viewer for structural biology and chemistry researchers. The app should let researchers open molecular structure files, inspect them in a full-screen 3D viewport, and use familiar iPad gestures to rotate, pan, zoom, and focus the structure without a mouse. The first release uses SwiftUI for the native app shell and Mol* inside `WKWebView` for molecular rendering.

## Goals

- Allow researchers to open local `pdb`, `cif`, and `mmcif` files from the iPad Files app.
- Provide stable one-finger rotate, two-finger pan, pinch-to-zoom, and double-tap focus gestures in the 3D viewport.
- Render loaded structures in a full-screen viewport with floating controls that do not permanently consume screen space.
- Provide basic representation switching and visibility toggles for common structural inspection workflows.
- Show selected atom or residue details in a bottom sheet.

## User Stories

### US-001: Create the iPadOS viewer shell
**Description:** As a researcher, I want a native iPadOS app with a full-screen molecule viewport so that I can inspect molecular structures without desktop-style sidebars.

**Acceptance Criteria:**
- [ ] App launches into a full-screen `MoleculeViewerView`.
- [ ] The 3D viewport occupies the available screen behind overlay controls.
- [ ] Floating toolbar and bottom sheet do not force the viewport into a smaller fixed layout.
- [ ] Layout works in landscape and portrait orientations on iPad-sized screens.
- [ ] Typecheck/build passes.
- [ ] Verify UI on iPad Simulator or real iPad.

### US-002: Load local structure files
**Description:** As a researcher, I want to open local molecular structure files from the iPad Files app so that I can inspect my own PDB or mmCIF data.

**Acceptance Criteria:**
- [ ] User can open a file picker from the viewer UI.
- [ ] File picker accepts `pdb`, `cif`, and `mmcif` files.
- [ ] Selected file content is passed from SwiftUI to the Mol* viewer in `WKWebView`.
- [ ] A successfully loaded file appears in the 3D viewport.
- [ ] Loading failure shows a clear non-blocking error state.
- [ ] Typecheck/build passes.
- [ ] Verify UI on iPad Simulator or real iPad.

### US-003: Add PDB ID loading after local files
**Description:** As a researcher, I want to load a public structure by PDB ID so that I can quickly inspect known structures without downloading files manually.

**Acceptance Criteria:**
- [ ] Viewer UI includes a PDB ID input flow.
- [ ] Entering a valid PDB ID requests the structure from an RCSB-compatible download URL.
- [ ] Loaded PDB ID structure appears in the same Mol* viewport as local files.
- [ ] Invalid IDs or network failures show a clear non-blocking error state.
- [ ] Local file loading remains the primary path and is not regressed.
- [ ] Typecheck/build passes.
- [ ] Verify UI on iPad Simulator or real iPad.

### US-004: Support iPad-native 3D gestures
**Description:** As a researcher, I want to manipulate the molecule with standard iPad gestures so that navigation feels natural without a mouse.

**Acceptance Criteria:**
- [ ] One-finger drag rotates the molecule.
- [ ] Two-finger drag pans the view.
- [ ] Pinch gesture zooms in and out.
- [ ] Double tap centers and zooms toward the selected atom or residue when one is selected.
- [ ] Double tap does not trigger accidental file loading, panel changes, or unrelated toolbar actions.
- [ ] Typecheck/build passes.
- [ ] Verify gestures on iPad Simulator or real iPad.

### US-005: Switch representations and visibility toggles
**Description:** As a researcher, I want one-tap controls for common molecule representations and visibility toggles so that I can quickly inspect different structural features.

**Acceptance Criteria:**
- [ ] Floating toolbar provides `Ribbon`, `Surface`, and `Stick` representation actions.
- [ ] Floating toolbar provides `Water`, `Ligand`, and `Disulfide` visibility toggles.
- [ ] Tapping a representation action updates the Mol* rendering without reloading the structure.
- [ ] Tapping a visibility toggle updates only the relevant structural feature when present.
- [ ] Missing feature categories do not crash the viewer.
- [ ] Typecheck/build passes.
- [ ] Verify UI on iPad Simulator or real iPad.

### US-006: Select and inspect atoms or residues
**Description:** As a researcher, I want to tap an atom or residue and see focused details so that I can understand the selected structural region.

**Acceptance Criteria:**
- [ ] Tapping a selectable atom or residue updates the current selection.
- [ ] Selected item is visually highlighted in the 3D viewport.
- [ ] Non-selected structure is dimmed enough to reduce visual clutter.
- [ ] Bottom sheet displays selected atom or residue identity, including available name, number, chain, and model data.
- [ ] Clearing the selection removes highlight and resets the bottom sheet state.
- [ ] Typecheck/build passes.
- [ ] Verify UI on iPad Simulator or real iPad.

### US-007: Prepare Apple Pencil advanced features for a later release
**Description:** As a product team, I want Apple Pencil functionality captured as a follow-up release candidate so that the MVP remains focused while preserving the professional app direction.

**Acceptance Criteria:**
- [ ] PRD or follow-up backlog identifies Pencil hover residue tooltip as a future capability.
- [ ] PRD or follow-up backlog identifies Pencil-based distance and angle measurement as a future capability.
- [ ] PRD or follow-up backlog identifies screenshot annotation and sharing as a future capability.
- [ ] MVP implementation does not require Apple Pencil support to be considered complete.

## Functional Requirements

- FR-1: The system must provide a native SwiftUI iPadOS app shell.
- FR-2: The system must embed the Mol* WebGL viewer inside `WKWebView`.
- FR-3: The system must expose a Swift-to-JavaScript bridge for `loadLocalStructure`, `loadPdbId`, `setRepresentation`, `toggleVisibility`, `focusSelection`, `setSelection`, and `clearSelection`.
- FR-4: The system must allow local structure loading for `pdb`, `cif`, and `mmcif` files.
- FR-5: The system must allow PDB ID loading after local file loading is implemented.
- FR-6: The system must render structures in a full-screen viewport with overlay controls.
- FR-7: The system must map one-finger drag to rotation.
- FR-8: The system must map two-finger drag to panning.
- FR-9: The system must map pinch gestures to zoom.
- FR-10: The system must map double tap to center and zoom on the selected atom or residue.
- FR-11: The system must provide one-tap representation actions for `Ribbon`, `Surface`, and `Stick`.
- FR-12: The system must provide toggles for `Water`, `Ligand`, and `Disulfide`.
- FR-13: The system must show selected atom or residue details in a bottom sheet.
- FR-14: The system must visually highlight the selected atom or residue and dim non-selected structure.
- FR-15: The system must handle load and render errors without crashing the app.

## Non-Goals

- No pure Swift, SceneKit, or Metal molecular renderer in the MVP.
- No fixed desktop-style sidebar layout in the MVP.
- No structure/chain navigator in the MVP.
- No multi-model NMR ensemble management UI in the MVP.
- No large Cryo-EM complex optimization beyond basic successful rendering in the MVP.
- No required Apple Pencil hover, measurement, annotation, or sharing implementation in the MVP.
- No account system, cloud sync, collaboration, or remote project storage.

## Design Considerations

- The 3D viewport should feel like the primary surface of the app, with controls layered above it.
- Toolbar controls should use compact icons where possible and avoid long text labels inside small buttons.
- The floating toolbar should be collapsible or edge-aligned so users can maximize structure visibility.
- The bottom sheet should support at least collapsed and expanded states.
- UI must avoid interfering with molecule gestures in the center of the viewport.
- Text in overlays must remain legible on top of complex molecular visuals.

## Technical Considerations

- Mol* should be bundled as static web assets in the app so the core viewer is not dependent on loading the viewer library from the network.
- Local structure file contents should be passed into the WebView through a controlled bridge instead of ad hoc DOM manipulation.
- PDB ID loading can use an RCSB-compatible download URL in the first release.
- Mol* camera controls should be reused where practical, with touch behavior adjusted only where needed for iPad expectations.
- The bridge API should stay small to reduce Swift/JavaScript coupling.
- This repository currently has no app code, so implementation begins by scaffolding a new iPadOS project.

## Success Metrics

- A researcher can open a local structure file and see it rendered in the viewport.
- A researcher can rotate, pan, zoom, and double-tap focus using only touch gestures.
- Local file loading remains the fastest path and can be completed without entering a PDB ID.
- Representation changes and visibility toggles update without a full structure reload.
- Selection visibly updates the viewport and bottom sheet within one interaction.

## Open Questions

- Which exact minimum iPadOS version should the app support?
- Should PDB ID loading prefer mmCIF or PDB format from RCSB by default?
- Should the MVP include a built-in sample structure for first launch or testing?
- What visual style should be used for toolbar icons and selection colors?
