import SwiftUI

struct MoleculeViewerView: View {
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var isRepresentationToolbarExpanded = true
    @State private var isSelectionSheetExpanded = false
    @State private var pdbIdText = ""
    @State private var selectedRepresentation: MoleculeRepresentation = .ribbon
    @State private var visibilityStates: [MoleculeVisibilityFeature: Bool] = [
        .water: true,
        .ligand: true,
        .disulfide: true
    ]
    @State private var statusMessage = "Ready for structure loading"
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack {
            viewport

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            representationToolbar
            selectionBottomSheet
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: LocalStructureFileLoader.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onReceive(bridge.$lastErrorMessage) { message in
            localErrorMessage = message
        }
        .onReceive(bridge.$lastCommandResult) { result in
            guard let result, result.success else { return }

            if result.command == .loadPdbId {
                statusMessage = "Loaded \(PdbIdentifier.displayName(from: pdbIdText))"
            } else if result.command == .setRepresentation {
                statusMessage = "\(selectedRepresentation.title) representation"
            }
        }
    }

    private var viewport: some View {
        MolStarWebView(bridge: bridge)
            .ignoresSafeArea()
    }

    private var errorMessage: String? {
        localErrorMessage ?? bridge.lastErrorMessage
    }

    private var representationToolbar: some View {
        VStack(spacing: 8) {
            Button {
                isRepresentationToolbarExpanded.toggle()
            } label: {
                Label("Representations", systemImage: isRepresentationToolbarExpanded ? "chevron.right" : "paintpalette")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel(isRepresentationToolbarExpanded ? "Collapse representation toolbar" : "Expand representation toolbar")

            if isRepresentationToolbarExpanded {
                ForEach(MoleculeRepresentation.allCases) { representation in
                    Button {
                        setRepresentation(representation)
                    } label: {
                        Label(representation.title, systemImage: representation.systemImage)
                            .frame(minWidth: 88, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedRepresentation == representation ? .blue : .white.opacity(0.28))
                    .foregroundStyle(.white)
                }

                Divider()
                    .overlay(.white.opacity(0.28))

                ForEach(MoleculeVisibilityFeature.allCases) { feature in
                    Button {
                        toggleVisibility(feature)
                    } label: {
                        Label(feature.title, systemImage: feature.systemImage)
                            .frame(minWidth: 88, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(visibilityStates[feature, default: true] ? .green : .white.opacity(0.28))
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(feature.title) visibility")
                    .accessibilityValue(visibilityStates[feature, default: true] ? "Visible" : "Hidden")
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var selectionBottomSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selection", systemImage: "scope")
                    .font(.headline)

                Spacer()

                Button {
                    isSelectionSheetExpanded.toggle()
                } label: {
                    Label(
                        isSelectionSheetExpanded ? "Collapse selection details" : "Expand selection details",
                        systemImage: isSelectionSheetExpanded ? "chevron.down" : "chevron.up"
                    )
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.28))
                .accessibilityLabel(isSelectionSheetExpanded ? "Collapse selection details" : "Expand selection details")
            }

            if isSelectionSheetExpanded {
                if let selection = bridge.currentSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selection.label ?? "Selected \(selection.type)")
                            .font(.subheadline.weight(.semibold))

                        selectionDetailRow(title: "Model", value: selection.model.map(String.init))
                        selectionDetailRow(title: "Chain", value: selection.chain)
                        selectionDetailRow(title: "Residue", value: selection.residueNumber.map(String.init))
                        selectionDetailRow(title: "Atom", value: selection.atomName)
                    }

                    Button {
                        localErrorMessage = nil
                        bridge.clearSelection()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                } else {
                    Text("No atom or residue selected")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                Text(bridge.currentSelection?.label ?? "No selection")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func selectionDetailRow(title: String, value: String?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 68, alignment: .leading)

            Text(selectionDetailValue(value))
                .fontWeight(.medium)
        }
        .font(.footnote)
    }

    private func selectionDetailValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "Unavailable"
        }

        return value
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
        bridge.setRepresentation(representation.rawValue)
    }

    private func toggleVisibility(_ feature: MoleculeVisibilityFeature) {
        let isVisible = !visibilityStates[feature, default: true]
        visibilityStates[feature] = isVisible
        localErrorMessage = nil
        statusMessage = "\(feature.title) \(isVisible ? "shown" : "hidden")"
        bridge.toggleVisibility(feature: feature.rawValue, isVisible: isVisible)
    }
}

enum MoleculeRepresentation: String, CaseIterable, Identifiable {
    case ribbon
    case surface
    case stick

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .ribbon:
            "Ribbon"
        case .surface:
            "Surface"
        case .stick:
            "Stick"
        }
    }

    var systemImage: String {
        switch self {
        case .ribbon:
            "scribble"
        case .surface:
            "circle.hexagongrid"
        case .stick:
            "line.diagonal"
        }
    }
}

enum MoleculeVisibilityFeature: String, CaseIterable, Identifiable {
    case water
    case ligand
    case disulfide

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .water:
            "Water"
        case .ligand:
            "Ligand"
        case .disulfide:
            "Disulfide"
        }
    }

    var systemImage: String {
        switch self {
        case .water:
            "drop"
        case .ligand:
            "hexagon"
        case .disulfide:
            "link"
        }
    }
}

enum PdbIdentifier {
    static func normalized(_ rawValue: String) throws -> String {
        let pdbId = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard pdbId.range(of: #"^[A-Z0-9]{4}$"#, options: .regularExpression) != nil else {
            throw PdbIdentifierError.invalid
        }

        return pdbId
    }

    static func displayName(from rawValue: String) -> String {
        (try? normalized(rawValue)) ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

enum PdbIdentifierError: LocalizedError, Equatable {
    case invalid

    var errorDescription: String? {
        "Enter a 4-character PDB ID."
    }
}

#Preview {
    MoleculeViewerView()
}
