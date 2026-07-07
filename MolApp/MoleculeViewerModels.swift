import Foundation

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

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .water:
            "Water"
        case .ligand:
            "Ligand"
        }
    }

    var systemImage: String {
        switch self {
        case .water:
            "drop"
        case .ligand:
            "hexagon"
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
