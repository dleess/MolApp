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
    case setBackgroundColor
    case surfacePotential
    case startMorph
    case stopMorph
    case superpose
    case secondaryStructure
    case setMeasureMode
    case clearMeasurements
    case resetAll
    case undo
    case redo
    case loadState
    // Posted by JS whenever it clears measure/morph mode, independent of the command that triggered
    // it: a command can clear these and then fail, so success is not a reliable signal.
    case transientModesStopped
}

struct MolStarCommandResult: Decodable {
    let id: String
    let command: MolStarCommandName?
    let success: Bool
    let error: String?
    let label: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case command
        case success
        case error
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        label = try container.decodeIfPresent(String.self, forKey: .label)

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
    case sphere

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ribbon:       "Ribbon"
        case .surface:      "Surface"
        case .stick:        "Stick"
        case .ballAndStick: "Ball+Stick"
        case .sphere:       "Sphere"
        }
    }

    var shortTitle: String {
        switch self {
        case .ribbon:       "Rib"
        case .surface:      "Sur"
        case .stick:        "Stk"
        case .ballAndStick: "B+S"
        case .sphere:       "Sph"
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
    // Apple Pencil hover: label comes from JS (Mol* hover), point from the native hover
    // recognizer. Tooltip shows only when both are present, gating display to Pencil hover.
    @Published private(set) var hoverLabel: String?
    @Published private(set) var hoverPoint: CGPoint?
    // Last completed distance measurement, as "atomA — atomB" (Å value shown on canvas by Mol*).
    @Published private(set) var lastMeasurement: String?
    // Feature (water/ligand/protein) visibility JS changed on its own (e.g. Surface auto-hides
    // water); the View observes this to keep its Display>Visibility toggles in sync.
    @Published private(set) var featureVisibility: [String: Bool] = [:]

    private weak var webView: WKWebView?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingScripts: [String] = []
    private(set) var isViewerReady = false
    // The viewer never came up at all (fatal init failure). Distinct from !isViewerReady, which is
    // the normal "still booting" state that pendingScripts exists to cover.
    private var isViewerFatal = false

    func attach(webView: WKWebView) {
        self.webView = webView
        isViewerReady = false
        isViewerFatal = false
    }

    func updateHoverPoint(_ point: CGPoint?) {
        hoverPoint = point
        if point == nil, hoverLabel != nil { hoverLabel = nil }
    }

    func loadLocalStructure(data: String, format: String, label: String? = nil) {
        send(.loadLocalStructure, payload: LocalStructurePayload(data: data, format: format, label: label))
    }

    func loadPdbId(_ pdbId: String) {
        send(.loadPdbId, payload: PdbPayload(pdbId: pdbId))
    }

    func setRepresentation(_ representation: String, targets: [String] = []) {
        send(.setRepresentation, payload: RepresentationPayload(representation: representation, targets: targets))
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
    }

    func setObjectRepresentation(name: String, representation: ObjectRepresentation) {
        send(.setObjectRepresentation, payload: ObjectRepresentationPayload(name: name, representation: representation.rawValue))
    }

    func setObjectColor(name: String, colorHex: String?) {
        send(.setObjectColor, payload: ObjectColorPayload(name: name, colorHex: colorHex))
    }

    func setBackgroundColor(colorHex: String) {
        send(.setBackgroundColor, payload: BackgroundColorPayload(colorHex: colorHex))
    }

    func drawSurfacePotential(targets: [String] = []) {
        send(.surfacePotential, payload: TargetedPayload(targets: targets))
    }

    func startMorph(durationInS: Double = 5, loop: Bool = false, targets: [String] = []) {
        send(.startMorph, payload: MorphPayload(durationInS: durationInS, loop: loop, targets: targets))
    }

    func stopMorph() {
        send(.stopMorph, payload: EmptyPayload())
    }

    func superpose(targets: [String] = []) {
        send(.superpose, payload: TargetedPayload(targets: targets))
    }

    func computeSecondaryStructure(targets: [String] = []) {
        send(.secondaryStructure, payload: TargetedPayload(targets: targets))
    }

    func setMeasureMode(_ enabled: Bool, kind: String? = nil) {
        send(.setMeasureMode, payload: MeasureModePayload(enabled: enabled, kind: kind))
    }

    func clearMeasurements() {
        send(.clearMeasurements, payload: EmptyPayload())
    }

    func resetAll() {
        send(.resetAll, payload: EmptyPayload())
    }

    func undo() {
        send(.undo, payload: EmptyPayload())
    }

    func redo() {
        send(.redo, payload: EmptyPayload())
    }

    func loadState(json: String) {
        send(.loadState, payload: StatePayload(json: json))
    }

    // Request/response (not fire-and-forget): the caller needs the returned value, so bypass the
    // serial script queue and await the JS result directly.
    @MainActor
    func serializeState() async -> String? {
        guard let webView else { return nil }
        do {
            let result = try await webView.callAsyncJavaScript(
                "return (window.molapp && window.molapp.serializeMolAppState) ? await window.molapp.serializeMolAppState() : null;",
                arguments: [:], in: nil, contentWorld: .page)
            return result as? String
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func captureImageDataURL() async -> String? {
        guard let webView else { return nil }
        do {
            let result = try await webView.callAsyncJavaScript(
                "return await window.molapp.captureImageDataURL();",
                arguments: [:], in: nil, contentWorld: .page)
            return result as? String
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
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

            enqueueScript("window.molapp.handleNativeCommand(\(json)); void 0;")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func enqueueScript(_ script: String) {
        // Queueing against a viewer that never booted grows without bound: loadLocalStructure
        // embeds the whole structure file in the script, and nothing will ever drain it.
        guard !isViewerFatal else { return }
        pendingScripts.append(script)
        flushPendingScripts()
    }

    private func flushPendingScripts() {
        guard isViewerReady, !pendingScripts.isEmpty, let webView else { return }
        let scripts = pendingScripts
        pendingScripts.removeAll()
        for script in scripts {
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    fileprivate func receive(result: MolStarCommandResult) {
        lastCommandResult = result
        lastErrorMessage = result.success ? nil : result.error
    }

    func receive(messageBody: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: messageBody)

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "viewerReady" {
            isViewerReady = true
            lastErrorMessage = nil
            flushPendingScripts()
            return
        }

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "viewerError" {
            if dict["fatal"] as? Bool == true {
                isViewerReady = false
                isViewerFatal = true
                pendingScripts.removeAll()
            }
            lastErrorMessage = dict["message"] as? String ?? "Mol* viewer error."
            return
        }

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "selectionChanged" {
            currentSelection = try decoder.decode(MolStarSelectionEvent.self, from: data).selection
            return
        }

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "pencilHover" {
            let label = dict["label"] as? String
            if hoverLabel != label { hoverLabel = label }
            return
        }

        if let dict = messageBody as? [String: Any], dict["event"] as? String == "measurement" {
            lastMeasurement = dict["label"] as? String
            return
        }

        // JS split a structure's ligands into per-residue objects (e.g. NAP/JBC/SO4). Surface each
        // as a selection object so it gets its own eye/representation/color row in the Objects panel.
        // addObject is idempotent by name, so a re-split after a representation change won't duplicate.
        if let dict = messageBody as? [String: Any], dict["event"] as? String == "objectsAdded",
           let arr = dict["objects"] as? [[String: Any]] {
            for object in arr {
                guard let name = object["name"] as? String else { continue }
                let representation = (object["representation"] as? String)
                    .flatMap(ObjectRepresentation.init(rawValue:)) ?? .ballAndStick
                addObject(MolAppObject(name: name, type: .selection, isVisible: true, representation: representation))
            }
            return
        }

        // The master Ligand toggle changes per-ligand visibility in JS; mirror it onto the rows so
        // the panel eye icons follow (they are separate native controls from the master toggle).
        if let dict = messageBody as? [String: Any], dict["event"] as? String == "objectsVisibility",
           let arr = dict["items"] as? [[String: Any]] {
            for item in arr {
                guard let name = item["name"] as? String, let isVisible = item["isVisible"] as? Bool else { continue }
                updateObject(name: name) { $0.isVisible = isVisible }
            }
            return
        }

        // JS auto-changed a feature toggle (e.g. Surface hides water); mirror it so the menu label
        // ("Show/Hide Water") stays truthful. The View observes featureVisibility to update its state.
        if let dict = messageBody as? [String: Any], dict["event"] as? String == "featureVisibility",
           let feature = dict["feature"] as? String, let isVisible = dict["isVisible"] as? Bool {
            featureVisibility[feature] = isVisible
            return
        }

        // Undo/redo/reset rebuilt the JS scene; replace the whole panel from the restored state.
        if let dict = messageBody as? [String: Any], dict["event"] as? String == "objectsReplaced",
           let arr = dict["objects"] as? [[String: Any]] {
            var rebuilt: [MolAppObject] = []
            for object in arr {
                guard let name = object["name"] as? String,
                      let typeRaw = object["type"] as? String,
                      let type = MolAppObject.ObjectType(rawValue: typeRaw) else { continue }
                let isVisible = object["isVisible"] as? Bool ?? true
                let representation = (object["representation"] as? String)
                    .flatMap(ObjectRepresentation.init(rawValue:)) ?? (type == .structure ? .ribbon : .ballAndStick)
                let colorHex = object["colorHex"] as? String
                rebuilt.append(MolAppObject(name: name, type: type, isVisible: isVisible, representation: representation, colorHex: colorHex))
            }
            objects = rebuilt
            if let vis = dict["visibility"] as? [String: Bool] { featureVisibility = vis }
            return
        }

        // An event this shell does not handle (the shared viewer serves three shells, and the
        // Flutter one reads events SwiftUI has no UI for) is not a command result — ignore it
        // rather than throwing a decode error into lastErrorMessage and showing a bogus banner.
        if let dict = messageBody as? [String: Any], dict["event"] is String { return }

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

private struct StatePayload: Encodable {
    let json: String
}

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
    let targets: [String]
}

private struct TargetedPayload: Encodable {
    let targets: [String]
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

private struct BackgroundColorPayload: Encodable {
    let colorHex: String
}

private struct MorphPayload: Encodable {
    let durationInS: Double
    let loop: Bool
    let targets: [String]
}

private struct MeasureModePayload: Encodable {
    let enabled: Bool
    let kind: String?
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
