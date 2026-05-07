import SwiftUI

struct MoleculeViewerView: View {
    @StateObject private var bridge = MolStarBridge()
    @State private var isFileImporterPresented = false
    @State private var pdbIdText = ""
    @State private var selectedRepresentation: MoleculeRepresentation = .ribbon
    @State private var visibilityStates: [MoleculeVisibilityFeature: Bool] = [
        .water: true,
        .ligand: true
    ]
    @State private var statusMessage = "Ready for structure loading"
    @State private var localErrorMessage: String?
    @State private var pendingStructureLabel: String?
    @State private var commandText = ""
    @State private var isObjectsPanelExpanded = true
    @State private var colorPickerTarget: String? = nil

    var body: some View {
        ZStack {
            viewport

            menuBar

            VStack(alignment: .leading, spacing: 8) {
                Text("Molecule Viewer")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))

                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Open Structure", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                HStack(spacing: 8) {
                    TextField("PDB ID", text: $pdbIdText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                        .onSubmit(loadPdbId)

                    Button {
                        loadPdbId()
                    } label: {
                        Label("Load PDB", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(pdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding()
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            objectsPanel

            VStack(spacing: 0) {
                Spacer()
                commandBar
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: LocalStructureFileLoader.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onReceive(bridge.$lastErrorMessage) { message in
            localErrorMessage = message
        }
        .onReceive(bridge.$lastCommandResult) { result in
            guard let result, result.success else { return }

            switch result.command {
            case .loadLocalStructure:
                let label = pendingStructureLabel ?? "Structure"
                statusMessage = "Loaded \(label)"
                bridge.addObject(MolAppObject(name: label, type: .structure))
                pendingStructureLabel = nil
            case .loadPdbId:
                let name = pdbIdText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = "Loaded \(PdbIdentifier.displayName(from: pdbIdText))"
                bridge.addObject(MolAppObject(name: name, type: .structure))
            case .setRepresentation:
                statusMessage = "\(selectedRepresentation.title) representation"
            default:
                break
            }
        }
    }

    private var viewport: some View {
        MolStarWebView(bridge: bridge)
            .ignoresSafeArea()
    }

    private var errorMessage: String? {
        localErrorMessage ?? bridge.lastErrorMessage
    }

    private var menuBar: some View {
        HStack(spacing: 20) {
            Menu("File") {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Open Structure", systemImage: "folder")
                }

                Button {
                    loadPdbId()
                } label: {
                    Label("Load PDB ID", systemImage: "square.and.arrow.down")
                }
                .disabled(pdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Menu("Edit") {
                Button {
                    localErrorMessage = nil
                    bridge.clearSelection()
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
            }

            Menu("Display") {
                Section("Representation") {
                    ForEach(MoleculeRepresentation.allCases) { representation in
                        Button {
                            setRepresentation(representation)
                        } label: {
                            Label(representation.title, systemImage: representation.systemImage)
                        }
                    }
                }

                Section("Visibility") {
                    ForEach(MoleculeVisibilityFeature.allCases) { feature in
                        Button {
                            toggleVisibility(feature)
                        } label: {
                            Label(
                                "\(visibilityStates[feature, default: true] ? "Hide" : "Show") \(feature.title)",
                                systemImage: feature.systemImage
                            )
                        }
                    }
                }
            }

            Menu("Calculation") {
                Button {
                    statusMessage = "Calculation tools unavailable"
                } label: {
                    Label("No Calculations Available", systemImage: "function")
                }
                .disabled(true)
            }

            Menu("Help") {
                Button {
                    statusMessage = "Open a PDB/mmCIF file or enter a PDB ID"
                } label: {
                    Label("Viewer Help", systemImage: "questionmark.circle")
                }
            }

            Spacer()
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.leading, 80)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.68))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private var commandBar: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.white.opacity(0.6))
            
            TextField("Enter command (e.g. load 1crn, repr surface)...", text: $commandText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(executeCommand)
            
            if !commandText.isEmpty {
                Button {
                    commandText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
    }

    private func executeCommand() {
        let input = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        commandText = ""
        let components = input.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let command = components.first else { return }
        
        switch command {
        case "load":
            if components.count >= 2 {
                pdbIdText = components[1].uppercased()
                loadPdbId()
            } else {
                localErrorMessage = "Usage: load [PDB_ID]"
            }
        case "repr":
            if components.count >= 3 {
                let reprStr = components[1]
                let objName = components[2]
                if let repr = ObjectRepresentation(rawValue: reprStr) {
                    bridge.setObjectRepresentation(name: objName, representation: repr)
                } else {
                    localErrorMessage = "Invalid representation. Use: \(ObjectRepresentation.allCases.map(\.rawValue).joined(separator: ", "))"
                }
            } else if components.count >= 2 {
                if let repr = MoleculeRepresentation(rawValue: components[1]) {
                    setRepresentation(repr)
                } else {
                    localErrorMessage = "Invalid representation. Use: \(MoleculeRepresentation.allCases.map(\.rawValue).joined(separator: ", "))"
                }
            } else {
                localErrorMessage = "Usage: repr [ribbon|surface|stick|ballAndStick] [name?]"
            }
        case "show", "hide":
            if components.count >= 2 {
                let arg = components[1]
                let isVisible = (command == "show")
                if let feature = MoleculeVisibilityFeature(rawValue: arg) {
                    if visibilityStates[feature] != isVisible {
                        toggleVisibility(feature)
                    }
                } else {
                    bridge.setObjectVisibility(name: arg, isVisible: isVisible)
                }
            } else {
                localErrorMessage = "Usage: \(command) [water|ligand|objectname]"
            }
        case "select":
            let afterSelect = input.dropping(first: 6).trimmingCharacters(in: .whitespaces)
            if afterSelect.isEmpty {
                localErrorMessage = "Usage: select [name] [expression] (e.g. select sele chain A & resn ala)"
            } else {
                let (selectionName, expression) = SelectionExpressionParser.extractName(from: afterSelect)
                do {
                    var parser = SelectionExpressionParser(expression: expression.lowercased())
                    let ast = try parser.parse()
                    let selection = MoleculeSelection(type: "expression", label: "\(selectionName): \(expression)", ast: ast)
                    bridge.setSelection(selection)
                    bridge.addObject(MolAppObject(name: selectionName, type: .selection))
                } catch {
                    localErrorMessage = error.localizedDescription
                }
            }
        case "color":
            if components.count >= 3 {
                let colorArg = components[1]
                let objName = components[2]
                let colorHex: String? = colorArg == "default" ? nil : colorNameToHex(colorArg)
                bridge.setObjectColor(name: objName, colorHex: colorHex)
            } else {
                localErrorMessage = "Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]"
            }
        case "clear":
            bridge.clearSelection()
        case "focus":
            bridge.focusSelection()
        default:
            localErrorMessage = "Unknown command: \(command)"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let structure = try LocalStructureFileLoader.load(from: url)
            statusMessage = "Loading \(structure.label)"
            pendingStructureLabel = structure.label
            localErrorMessage = nil
            bridge.loadLocalStructure(data: structure.data, format: structure.format, label: structure.label)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func loadPdbId() {
        do {
            let pdbId = try PdbIdentifier.normalized(pdbIdText)
            pdbIdText = pdbId
            statusMessage = "Loading \(pdbId)"
            pendingStructureLabel = pdbId
            localErrorMessage = nil
            bridge.loadPdbId(pdbId)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func setRepresentation(_ representation: MoleculeRepresentation) {
        selectedRepresentation = representation
        localErrorMessage = nil
        bridge.setRepresentation(representation.rawValue)
    }

    private func toggleVisibility(_ feature: MoleculeVisibilityFeature) {
        let isVisible = !visibilityStates[feature, default: true]
        visibilityStates[feature] = isVisible
        localErrorMessage = nil
        statusMessage = "\(feature.title) \(isVisible ? "shown" : "hidden")"
        bridge.toggleVisibility(feature: feature.rawValue, isVisible: isVisible)
    }

    private static let namedColors: [String: String] = [
        "red": "#FF4444", "green": "#44FF44", "blue": "#4444FF",
        "yellow": "#FFFF44", "white": "#FFFFFF", "cyan": "#44FFFF",
        "magenta": "#FF44FF", "orange": "#FF8844"
    ]

    private func colorNameToHex(_ name: String) -> String {
        if name.hasPrefix("#") { return name }
        return Self.namedColors[name] ?? "#FFFFFF"
    }

    private var objectsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isObjectsPanelExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Objects")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: isObjectsPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if isObjectsPanelExpanded {
                if bridge.objects.isEmpty {
                    Text("No objects")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(bridge.objects) { object in
                        objectRow(object)
                        if object.id != bridge.objects.last?.id {
                            Divider().overlay(.white.opacity(0.15))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 16)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func objectRow(_ object: MolAppObject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    bridge.setObjectVisibility(name: object.name, isVisible: !object.isVisible)
                } label: {
                    Image(systemName: object.isVisible ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(object.isVisible ? .white : .white.opacity(0.35))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(object.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(object.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Circle()
                    .fill(object.swiftUIColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                    .onTapGesture { colorPickerTarget = object.name }
                    .popover(isPresented: Binding(
                        get: { colorPickerTarget == object.name },
                        set: { if !$0 { colorPickerTarget = nil } }
                    )) {
                        colorPickerPopover(for: object.name)
                    }
            }

            HStack(spacing: 4) {
                ForEach(ObjectRepresentation.allCases) { repr in
                    Button(repr.shortTitle) {
                        bridge.setObjectRepresentation(name: object.name, representation: repr)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        object.representation == repr
                            ? Color.white.opacity(0.25)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                    .foregroundStyle(
                        object.representation == repr ? .white : .white.opacity(0.6)
                    )
                }
            }
        }
    }

    private static let pickerColors: [(label: String, key: String)] = [
        ("Default", "default"), ("Red", "red"), ("Green", "green"),
        ("Blue", "blue"), ("Yellow", "yellow"), ("White", "white"),
        ("Cyan", "cyan"), ("Magenta", "magenta"), ("Orange", "orange")
    ]
    private static let colorPickerColumns = Array(repeating: GridItem(.fixed(34)), count: 5)

    private func colorPickerPopover(for name: String) -> some View {
        return VStack(spacing: 8) {
            Text("Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            LazyVGrid(columns: Self.colorPickerColumns, spacing: 8) {
                ForEach(Self.pickerColors, id: \.key) { item in
                    let hex: String? = item.key == "default" ? nil : colorNameToHex(item.key)
                    Button {
                        bridge.setObjectColor(name: name, colorHex: hex)
                        colorPickerTarget = nil
                    } label: {
                        Circle()
                            .fill(hex.flatMap { Color(hex: $0) } ?? Color.gray.opacity(0.4))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .presentationCompactAdaptation(.popover)
    }
}

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

#Preview {
    MoleculeViewerView()
}

struct SelectionExpressionParser {
    let tokens: [String]
    var index = 0
    
    init(expression: String) {
        let symbols = ["&", "|", "!", "(", ")"]
        var expr = expression
        for s in symbols {
            expr = expr.replacingOccurrences(of: s, with: " \(s) ")
        }
        self.tokens = expr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    
    mutating func parse() throws -> SelectionAST {
        let ast = try parseOr()
        if index < tokens.count {
            throw ParserError.unexpectedToken(tokens[index])
        }
        return ast
    }
    
    private mutating func parseOr() throws -> SelectionAST {
        var node = try parseAnd()
        while index < tokens.count && (tokens[index] == "|" || tokens[index] == "or") {
            index += 1
            let right = try parseAnd()
            node = SelectionAST(kind: .or, left: [node], right: [right], operand: nil, value: nil)
        }
        return node
    }
    
    private mutating func parseAnd() throws -> SelectionAST {
        var node = try parseNot()
        while index < tokens.count && (tokens[index] == "&" || tokens[index] == "and") {
            index += 1
            let right = try parseNot()
            node = SelectionAST(kind: .and, left: [node], right: [right], operand: nil, value: nil)
        }
        return node
    }
    
    private mutating func parseNot() throws -> SelectionAST {
        if index < tokens.count && tokens[index] == "!" {
            index += 1
            let operand = try parseNot()
            return SelectionAST(kind: .not, left: nil, right: nil, operand: [operand], value: nil)
        }
        return try parsePrimary()
    }
    
    private mutating func parsePrimary() throws -> SelectionAST {
        guard index < tokens.count else {
            throw ParserError.unexpectedEOF
        }
        
        let token = tokens[index]
        if token == "(" {
            index += 1
            let node = try parseOr()
            guard index < tokens.count && tokens[index] == ")" else {
                throw ParserError.missingClosingParen
            }
            index += 1
            return node
        }
        
        if token == "chain" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("chain") }
            let value = tokens[index].uppercased()
            index += 1
            return SelectionAST(kind: .chain, left: nil, right: nil, operand: nil, value: value)
        } else if token == "residue" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("residue") }
            let value = tokens[index]
            index += 1
            return SelectionAST(kind: .residue, left: nil, right: nil, operand: nil, value: value)
        } else if token == "atom" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("atom") }
            let value = tokens[index].uppercased()
            index += 1
            return SelectionAST(kind: .atom, left: nil, right: nil, operand: nil, value: value)
        } else if token == "res" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("res") }
            let value = tokens[index]
            index += 1
            if value.contains("-") {
                return SelectionAST(kind: .residueRange, left: nil, right: nil, operand: nil, value: value)
            } else {
                return SelectionAST(kind: .residue, left: nil, right: nil, operand: nil, value: value)
            }
        } else if token == "resn" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("resn") }
            let value = tokens[index].uppercased()
            index += 1
            return SelectionAST(kind: .residueName, left: nil, right: nil, operand: nil, value: value)
        } else if token == "model" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("model") }
            let value = tokens[index]
            index += 1
            return SelectionAST(kind: .model, left: nil, right: nil, operand: nil, value: value)
        }

        throw ParserError.unexpectedToken(token)
    }

    static let selectionKeywords: Set<String> = [
        "chain", "residue", "res", "resn", "atom", "model", "not", "and", "or"
    ]

    static func extractName(from afterSelect: String) -> (name: String, expression: String) {
        let parts = afterSelect.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 2 && !selectionKeywords.contains(parts[0].lowercased()) {
            return (parts[0], parts.dropFirst().joined(separator: " "))
        }
        return ("sele", afterSelect)
    }

    enum ParserError: Error, LocalizedError {
        case unexpectedToken(String)
        case unexpectedEOF
        case missingClosingParen
        case missingValue(String)
        
        var errorDescription: String? {
            switch self {
            case .unexpectedToken(let t): "Unexpected token: \(t)"
            case .unexpectedEOF: "Unexpected end of expression"
            case .missingClosingParen: "Missing closing parenthesis"
            case .missingValue(let t): "Missing value for \(t)"
            }
        }
    }
}

extension String {
    func dropping(first count: Int) -> String {
        guard count <= self.count else { return "" }
        return String(self.dropFirst(count))
    }
}
