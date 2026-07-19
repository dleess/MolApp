import SwiftUI

enum MeasureKind: String, CaseIterable, Identifiable {
    case distance, angle, dihedral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Distance"
        case .angle:    "Angle"
        case .dihedral: "Dihedral"
        }
    }

    var atomCount: Int {
        switch self {
        case .distance: 2
        case .angle:    3
        case .dihedral: 4
        }
    }
}

private let defaultVisibilityStates = Dictionary(
    uniqueKeysWithValues: MoleculeVisibilityFeature.allCases.map { ($0, true) }
)

struct MoleculeViewerView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var pdbIdText = ""
    @State private var selectedRepresentation: MoleculeRepresentation = .ribbon
    @State private var visibilityStates = defaultVisibilityStates
    @State private var statusMessage = "Ready for structure loading"
    @State private var localErrorMessage: String?
    @State private var commandText = ""
    @State private var isObjectsPanelExpanded = true
    @State private var colorPickerTarget: String? = nil
    @State private var isMorphing = false
    @State private var isManualPresented = false
    @State private var measureKind: MeasureKind? = nil
    @State private var isStateImporterPresented = false
    @State private var shareItem: ShareItem?

    var body: some View {
        ZStack {
            viewport

            menuBar

            VStack(alignment: .leading, spacing: 8) {
                Text("Molecule Viewer")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))

                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Open Structure", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                HStack(spacing: 8) {
                    TextField("PDB ID", text: $pdbIdText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                        .onSubmit(loadPdbId)

                    Button {
                        loadPdbId()
                    } label: {
                        Label("Load PDB", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(pdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding()
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            objectsPanel

            VStack(spacing: 0) {
                Spacer()
                commandBar
            }
            .zIndex(10)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: LocalStructureFileLoader.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .fileImporter(
            isPresented: $isStateImporterPresented,
            allowedContentTypes: [.molApp],
            allowsMultipleSelection: false,
            onCompletion: handleStateImport
        )
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .sheet(isPresented: $isManualPresented) {
            ManualView()
        }
        .onReceive(bridge.$lastMeasurement) { label in
            guard let label else { return }
            statusMessage = "\(measureKind?.title ?? "Distance"): \(label)"
        }
        .onReceive(bridge.$lastCommandResult) { result in
            guard let result else { return }
            guard result.success else {
                // In-flight status is set optimistically and only advanced on success, so a rejected
                // command would otherwise claim "Loading …" forever next to the error banner.
                // ponytail: in-flight messages are identified by shape; give them their own @State
                // if that ever gets fragile.
                if statusMessage.hasSuffix("…") || statusMessage.hasPrefix("Loading") {
                    statusMessage = "Ready for structure loading"
                }
                // measureKind is set optimistically in toggleMeasure; if JS never entered measure
                // mode (e.g. the command failed before the viewer was ready), clear it so the
                // "tap N atoms" banner doesn't stick with taps doing nothing.
                if result.command == .setMeasureMode {
                    measureKind = nil
                }
                return
            }

            switch result.command {
            case .loadLocalStructure:
                let label = result.label ?? "Structure"
                statusMessage = "Loaded \(label)"
            case .loadPdbId:
                let name = result.label ?? PdbIdentifier.displayName(from: pdbIdText)
                statusMessage = "Loaded \(name)"
            case .setRepresentation:
                statusMessage = "\(selectedRepresentation.title) representation"
            case .surfacePotential:
                statusMessage = "Electrostatic potential (screened Coulomb)"
            case .startMorph:
                isMorphing = true
                statusMessage = "Morphing"
            case .stopMorph:
                isMorphing = false
                statusMessage = "Morph stopped"
            case .superpose:
                statusMessage = "Superposed visible structures"
            case .secondaryStructure:
                statusMessage = "Secondary structure (helix/sheet/coil)"
            case .resetAll:
                statusMessage = "Reset — everything cleared"
            case .undo:
                statusMessage = "Undid last change"
            case .redo:
                statusMessage = "Redid last change"
            case .loadState:
                statusMessage = "State loaded"
            case .transientModesStopped:
                // JS is the authority on these: it reports the moment it clears them, so a command
                // that clears and then fails cannot leave the UI claiming a mode the viewer dropped.
                measureKind = nil
                isMorphing = false
            default:
                break
            }
        }
        .onReceive(bridge.$featureVisibility) { dict in
            visibilityStates = defaultVisibilityStates
            for (key, isVisible) in dict {
                if let feature = MoleculeVisibilityFeature(rawValue: key) {
                    visibilityStates[feature] = isVisible
                }
            }
        }
    }

    private var viewport: some View {
        MolStarWebView(bridge: bridge)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) { hoverTooltip }
            .overlay(alignment: .top) { measureBanner }
    }

    @ViewBuilder
    private var measureBanner: some View {
        if let kind = measureKind {
            Label("\(kind.title) mode — tap \(kind.atomCount) atoms", systemImage: "ruler.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.85), in: Capsule())
                .padding(.top, 60)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var hoverTooltip: some View {
        if let label = bridge.hoverLabel, let point = bridge.hoverPoint {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.8), in: Capsule())
                .position(x: point.x, y: max(point.y - 28, 16))
                .allowsHitTesting(false)
        }
    }

    private var errorMessage: String? {
        localErrorMessage ?? bridge.lastErrorMessage
    }

    // Structures the user has left visible (eye-on) in the Objects panel. Global actions
    // (representation, surface potential, morph) are scoped to this selection so loading
    // multiple PDBs and hiding some restricts actions to the ones still shown.
    private var visibleStructureNames: [String] {
        bridge.objects.filter { $0.type == .structure && $0.isVisible }.map(\.name)
    }

    private var menuBar: some View {
        // iPad has room for all six menus in a row; iPhone (compact width) does not, so scroll them
        // horizontally instead of letting the row overflow and clip. Layout otherwise identical.
        Group {
            if hSizeClass == .compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    menuItems.padding(.horizontal, 12)
                }
            } else {
                HStack(spacing: 20) {
                    menuItems
                    Spacer()
                }
                .padding(.leading, 80)
                .padding(.trailing, 14)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .background(.black.opacity(0.68))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private var menuItems: some View {
        HStack(spacing: 20) {
            Menu("File") {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Open Structure", systemImage: "folder")
                }

                Button {
                    loadPdbId()
                } label: {
                    Label("Load PDB ID", systemImage: "square.and.arrow.down")
                }
                .disabled(pdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                Button {
                    saveState()
                } label: {
                    Label("Save State (.molapp)", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(bridge.objects.isEmpty)

                Button {
                    localErrorMessage = nil
                    isStateImporterPresented = true
                } label: {
                    Label("Open State (.molapp)", systemImage: "folder.badge.gearshape")
                }

                Divider()

                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            exportImage(format)
                        } label: {
                            Text(format.title)
                        }
                    }
                } label: {
                    Label("Export Display", systemImage: "photo")
                }
                .disabled(bridge.objects.isEmpty)

                Button {
                    printDisplay()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .disabled(bridge.objects.isEmpty)

                Divider()

                Button(role: .destructive) {
                    localErrorMessage = nil
                    bridge.resetAll()
                    statusMessage = "Resetting…"
                } label: {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                }
            }

            Menu("Edit") {
                Button {
                    localErrorMessage = nil
                    bridge.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }

                Button {
                    localErrorMessage = nil
                    bridge.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }

                Divider()

                Button {
                    localErrorMessage = nil
                    bridge.clearSelection()
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
            }

            Menu("Display") {
                Section("Representation") {
                    ForEach(MoleculeRepresentation.allCases) { representation in
                        Button {
                            setRepresentation(representation)
                        } label: {
                            Label(representation.title, systemImage: representation.systemImage)
                        }
                        .disabled(visibleStructureNames.isEmpty)
                    }
                }

                Section("Visibility") {
                    ForEach(MoleculeVisibilityFeature.allCases) { feature in
                        Button {
                            toggleVisibility(feature)
                        } label: {
                            Label(
                                "\(visibilityStates[feature, default: true] ? "Hide" : "Show") \(feature.title)",
                                systemImage: feature.systemImage
                            )
                        }
                    }
                }

                Section("Background") {
                    ForEach(Self.backgroundPresets) { preset in
                        Button {
                            localErrorMessage = nil
                            bridge.setBackgroundColor(colorHex: preset.hex)
                            statusMessage = "Background: \(preset.title)"
                        } label: {
                            Label(preset.title, systemImage: "square.fill")
                        }
                    }
                }
            }

            Menu("Calculation") {
                Button {
                    localErrorMessage = nil
                    statusMessage = "Computing surface potential…"
                    bridge.drawSurfacePotential(targets: visibleStructureNames)
                } label: {
                    Label("Surface Potential", systemImage: "bolt.circle")
                }
                .disabled(visibleStructureNames.isEmpty)

                Button {
                    localErrorMessage = nil
                    statusMessage = "Assigning secondary structure…"
                    bridge.computeSecondaryStructure(targets: visibleStructureNames)
                } label: {
                    Label("Secondary Structure", systemImage: "scribble.variable")
                }
                .disabled(visibleStructureNames.isEmpty)

                Button {
                    localErrorMessage = nil
                    statusMessage = "Superposing structures…"
                    bridge.superpose(targets: visibleStructureNames)
                } label: {
                    Label("Superpose Visible", systemImage: "square.on.square.dashed")
                }
                .disabled(visibleStructureNames.count < 2)

                Section("Morph") {
                    Button {
                        localErrorMessage = nil
                        if isMorphing {
                            bridge.stopMorph()
                        } else {
                            statusMessage = "Morphing trajectory…"
                            bridge.startMorph(loop: false, targets: visibleStructureNames)
                        }
                    } label: {
                        Label(
                            isMorphing ? "Stop Morph" : "Start Morph",
                            systemImage: isMorphing ? "stop.circle" : "play.circle"
                        )
                    }
                    .disabled(!isMorphing && visibleStructureNames.isEmpty)
                }
            }

            Menu("Measure") {
                ForEach(MeasureKind.allCases) { kind in
                    Button {
                        toggleMeasure(kind)
                    } label: {
                        Label(
                            "\(kind.title) Mode",
                            systemImage: measureKind == kind ? "ruler.fill" : "ruler"
                        )
                    }
                }

                Button {
                    localErrorMessage = nil
                    bridge.clearMeasurements()
                    statusMessage = "Measurements cleared"
                } label: {
                    Label("Clear Measurements", systemImage: "trash")
                }
            }

            Menu("Help") {
                Button {
                    isManualPresented = true
                } label: {
                    Label("Manual", systemImage: "book")
                }

                Button {
                    statusMessage = "Open a PDB/mmCIF file or enter a PDB ID"
                } label: {
                    Label("Quick Help", systemImage: "questionmark.circle")
                }
            }
        }
    }

    private var commandBar: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.white.opacity(0.6))

            CommandTextField(
                text: $commandText,
                placeholder: "Enter command (e.g. load 1crn, repr surface)...",
                onSubmit: executeCommand
            )
            .frame(height: 36)

            if !commandText.isEmpty {
                Button {
                    commandText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Button {
                executeCommand()
            } label: {
                Label("Run command", systemImage: "arrow.up.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.3) : .blue)
            }
            .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Run command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 56)
        .frame(maxWidth: 600)
        .zIndex(10)
        .contentShape(Rectangle())
    }

    private func executeCommand() {
        let input = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        commandText = ""
        localErrorMessage = nil
        let components = input.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        // Object names (PDB IDs, file labels) are stored case-sensitively (uppercase for PDB IDs),
        // so keep an original-case token list for name arguments — only keywords are lowercased.
        let rawComponents = input.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let command = components.first else { return }

        switch command {
        case "load":
            if components.count >= 2 {
                pdbIdText = components[1].uppercased()
                loadPdbId()
            } else {
                localErrorMessage = "Usage: load [PDB_ID]"
            }
        case "repr":
            if components.count >= 3 {
                let reprStr = components[1]
                let objName = rawComponents.dropFirst(2).joined(separator: " ")
                if let repr = ObjectRepresentation.allCases.first(where: { $0.rawValue.lowercased() == reprStr }) {
                    bridge.setObjectRepresentation(name: objName, representation: repr)
                } else {
                    localErrorMessage = "Invalid representation. Use: \(ObjectRepresentation.allCases.map(\.rawValue).joined(separator: ", "))"
                }
            } else if components.count >= 2 {
                if let repr = MoleculeRepresentation(rawValue: components[1]) {
                    setRepresentation(repr)
                } else {
                    localErrorMessage = "Invalid representation. Use: \(MoleculeRepresentation.allCases.map(\.rawValue).joined(separator: ", "))"
                }
            } else {
                localErrorMessage = "Usage: repr [ribbon|surface|stick|ballAndStick|sphere] [name?]"
            }
        case "show", "hide":
            if components.count >= 2 {
                let arg = components[1]
                let isVisible = (command == "show")
                if let feature = MoleculeVisibilityFeature(rawValue: arg) {
                    if visibilityStates[feature] != isVisible {
                        toggleVisibility(feature)
                    }
                } else {
                    bridge.setObjectVisibility(name: rawComponents.dropFirst().joined(separator: " "), isVisible: isVisible)
                }
            } else {
                localErrorMessage = "Usage: \(command) [water|ligand|objectname]"
            }
        case "select":
            let afterSelect = input.dropping(first: 6).trimmingCharacters(in: .whitespaces)
            if afterSelect.isEmpty {
                localErrorMessage = "Usage: select [name] [expression] (e.g. select sele chain A & resn ala)"
            } else {
                let (selectionName, expression) = SelectionExpressionParser.extractName(from: afterSelect)
                do {
                    // Keep original case: the parser lowercases only keyword tokens, so chain IDs
                    // (which can be lowercase, e.g. large-assembly auth_asym_id) survive.
                    var parser = SelectionExpressionParser(expression: expression)
                    let ast = try parser.parse()
                    let selection = MoleculeSelection(type: "expression", label: "\(selectionName): \(expression)", ast: ast)
                    bridge.setSelection(selection)
                } catch {
                    localErrorMessage = error.localizedDescription
                }
            }
        case "color":
            if components.count >= 3 {
                let colorArg = components[1]
                let objName = rawComponents.dropFirst(2).joined(separator: " ")
                // Reject an unknown color name instead of silently painting it white (colorNameToHex
                // falls back to #FFFFFF): a typo like "gren" must report the usage, not recolor white.
                let colorHex: String?
                if colorArg == "default" {
                    colorHex = nil
                } else if colorArg.hasPrefix("#") {
                    colorHex = colorArg
                } else if let named = Self.namedColors[colorArg] {
                    colorHex = named
                } else {
                    localErrorMessage = "Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]"
                    return
                }
                bridge.setObjectColor(name: objName, colorHex: colorHex)
            } else {
                localErrorMessage = "Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]"
            }
        case "background", "bg":
            let arg = components.count >= 2 ? components[1] : ""
            let hex: String? = arg.hasPrefix("#")
                ? arg.uppercased()
                : Self.backgroundPresets.first { $0.title.lowercased() == arg }?.hex
            if let hex, hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil {
                bridge.setBackgroundColor(colorHex: hex)
                statusMessage = "Background set"
            } else {
                localErrorMessage = "Usage: background [dark|black|gray|light|white|#RRGGBB]"
            }
        case "clear":
            bridge.clearSelection()
        case "focus":
            bridge.focusSelection()
        case "surfpot", "potential":
            statusMessage = "Computing surface potential…"
            bridge.drawSurfacePotential(targets: visibleStructureNames)
        case "ss", "dssp", "secstr":
            statusMessage = "Assigning secondary structure…"
            bridge.computeSecondaryStructure(targets: visibleStructureNames)
        case "super", "superpose", "align":
            if visibleStructureNames.count < 2 {
                localErrorMessage = "Show at least two structures to superpose."
            } else {
                statusMessage = "Superposing structures…"
                bridge.superpose(targets: visibleStructureNames)
            }
        case "morph":
            let arg = components.count >= 2 ? components[1] : "start"
            if arg == "stop" {
                bridge.stopMorph()
            } else {
                let loop = components.contains("loop")
                statusMessage = "Morphing trajectory…"
                bridge.startMorph(loop: loop, targets: visibleStructureNames)
            }
        case "measure", "dist":
            let arg = components.count >= 2 ? components[1] : "distance"
            switch arg {
            case "clear":
                bridge.clearMeasurements()
                statusMessage = "Measurements cleared"
            case "off":
                if let kind = measureKind { toggleMeasure(kind) }
            case "angle":
                if measureKind != .angle { toggleMeasure(.angle) }
            case "dihedral", "torsion":
                if measureKind != .dihedral { toggleMeasure(.dihedral) }
            default:
                if measureKind != .distance { toggleMeasure(.distance) }
            }
        default:
            localErrorMessage = "Unknown command: \(command)"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let structure = try LocalStructureFileLoader.load(from: url)
            statusMessage = "Loading \(structure.label)"
            localErrorMessage = nil
            bridge.loadLocalStructure(data: structure.data, format: structure.format, label: structure.label)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func handleStateImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Saved state embeds the structure text, so it is the same size class as a raw file and
            // needs the same cap — see LocalStructureFileLoader.load.
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LocalStructureFileLoader.maxFileSize else {
                throw LocalStructureFileLoaderError.tooLarge(size)
            }
            let data = try Data(contentsOf: url)
            // fileSizeKey is nil for some providers → the pre-check passes with size 0; re-check the
            // bytes actually read (see LocalStructureFileLoader.load).
            guard data.count <= LocalStructureFileLoader.maxFileSize else {
                throw LocalStructureFileLoaderError.tooLarge(data.count)
            }
            guard let json = String(data: data, encoding: .utf8) else {
                localErrorMessage = "Could not read .molapp file."
                return
            }
            localErrorMessage = nil
            statusMessage = "Loading state…"
            bridge.loadState(json: json)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func saveState() {
        localErrorMessage = nil
        Task {
            guard let json = await bridge.serializeState() else {
                localErrorMessage = "Could not capture current state."
                return
            }
            guard let url = writeTemporaryFile(named: "molecule.molapp", data: Data(json.utf8)) else {
                localErrorMessage = "Could not write state file."
                return
            }
            shareItem = ShareItem(url: url)
        }
    }

    private func exportImage(_ format: ExportFormat) {
        localErrorMessage = nil
        statusMessage = "Rendering \(format.title)…"
        Task {
            guard let dataURL = await bridge.captureImageDataURL(),
                  let image = imageFromDataURL(dataURL) else {
                localErrorMessage = "Could not capture the display."
                return
            }
            guard let data = encodeImage(image, as: format),
                  let url = writeTemporaryFile(named: "molecule.\(format.fileExtension)", data: data) else {
                localErrorMessage = "Could not encode \(format.title)."
                return
            }
            statusMessage = "Exported \(format.title)"
            shareItem = ShareItem(url: url)
        }
    }

    private func printDisplay() {
        localErrorMessage = nil
        Task {
            guard let dataURL = await bridge.captureImageDataURL(),
                  let image = imageFromDataURL(dataURL) else {
                localErrorMessage = "Could not capture the display."
                return
            }
            presentPrint(image)
        }
    }

    private func loadPdbId() {
        do {
            let pdbId = try PdbIdentifier.normalized(pdbIdText)
            pdbIdText = pdbId
            statusMessage = "Loading \(pdbId)"
            localErrorMessage = nil
            bridge.loadPdbId(pdbId)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func setRepresentation(_ representation: MoleculeRepresentation) {
        selectedRepresentation = representation
        localErrorMessage = nil
        bridge.setRepresentation(representation.rawValue, targets: visibleStructureNames)
    }

    private func toggleMeasure(_ kind: MeasureKind) {
        localErrorMessage = nil
        if measureKind == kind {
            measureKind = nil
            bridge.setMeasureMode(false)
            statusMessage = "Measure mode off"
        } else {
            measureKind = kind
            bridge.setMeasureMode(true, kind: kind.rawValue)
            statusMessage = "\(kind.title): tap \(kind.atomCount) atoms"
        }
    }

    private func toggleVisibility(_ feature: MoleculeVisibilityFeature) {
        let isVisible = !visibilityStates[feature, default: true]
        visibilityStates[feature] = isVisible
        localErrorMessage = nil
        statusMessage = "\(feature.title) \(isVisible ? "shown" : "hidden")"
        bridge.toggleVisibility(feature: feature.rawValue, isVisible: isVisible)
    }

    // Okabe-Ito colorblind-safe qualitative palette. Command names keep their familiar
    // labels; the hexes map to the nearest Okabe-Ito hue so every swatch stays
    // distinguishable under deuteranopia/protanopia. "white" is the light neutral in place
    // of Okabe-Ito black (invisible on the dark viewport).
    private static let namedColors: [String: String] = [
        "red": "#D55E00", "green": "#009E73", "blue": "#0072B2",
        "yellow": "#F0E442", "white": "#FFFFFF", "cyan": "#56B4E9",
        "magenta": "#CC79A7", "orange": "#E69F00"
    ]

    private func colorNameToHex(_ name: String) -> String {
        if name.hasPrefix("#") { return name }
        return Self.namedColors[name] ?? "#FFFFFF"
    }

    // Viewport background presets (dark → light). Shared by the Display ▸ Background menu and the
    // `background` command so both offer the same names.
    struct BackgroundPreset: Identifiable {
        let title: String
        let hex: String
        var id: String { hex }
    }
    static let backgroundPresets: [BackgroundPreset] = [
        .init(title: "Dark", hex: "#0B0F14"),
        .init(title: "Black", hex: "#000000"),
        .init(title: "Gray", hex: "#4D4D4D"),
        .init(title: "Light", hex: "#D9D9D9"),
        .init(title: "White", hex: "#FFFFFF"),
    ]

    private var objectsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isObjectsPanelExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Objects")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: isObjectsPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if isObjectsPanelExpanded {
                if bridge.objects.isEmpty {
                    Text("No objects")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(bridge.objects) { object in
                        objectRow(object)
                        if object.id != bridge.objects.last?.id {
                            Divider().overlay(.white.opacity(0.15))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 16)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func objectRow(_ object: MolAppObject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    bridge.setObjectVisibility(name: object.name, isVisible: !object.isVisible)
                } label: {
                    Image(systemName: object.isVisible ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(object.isVisible ? .white : .white.opacity(0.35))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(object.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(object.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Circle()
                    .fill(object.swiftUIColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                    .onTapGesture { colorPickerTarget = object.name }
                    .popover(isPresented: Binding(
                        get: { colorPickerTarget == object.name },
                        set: { if !$0 { colorPickerTarget = nil } }
                    )) {
                        colorPickerPopover(for: object.name)
                    }
            }

            HStack(spacing: 4) {
                ForEach(ObjectRepresentation.allCases) { repr in
                    Button(repr.shortTitle) {
                        bridge.setObjectRepresentation(name: object.name, representation: repr)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        object.representation == repr
                            ? Color.white.opacity(0.25)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                    .foregroundStyle(
                        object.representation == repr ? .white : .white.opacity(0.6)
                    )
                }
            }
        }
    }

    private static let pickerColors: [(label: String, key: String)] = [
        ("Default", "default"), ("Red", "red"), ("Green", "green"),
        ("Blue", "blue"), ("Yellow", "yellow"), ("White", "white"),
        ("Cyan", "cyan"), ("Magenta", "magenta"), ("Orange", "orange")
    ]
    private static let colorPickerColumns = Array(repeating: GridItem(.fixed(34)), count: 5)

    private func colorPickerPopover(for name: String) -> some View {
        return VStack(spacing: 8) {
            Text("Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            LazyVGrid(columns: Self.colorPickerColumns, spacing: 8) {
                ForEach(Self.pickerColors, id: \.key) { item in
                    let hex: String? = item.key == "default" ? nil : colorNameToHex(item.key)
                    Button {
                        bridge.setObjectColor(name: name, colorHex: hex)
                        colorPickerTarget = nil
                    } label: {
                        Circle()
                            .fill(hex.flatMap { Color(hex: $0) } ?? Color.gray.opacity(0.4))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .presentationCompactAdaptation(.popover)
    }
}

#Preview {
    MoleculeViewerView()
}
