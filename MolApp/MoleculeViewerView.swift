import SwiftUI

struct MoleculeViewerView: View {
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var statusMessage = "Ready for structure loading"
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
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
    }

    private var viewport: some View {
        MolStarWebView(bridge: bridge)
            .ignoresSafeArea()
    }

    private var errorMessage: String? {
        localErrorMessage ?? bridge.lastErrorMessage
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
}

#Preview {
    MoleculeViewerView()
}
