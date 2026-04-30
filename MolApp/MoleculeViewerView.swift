import SwiftUI

struct MoleculeViewerView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            viewport

            VStack(alignment: .leading, spacing: 8) {
                Text("Molecule Viewer")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Ready for structure loading")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
    }

    private var viewport: some View {
        MolStarWebView()
            .ignoresSafeArea()
    }
}

#Preview {
    MoleculeViewerView()
}
