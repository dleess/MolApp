import Foundation
import WebKit

enum MolStarCommandName: String, Codable {
    case loadLocalStructure
    case loadPdbId
    case setRepresentation
    case toggleVisibility
    case focusSelection
    case setSelection
    case clearSelection
}

struct MolStarCommandResult: Decodable {
    let id: String
    let command: MolStarCommandName?
    let success: Bool
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case command
        case success
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        if let rawCommand = try container.decodeIfPresent(String.self, forKey: .command) {
            command = MolStarCommandName(rawValue: rawCommand)
        } else {
            command = nil
        }
    }
}

final class MolStarBridge: NSObject, ObservableObject {
    @Published private(set) var lastCommandResult: MolStarCommandResult?
    @Published private(set) var lastErrorMessage: String?

    private weak var webView: WKWebView?
    private let encoder = JSONEncoder()

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func loadLocalStructure(data: String, format: String, label: String? = nil) {
        send(.loadLocalStructure, payload: LocalStructurePayload(data: data, format: format, label: label))
    }

    func loadPdbId(_ pdbId: String) {
        send(.loadPdbId, payload: PdbPayload(pdbId: pdbId))
    }

    func setRepresentation(_ representation: String) {
        send(.setRepresentation, payload: RepresentationPayload(representation: representation))
    }

    func toggleVisibility(feature: String, isVisible: Bool) {
        send(.toggleVisibility, payload: VisibilityPayload(feature: feature, isVisible: isVisible))
    }

    func focusSelection() {
        send(.focusSelection, payload: EmptyPayload())
    }

    func setSelection(_ selection: SelectionPayload) {
        send(.setSelection, payload: selection)
    }

    func clearSelection() {
        send(.clearSelection, payload: EmptyPayload())
    }

    private func send<Payload: Encodable>(_ command: MolStarCommandName, payload: Payload) {
        do {
            let envelope = CommandEnvelope(id: UUID().uuidString, command: command, payload: payload)
            let data = try encoder.encode(envelope)
            guard let json = String(data: data, encoding: .utf8) else {
                lastErrorMessage = "Unable to encode \(command.rawValue) command."
                return
            }

            webView?.evaluateJavaScript("window.molapp.handleNativeCommand(\(json));")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    fileprivate func receive(result: MolStarCommandResult) {
        lastCommandResult = result
        lastErrorMessage = result.success ? nil : result.error
    }
}

extension MolStarBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "molapp" else { return }

        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let result = try JSONDecoder().decode(MolStarCommandResult.self, from: data)
            receive(result: result)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

private struct CommandEnvelope<Payload: Encodable>: Encodable {
    let id: String
    let command: MolStarCommandName
    let payload: Payload
}

private struct EmptyPayload: Encodable {}

private struct LocalStructurePayload: Encodable {
    let data: String
    let format: String
    let label: String?
}

private struct PdbPayload: Encodable {
    let pdbId: String
}

private struct RepresentationPayload: Encodable {
    let representation: String
}

private struct VisibilityPayload: Encodable {
    let feature: String
    let isVisible: Bool
}

struct SelectionPayload: Encodable {
    let type: String
    let label: String?
    let model: Int?
    let chain: String?
    let residueNumber: Int?
    let atomName: String?
}
