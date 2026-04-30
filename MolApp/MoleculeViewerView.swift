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
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.05, blue: 0.07),
                        Color(red: 0.11, green: 0.13, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 2)
                    .frame(width: 240, height: 240)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding()
            }
            .ignoresSafeArea()
    }
}

#Preview {
    MoleculeViewerView()
}
