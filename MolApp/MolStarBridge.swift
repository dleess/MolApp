import Foundation
import SwiftUI
import WebKit

enum MolStarCommandName: String, Codable {
    case loadLocalStructure
    case loadPdbId
    case setRepresentation
    case toggleVisibility
    case focusSelection
    case setSelection
    case clearSelection
    case setObjectVisibility
    case setObjectRepresentation
    case setObjectColor
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

enum ObjectRepresentation: String, Codable, CaseIterable, Identifiable {
    case ribbon
    case surface
    case stick
    case ballAndStick = "ballAndStick"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ribbon:       "Ribbon"
        case .surface:      "Surface"
        case .stick:        "Stick"
        case .ballAndStick: "Ball+Stick"
        }
    }

    var shortTitle: String {
        switch self {
        case .ribbon:       "Rib"
        case .surface:      "Sur"
        case .stick:        "Stk"
        case .ballAndStick: "B+S"
        }
    }
}

struct MolAppObject: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String

    enum ObjectType: String, Codable { case structure, selection }
    let type: ObjectType

    var isVisible: Bool = true
    var representation: ObjectRepresentation = .ribbon
    var colorHex: String? = nil

    var swiftUIColor: Color {
        guard let hex = colorHex else { return .white.opacity(0.3) }
        return Color(hex: hex) ?? .white.opacity(0.3)
    }
}

struct SelectionAST: Codable, Equatable {
    enum Kind: String, Codable {
        case and, or, not, chain, residue, residueRange, residueName, atom, model
    }
    let kind: Kind
    var left: [SelectionAST]?
    var right: [SelectionAST]?
    var operand: [SelectionAST]?
    let value: String?
}

struct MoleculeSelection: Codable, Equatable {
    let type: String
    let label: String?
    let model: Int?
    let chain: String?
    let residueNumber: Int?
    let atomName: String?
    let ast: SelectionAST?

    init(
        type: String,
        label: String? = nil,
        model: Int? = nil,
        chain: String? = nil,
        residueNumber: Int? = nil,
        atomName: String? = nil,
        ast: SelectionAST? = nil
    ) {
        self.type = type
        self.label = label
        self.model = model
        self.chain = chain
        self.residueNumber = residueNumber
        self.atomName = atomName
        self.ast = ast
    }
}

final class MolStarBridge: NSObject, ObservableObject {
    @Published private(set) var lastCommandResult: MolStarCommandResult?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var currentSelection: MoleculeSelection?
    @Published private(set) var objects: [MolAppObject] = []

    private weak var webView: WKWebView?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingScripts: [String] = []
    private var isEvaluatingScript = false

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

    func setSelection(_ selection: MoleculeSelection) {
        send(.setSelection, payload: selection)
    }

    func clearSelection() {
        send(.clearSelection, payload: EmptyPayload())
    }

    func addObject(_ object: MolAppObject) {
        if let idx = objects.firstIndex(where: { $0.name == object.name }) {
            objects[idx] = object
        } else {
            objects.append(object)
        }
    }

    func setObjectVisibility(name: String, isVisible: Bool) {
        send(.setObjectVisibility, payload: ObjectVisibilityPayload(name: name, isVisible: isVisible))
        updateObject(name: name) { $0.isVisible = isVisible }
    }

    func setObjectRepresentation(name: String, representation: ObjectRepresentation) {
        send(.setObjectRepresentation, payload: ObjectRepresentationPayload(name: name, representation: representation.rawValue))
        updateObject(name: name) { $0.representation = representation }
    }

    func setObjectColor(name: String, colorHex: String?) {
        send(.setObjectColor, payload: ObjectColorPayload(name: name, colorHex: colorHex))
        updateObject(name: name) { $0.colorHex = colorHex }
    }

    private func updateObject(name: String, update: (inout MolAppObject) -> Void) {
        if let idx = objects.firstIndex(where: { $0.name == name }) {
            update(&objects[idx])
        }
    }

    private func send<Payload: Encodable>(_ command: MolStarCommandName, payload: Payload) {
        do {
            let envelope = CommandEnvelope(id: UUID().uuidString, command: command, payload: payload)
            let data = try encoder.encode(envelope)
            guard let json = String(data: data, encoding: .utf8) else {
                lastErrorMessage = "Unable to encode \(command.rawValue) command."
                return
            }

            enqueueScript("window.molapp.handleNativeCommand(\(json));")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func enqueueScript(_ script: String) {
        pendingScripts.append(script)
        evaluateNextScriptIfNeeded()
    }

    private func evaluateNextScriptIfNeeded() {
        guard !isEvaluatingScript, !pendingScripts.isEmpty else { return }
        guard let webView else {
            pendingScripts.removeAll()
            return
        }

        isEvaluatingScript = true
        let script = pendingScripts.removeFirst()
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
            self.isEvaluatingScript = false
            self.evaluateNextScriptIfNeeded()
        }
    }

    fileprivate func receive(result: MolStarCommandResult) {
        lastCommandResult = result
        lastErrorMessage = result.success ? nil : result.error
    }

    func receive(messageBody: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: messageBody)

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "selectionChanged" {
            currentSelection = try decoder.decode(MolStarSelectionEvent.self, from: data).selection
            return
        }

        receive(result: try decoder.decode(MolStarCommandResult.self, from: data))
    }
}

extension MolStarBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "molapp" else { return }

        do {
            try receive(messageBody: message.body)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

private struct MolStarSelectionEvent: Decodable {
    let event: String
    let selection: MoleculeSelection?
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

private struct ObjectVisibilityPayload: Encodable {
    let name: String
    let isVisible: Bool
}

private struct ObjectRepresentationPayload: Encodable {
    let name: String
    let representation: String
}

private struct ObjectColorPayload: Encodable {
    let name: String
    let colorHex: String?
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
