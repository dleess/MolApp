import SwiftUI

enum AppInfo {
    static let version = "0.1"
}

struct ManualView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Command: Identifiable {
        let id = UUID()
        let syntax: String
        let detail: String
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let body: String
        let commands: [Command]
    }

    private let sections: [Section] = [
        Section(
            title: "Loading structures",
            icon: "square.and.arrow.down",
            body: "Open a local PDB/mmCIF file with File ▸ Open Structure, or fetch from the RCSB by entering a 4-character PDB ID and tapping Load PDB. Multiple structures can be loaded at once — each appears in the Objects panel.",
            commands: [
                Command(syntax: "load 1UBQ", detail: "Fetch and display a PDB entry by ID")
            ]
        ),
        Section(
            title: "Objects panel",
            icon: "square.stack.3d.up",
            body: "Every loaded structure and named selection is listed at the bottom-left. The eye toggles a structure's visibility. The colored dot opens a color picker. The Rib / Sur / Stk / B+S buttons switch that object's representation. Calculation and Display actions apply only to the structures currently shown (eye on).",
            commands: [
                Command(syntax: "show NAME / hide NAME", detail: "Show or hide an object (or water / ligand)"),
                Command(syntax: "repr surface NAME", detail: "Set an object's representation"),
                Command(syntax: "color red NAME", detail: "Recolor an object (or 'default')")
            ]
        ),
        Section(
            title: "Selections",
            icon: "lasso",
            body: "Build a named selection from an expression. Combine terms with & (and), | (or), ! (not) and parentheses. Tap an atom in the viewport to select it; double-tap to focus.",
            commands: [
                Command(syntax: "select sele chain A & resn ALA", detail: "Name a selection from an expression"),
                Command(syntax: "res 10-25 · residue 42 · atom CA", detail: "Residue range, single residue, atom name"),
                Command(syntax: "clear · focus", detail: "Clear the selection · frame it in view")
            ]
        ),
        Section(
            title: "Calculation",
            icon: "function",
            body: "Analyses run on the visible structures. Surface Potential draws a molecular surface colored by a screened-Coulomb (APBS-like) electrostatic potential. Secondary Structure assigns helix / sheet / coil (DSSP when the model has none) and colors a cartoon. Superpose aligns visible structures onto the first by sequence alignment plus iterative Cα fitting — sequences need not match. Morph animates through the models of a multi-model structure (NMR ensemble / trajectory).",
            commands: [
                Command(syntax: "surfpot", detail: "Electrostatic potential surface"),
                Command(syntax: "ss", detail: "Secondary structure (DSSP) coloring"),
                Command(syntax: "super", detail: "Superpose the visible structures"),
                Command(syntax: "morph · morph stop", detail: "Start / stop trajectory morph")
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("MolApp is a molecular structure viewer built on Mol*. Use the menu bar, the Objects panel, or the command line at the bottom of the screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.icon)
                                .font(.headline)
                            Text(section.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.commands) { command in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(command.syntax)
                                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                                        Text(command.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Text("MolApp version \(AppInfo.version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle("Manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
