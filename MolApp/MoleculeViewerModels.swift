import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    case protein
    case water
    case ligand

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .protein:
            "Protein"
        case .water:
            "Water"
        case .ligand:
            "Ligand"
        }
    }

    var systemImage: String {
        switch self {
        case .protein:
            "p.circle"
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

// MARK: - Display export (File menu: Export Image / Print)

// Image/document formats the current display can be exported to.
enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case gif
    case svg
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png:  "PNG"
        case .jpeg: "JPEG"
        case .gif:  "GIF"
        case .svg:  "SVG"
        case .pdf:  "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:  "png"
        case .jpeg: "jpg"
        case .gif:  "gif"
        case .svg:  "svg"
        case .pdf:  "pdf"
        }
    }
}

// Mol* hands us a `data:image/png;base64,...` URI from the WebGL viewport; decode to a UIImage.
func imageFromDataURL(_ dataURL: String) -> UIImage? {
    guard let commaIndex = dataURL.firstIndex(of: ","),
          case let base64 = String(dataURL[dataURL.index(after: commaIndex)...]),
          let data = Data(base64Encoded: base64) else { return nil }
    return UIImage(data: data)
}

// The PNG from JS is the source of truth; re-encode it to the requested container natively — this is
// exactly the kind of format work UIKit/ImageIO already do, so no JS-side encoder is needed.
func encodeImage(_ image: UIImage, as format: ExportFormat) -> Data? {
    switch format {
    case .png:
        return image.pngData()
    case .jpeg:
        return image.jpegData(compressionQuality: 0.95)
    case .gif:
        return gifData(from: image)
    case .svg:
        return svgData(from: image)
    case .pdf:
        return pdfData(from: image)
    }
}

// Single-frame GIF via ImageIO. ponytail: one frame — the viewport is a still; upgrade to a real
// animated GIF only if morph-recording export is ever requested.
private func gifData(from image: UIImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.gif.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

// A WebGL viewport is raster, so a true vector SVG is not possible — wrap the PNG in an SVG <image>
// so the .svg opens anywhere an SVG is expected. ponytail: known ceiling, raster inside vector.
private func svgData(from image: UIImage) -> Data? {
    guard let png = image.pngData() else { return nil }
    let width = Int(image.size.width * image.scale)
    let height = Int(image.size.height * image.scale)
    let base64 = png.base64EncodedString()
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
    <image width="\(width)" height="\(height)" xlink:href="data:image/png;base64,\(base64)"/>
    </svg>
    """
    return Data(svg.utf8)
}

private func pdfData(from image: UIImage) -> Data? {
    let bounds = CGRect(origin: .zero, size: image.size)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    return renderer.pdfData { context in
        context.beginPage()
        image.draw(in: bounds)
    }
}

func writeTemporaryFile(named name: String, data: Data) -> URL? {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try data.write(to: url, options: .atomic)
        return url
    } catch {
        return nil
    }
}

func presentPrint(_ image: UIImage) {
    let info = UIPrintInfo.printInfo()
    info.outputType = .photo
    info.jobName = "MolApp"
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = image
    controller.present(animated: true, completionHandler: nil)
}

// Identifiable wrapper so a SwiftUI `.sheet(item:)` can drive the share sheet from a URL.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// The .molapp UTType (extension-based; no Info.plist declaration needed to save or re-open it).
extension UTType {
    static var molApp: UTType { UTType(filenameExtension: "molapp") ?? .json }
}
