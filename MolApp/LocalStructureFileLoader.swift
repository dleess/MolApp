import Foundation
import UniformTypeIdentifiers

struct LocalStructureFile {
    let data: String
    let format: String
    let label: String
}

enum LocalStructureFileLoader {
    static let allowedContentTypes: [UTType] = ["pdb", "cif", "mmcif"].compactMap {
        UTType(filenameExtension: $0)
    }

    static func load(from url: URL) throws -> LocalStructureFile {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LocalStructureFileLoaderError.unreadableText
        }

        return LocalStructureFile(
            data: text,
            format: try format(for: url),
            label: url.lastPathComponent
        )
    }

    static func format(for url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdb":
            return "pdb"
        case "cif", "mmcif":
            return "mmcif"
        default:
            throw LocalStructureFileLoaderError.unsupportedExtension(url.pathExtension)
        }
    }
}

enum LocalStructureFileLoaderError: LocalizedError, Equatable {
    case unsupportedExtension(String)
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let fileExtension):
            let suffix = fileExtension.isEmpty ? "selected file" : ".\(fileExtension)"
            return "Unsupported structure file type: \(suffix)."
        case .unreadableText:
            return "Structure file must be UTF-8 text."
        }
    }
}
