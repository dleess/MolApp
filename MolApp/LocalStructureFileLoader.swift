import Foundation
import UniformTypeIdentifiers

struct LocalStructureFile {
    let data: String
    let format: String
    let label: String
}

enum LocalStructureFileLoader {
    static let maxFileSize = 64 * 1024 * 1024

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

        let fileFormat = try format(for: url)
        // ponytail: the payload is copied ~5x downstream (JSON encode -> String -> script -> WKWebView
        // IPC), so a large file peaks at several times its size. Cap the input instead of moving the
        // read off-thread; raise the cap if a real structure gets rejected.
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxFileSize else {
            throw LocalStructureFileLoaderError.tooLarge(size)
        }

        let data = try Data(contentsOf: url)
        // fileSizeKey is nil for some providers → the pre-check passes with size 0. Re-check the bytes
        // actually read, before they get amplified ~5x through String → JSON → script → WKWebView IPC.
        guard data.count <= maxFileSize else {
            throw LocalStructureFileLoaderError.tooLarge(data.count)
        }
        // Lossy on purpose: Mol* decodes with a non-fatal TextDecoder, so rejecting a file for one
        // stray Latin-1 byte in a REMARK would be stricter than the viewer that consumes it.
        return LocalStructureFile(
            data: String(decoding: data, as: UTF8.self),
            format: fileFormat,
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
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let fileExtension):
            let suffix = fileExtension.isEmpty ? "selected file" : ".\(fileExtension)"
            return "Unsupported structure file type: \(suffix)."
        case .tooLarge(let size):
            let limit = LocalStructureFileLoader.maxFileSize / (1024 * 1024)
            let actual = size / (1024 * 1024)
            return "Structure file is too large: \(actual) MB (limit \(limit) MB)."
        }
    }
}
