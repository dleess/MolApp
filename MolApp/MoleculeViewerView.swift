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

struct MoleculeViewerView: View {
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var pdbIdText = ""
    @State private var selectedRepresentation: MoleculeRepresentation = .ribbon
    @State private var visibilityStates: [MoleculeVisibilityFeature: Bool] = [
        .water: true,
        .ligand: true
    ]
    @State private var statusMessage = "Ready for structure loading"
    @State private var localErrorMessage: String?
    @State private var pendingStructureLabel: String?
    @State private var commandText = ""
    @State private var isObjectsPanelExpanded = true
    @State private var colorPickerTarget: String? = nil
    @State private var isMorphing = false
    @State private var isManualPresented = false
    @State private var measureKind: MeasureKind? = nil

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
        .sheet(isPresented: $isManualPresented) {
            ManualView()
        }
        .onReceive(bridge.$lastErrorMessage) { message in
            localErrorMessage = message
        }
        .onReceive(bridge.$lastMeasurement) { label in
            guard let label else { return }
            statusMessage = "\(measureKind?.title ?? "Distance"): \(label)"
        }
        .onReceive(bridge.$lastCommandResult) { result in
            guard let result, result.success else { return }

            switch result.command {
            case .loadLocalStructure:
                let label = pendingStructureLabel ?? "Structure"
                statusMessage = "Loaded \(label)"
                bridge.addObject(MolAppObject(name: label, type: .structure))
                pendingStructureLabel = nil
                visibilityStates = [.water: true, .ligand: true]
            case .loadPdbId:
                // Use the label captured at send time, not the live field — the field may have
                // changed during the async fetch, which would name the object off the JS key.
                let name = pendingStructureLabel ?? pdbIdText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = "Loaded \(name)"
                bridge.addObject(MolAppObject(name: name, type: .structure))
                pendingStructureLabel = nil
                visibilityStates = [.water: true, .ligand: true]
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
            default:
                break
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
            }

            Menu("Edit") {
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
            }

            Menu("Calculation") {
                Button {
                    localErrorMessage = nil
                    statusMessage = "Computing surface potential…"
                    bridge.drawSurfacePotential(targets: visibleStructureNames)
                } label: {
                    Label("Surface Potential", systemImage: "bolt.circle")
                }

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

            Spacer()
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.leading, 80)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.68))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
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
                let objName = rawComponents[2]
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
                localErrorMessage = "Usage: repr [ribbon|surface|stick|ballAndStick] [name?]"
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
                    bridge.setObjectVisibility(name: rawComponents[1], isVisible: isVisible)
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
                    bridge.addObject(MolAppObject(name: selectionName, type: .selection))
                } catch {
                    localErrorMessage = error.localizedDescription
                }
            }
        case "color":
            if components.count >= 3 {
                let colorArg = components[1]
                let objName = rawComponents[2]
                let colorHex: String? = colorArg == "default" ? nil : colorNameToHex(colorArg)
                bridge.setObjectColor(name: objName, colorHex: colorHex)
            } else {
                localErrorMessage = "Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]"
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
            pendingStructureLabel = structure.label
            localErrorMessage = nil
            bridge.loadLocalStructure(data: structure.data, format: structure.format, label: structure.label)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func loadPdbId() {
        do {
            let pdbId = try PdbIdentifier.normalized(pdbIdText)
            pdbIdText = pdbId
            statusMessage = "Loading \(pdbId)"
            pendingStructureLabel = pdbId
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

    private static let namedColors: [String: String] = [
        "red": "#FF4444", "green": "#44FF44", "blue": "#4444FF",
        "yellow": "#FFFF44", "white": "#FFFFFF", "cyan": "#44FFFF",
        "magenta": "#FF44FF", "orange": "#FF8844"
    ]

    private func colorNameToHex(_ name: String) -> String {
        if name.hasPrefix("#") { return name }
        return Self.namedColors[name] ?? "#FFFFFF"
    }

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
