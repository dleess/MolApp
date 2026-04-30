import SwiftUI

struct MoleculeViewerView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Text("Molecule Viewer")
                .font(.title)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    MoleculeViewerView()
}
