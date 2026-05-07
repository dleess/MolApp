import XCTest
@testable import MolApp

final class MolStarBridgeTests: XCTestCase {
    func testCommandResultDecodesKnownCommand() throws {
        let data = """
        {"id":"1","command":"loadPdbId","success":true}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(MolStarCommandResult.self, from: data)

        XCTAssertEqual(result.id, "1")
        XCTAssertEqual(result.command, .loadPdbId)
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
    }

    func testCommandResultKeepsUnknownCommandFailureMessage() throws {
        let data = """
        {"id":"2","command":"unknownCommand","success":false,"error":"Unknown MolApp command: unknownCommand"}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(MolStarCommandResult.self, from: data)

        XCTAssertEqual(result.id, "2")
        XCTAssertNil(result.command)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Unknown MolApp command: unknownCommand")
    }

    func testLocalStructureFileFormatMapsSupportedExtensions() throws {
        XCTAssertEqual(try LocalStructureFileLoader.format(for: URL(filePath: "/tmp/model.pdb")), "pdb")
        XCTAssertEqual(try LocalStructureFileLoader.format(for: URL(filePath: "/tmp/model.cif")), "mmcif")
        XCTAssertEqual(try LocalStructureFileLoader.format(for: URL(filePath: "/tmp/model.mmcif")), "mmcif")
    }

    func testLocalStructureFileFormatRejectsUnsupportedExtension() {
        XCTAssertThrowsError(try LocalStructureFileLoader.format(for: URL(filePath: "/tmp/model.txt"))) { error in
            XCTAssertEqual(error as? LocalStructureFileLoaderError, .unsupportedExtension("txt"))
        }
    }

    func testPdbIdentifierNormalizesValidInput() throws {
        XCTAssertEqual(try PdbIdentifier.normalized(" 1abc "), "1ABC")
        XCTAssertEqual(try PdbIdentifier.normalized("7tim"), "7TIM")
    }

    func testPdbIdentifierRejectsInvalidInput() {
        XCTAssertThrowsError(try PdbIdentifier.normalized("abc")) { error in
            XCTAssertEqual(error as? PdbIdentifierError, .invalid)
        }

        XCTAssertThrowsError(try PdbIdentifier.normalized("12-4")) { error in
            XCTAssertEqual(error as? PdbIdentifierError, .invalid)
        }
    }

    func testVisibilityFeatureKeysMatchBridgePayloadContract() {
        XCTAssertEqual(MoleculeVisibilityFeature.water.rawValue, "water")
        XCTAssertEqual(MoleculeVisibilityFeature.ligand.rawValue, "ligand")
    }

    func testBridgeReceivesSelectionChangedEvent() throws {
        let bridge = MolStarBridge()

        try bridge.receive(messageBody: [
            "event": "selectionChanged",
            "selection": [
                "type": "atom",
                "label": "GLY A 1 CA",
                "model": 1,
                "chain": "A",
                "residueNumber": 1,
                "atomName": "CA"
            ]
        ])

        XCTAssertEqual(
            bridge.currentSelection,
            MoleculeSelection(type: "atom", label: "GLY A 1 CA", model: 1, chain: "A", residueNumber: 1, atomName: "CA")
        )
    }

    func testBridgeClearsSelectionFromSelectionChangedEvent() throws {
        let bridge = MolStarBridge()

        try bridge.receive(messageBody: [
            "event": "selectionChanged",
            "selection": [
                "type": "atom",
                "label": "GLY A 1 CA",
                "model": 1,
                "chain": "A",
                "residueNumber": 1,
                "atomName": "CA"
            ]
        ])
        try bridge.receive(messageBody: [
            "event": "selectionChanged",
            "selection": NSNull()
        ])

        XCTAssertNil(bridge.currentSelection)
        }

