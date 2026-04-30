import SwiftUI

struct MoleculeViewerView: View {
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var isRepresentationToolbarExpanded = true
    @State private var pdbIdText = ""
    @State private var selectedRepresentation: MoleculeRepresentation = .ribbon
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
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
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