        func testSelectionExpressionParserHandlesBasicTerms() throws {
        var parser = SelectionExpressionParser(expression: "chain A")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .chain)
        XCTAssertEqual(ast.value, "A")
        }

        func testSelectionExpressionParserHandlesNotOperator() throws {
        var parser = SelectionExpressionParser(expression: "!chain A")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .not)
        XCTAssertEqual(ast.operand?[0].kind, .chain)
        XCTAssertEqual(ast.operand?[0].value, "A")
        }

        func testSelectionExpressionParserHandlesAndOperator() throws {
        var parser = SelectionExpressionParser(expression: "chain A & residue 10")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .and)
        XCTAssertEqual(ast.left?[0].kind, .chain)
        XCTAssertEqual(ast.left?[0].value, "A")
        XCTAssertEqual(ast.right?[0].kind, .residue)
        XCTAssertEqual(ast.right?[0].value, "10")
        }

        func testSelectionExpressionParserHandlesOrOperator() throws {
        var parser = SelectionExpressionParser(expression: "chain A | chain B")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .or)
        XCTAssertEqual(ast.left?[0].value, "A")
        XCTAssertEqual(ast.right?[0].value, "B")
        }

        func testSelectionExpressionParserHandlesPrecedence() throws {
        var parser = SelectionExpressionParser(expression: "chain A | chain B & residue 10")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .or)
        XCTAssertEqual(ast.left?[0].value, "A")
        XCTAssertEqual(ast.right?[0].kind, .and)
        }

        func testSelectionExpressionParserHandlesParentheses() throws {
        var parser = SelectionExpressionParser(expression: "(chain A | chain B) & residue 10")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .and)
        XCTAssertEqual(ast.left?[0].kind, .or)
        XCTAssertEqual(ast.right?[0].kind, .residue)
        }

        func testSelectionExpressionParserThrowsOnInvalidInput() {
            XCTAssertThrowsError(try {
                var p = SelectionExpressionParser(expression: "chain A &")
                _ = try p.parse()
            }())
            XCTAssertThrowsError(try {
                var p = SelectionExpressionParser(expression: "(chain A")
                _ = try p.parse()
            }())
            XCTAssertThrowsError(try {
                var p = SelectionExpressionParser(expression: "unknown term")
                _ = try p.parse()
            }())
        }

    func testSelectionExpressionParserHandlesResAsSingleResidue() throws {
        var parser = SelectionExpressionParser(expression: "res 42")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .residue)
        XCTAssertEqual(ast.value, "42")
    }

    func testSelectionExpressionParserHandlesResAsRange() throws {
        var parser = SelectionExpressionParser(expression: "res 3-42")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .residueRange)
        XCTAssertEqual(ast.value, "3-42")
    }

    func testSelectionExpressionParserHandlesResnTerm() throws {
        var parser = SelectionExpressionParser(expression: "resn ala")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .residueName)
        XCTAssertEqual(ast.value, "ALA")
    }

    func testSelectionExpressionParserHandlesModelTerm() throws {
        var parser = SelectionExpressionParser(expression: "model 2")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .model)
        XCTAssertEqual(ast.value, "2")
    }

    func testSelectionExpressionParserHandlesAndTextKeyword() throws {
        var parser = SelectionExpressionParser(expression: "chain a and res 10")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .and)
        XCTAssertEqual(ast.left?[0].kind, .chain)
        XCTAssertEqual(ast.right?[0].kind, .residue)
    }

    func testSelectionExpressionParserHandlesOrTextKeyword() throws {
        var parser = SelectionExpressionParser(expression: "chain a or chain b")
        let ast = try parser.parse()
        XCTAssertEqual(ast.kind, .or)
        XCTAssertEqual(ast.left?[0].value, "A")
        XCTAssertEqual(ast.right?[0].value, "B")
    }

    func testExtractNameWhenFirstTokenIsNotKeyword() {
        let (name, expr) = SelectionExpressionParser.extractName(from: "mysel chain A")
        XCTAssertEqual(name, "mysel")
        XCTAssertEqual(expr, "chain A")
    }

    func testExtractNameDefaultsToSeleForKeyword() {
        let (name, expr) = SelectionExpressionParser.extractName(from: "chain A")
        XCTAssertEqual(name, "sele")
        XCTAssertEqual(expr, "chain A")
    }

    func testObjectRepresentationRawValues() {
        XCTAssertEqual(ObjectRepresentation.ribbon.rawValue, "ribbon")
        XCTAssertEqual(ObjectRepresentation.surface.rawValue, "surface")
        XCTAssertEqual(ObjectRepresentation.stick.rawValue, "stick")
        XCTAssertEqual(ObjectRepresentation.ballAndStick.rawValue, "ballAndStick")
    }

    func testMolAppObjectDefaultValues() {
        let obj = MolAppObject(name: "1crn", type: .structure)
        XCTAssertTrue(obj.isVisible)
        XCTAssertEqual(obj.representation, .ribbon)
        XCTAssertNil(obj.colorHex)
    }

    func testBridgeAddObjectAppends() {
        let bridge = MolStarBridge()
        bridge.addObject(MolAppObject(name: "1crn", type: .structure))
        XCTAssertEqual(bridge.objects.count, 1)
        XCTAssertEqual(bridge.objects[0].name, "1crn")
    }

    func testBridgeAddObjectUpdatesExisting() {
        let bridge = MolStarBridge()
        bridge.addObject(MolAppObject(name: "1crn", type: .structure))
        var updated = MolAppObject(name: "1crn", type: .structure)
        updated.representation = .surface
        bridge.addObject(updated)
        XCTAssertEqual(bridge.objects.count, 1)
        XCTAssertEqual(bridge.objects[0].representation, .surface)
    }

    func testBridgeAddObjectSelectionType() {
        let bridge = MolStarBridge()
        bridge.addObject(MolAppObject(name: "mysel", type: .selection))
        XCTAssertEqual(bridge.objects[0].type, .selection)
    }
}
