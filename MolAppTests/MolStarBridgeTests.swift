import XCTest
import WebKit
@testable import MolApp

final class MolStarBridgeTests: XCTestCase {
    private var viewerAuditRunner: ViewerAuditRunner?

    func testViewerAppliesRepresentationsOnlyToSelectionInWebView() throws {
        guard let htmlURL = Bundle.main.url(forResource: "viewer", withExtension: "html") else {
            XCTFail("viewer.html is missing from the host app bundle")
            return
        }

        let auditFinished = expectation(description: "Mol* viewer representation audit finished")
        DispatchQueue.main.async {
            self.viewerAuditRunner = ViewerAuditRunner(htmlURL: htmlURL) { result in
                defer {
                    self.viewerAuditRunner = nil
                    auditFinished.fulfill()
                }

                switch result {
                case .success(let result):
                    XCTAssertEqual(result.pinchType, "function")

                    XCTAssertEqual(result.globalResults["surface"]?.containsRepresentation("molecular-surface"), true)
                    XCTAssertEqual(result.globalResults["ribbon"]?.containsRepresentation("cartoon"), true)
                    XCTAssertEqual(result.globalResults["ribbon"]?.containsRepresentation("molecular-surface"), false)

                    XCTAssertEqual(result.objectResults["surface"]?.containsRepresentation("molecular-surface"), true)
                    XCTAssertEqual(result.objectResults["ribbon"]?.containsRepresentation("cartoon"), true)
                    XCTAssertEqual(result.objectResults["ribbon"]?.containsRepresentation("molecular-surface"), false)

                    XCTAssertEqual(result.stickThenRibbonResults["stick"]?.containsRepresentation("ball-and-stick"), true)
                    XCTAssertEqual(result.stickThenRibbonResults["ribbon"]?.containsRepresentation("cartoon"), true)
                    XCTAssertEqual(result.stickThenRibbonResults["ribbon"]?.containsRepresentation("ball-and-stick"), false)

                    XCTAssertEqual(result.rapidDisplayResults["ribbon"]?.containsRepresentation("cartoon"), true)
                    XCTAssertEqual(result.rapidDisplayResults["ribbon"]?.containsRepresentation("molecular-surface"), false)

                    XCTAssertEqual(result.results["ribbon"]?.component(named: "All")?.reprs, ["ball-and-stick"])
                    XCTAssertEqual(result.results["ribbon"]?.component(named: "All")?.elements, 18)
                    XCTAssertEqual(result.results["ribbon"]?.component(named: "sele")?.reprs, ["cartoon"])
                    XCTAssertEqual(result.results["ribbon"]?.component(named: "sele")?.elements, 9)

                    XCTAssertEqual(result.results["surface"]?.component(named: "All")?.reprs, ["ball-and-stick"])
                    XCTAssertEqual(result.results["surface"]?.component(named: "All")?.elements, 18)
                    XCTAssertEqual(result.results["surface"]?.component(named: "sele")?.reprs, ["molecular-surface"])
                    XCTAssertEqual(result.results["surface"]?.component(named: "sele")?.elements, 9)

                    XCTAssertEqual(result.results["stick"]?.component(named: "All")?.reprs, ["ball-and-stick"])
                    XCTAssertEqual(result.results["stick"]?.component(named: "All")?.elements, 18)
                    XCTAssertEqual(result.results["stick"]?.component(named: "sele")?.reprs, ["ball-and-stick"])
                    XCTAssertEqual(result.results["stick"]?.component(named: "sele")?.elements, 9)
                case .failure(let error):
                    XCTFail("Mol* viewer audit failed: \(error)")
                }
            }
            self.viewerAuditRunner?.start()
        }

        wait(for: [auditFinished], timeout: 90)
    }

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

private struct ViewerAuditResult: Decodable {
    let pinchType: String
    let globalResults: [String: [ViewerComponent]]
    let objectResults: [String: [ViewerComponent]]
    let stickThenRibbonResults: [String: [ViewerComponent]]
    let rapidDisplayResults: [String: [ViewerComponent]]
    let results: [String: [ViewerComponent]]
}

private struct ViewerAuditEnvelope: Decodable {
    let ok: Bool
    let value: ViewerAuditResult?
    let error: String?
}

private struct ViewerComponent: Decodable {
    let label: String
    let elements: Int
    let reprs: [String]
}

private extension Array where Element == ViewerComponent {
    func component(named name: String) -> ViewerComponent? {
        first { $0.label == name }
    }

    func containsRepresentation(_ representation: String) -> Bool {
        contains { $0.reprs.contains(representation) }
    }
}

private final class ViewerAuditRunner: NSObject, WKNavigationDelegate {
    private let completion: (Result<ViewerAuditResult, Error>) -> Void
    private let htmlURL: URL
    private let webView: WKWebView
    private var readyPolls = 0
    private var auditPolls = 0

    init(htmlURL: URL, completion: @escaping (Result<ViewerAuditResult, Error>) -> Void) {
        self.htmlURL = htmlURL
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)

        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = windowScene.windows.first {
            webView.alpha = 0.01
            window.addSubview(webView)
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    deinit {
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollForViewerReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completion(.failure(error))
    }

    private func pollForViewerReady() {
        webView.evaluateJavaScript("Boolean(window.molapp?.viewer?.plugin)") { value, error in
            if let error {
                self.completion(.failure(error))
                return
            }

            if let isReady = value as? Bool, isReady {
                self.evaluateAudit()
                return
            }

            self.readyPolls += 1
            guard self.readyPolls < 120 else {
                self.completion(.failure(ViewerAuditError.timeout("viewer readiness")))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.pollForViewerReady()
            }
        }
    }

    private func evaluateAudit() {
        let pdb = """
    ATOM      1  N   ALA A   1      -2.000   0.000   0.000  1.00 20.00           N
    ATOM      2  CA  ALA A   1      -1.000   0.000   0.000  1.00 20.00           C
    ATOM      3  C   ALA A   1      -0.200   1.200   0.000  1.00 20.00           C
    ATOM      4  O   ALA A   1      -0.500   2.300   0.000  1.00 20.00           O
    ATOM      5  CB  ALA A   1      -1.000  -0.800   1.200  1.00 20.00           C
    ATOM      6  N   GLY A   2       0.900   1.000   0.000  1.00 20.00           N
    ATOM      7  CA  GLY A   2       1.800   2.100   0.000  1.00 20.00           C
    ATOM      8  C   GLY A   2       3.200   1.600   0.000  1.00 20.00           C
    ATOM      9  O   GLY A   2       3.500   0.400   0.000  1.00 20.00           O
    TER      10      GLY A   2
    ATOM     11  N   ALA B   1      -2.000   5.000   0.000  1.00 20.00           N
    ATOM     12  CA  ALA B   1      -1.000   5.000   0.000  1.00 20.00           C
    ATOM     13  C   ALA B   1      -0.200   6.200   0.000  1.00 20.00           C
    ATOM     14  O   ALA B   1      -0.500   7.300   0.000  1.00 20.00           O
    ATOM     15  CB  ALA B   1      -1.000   4.200   1.200  1.00 20.00           C
    ATOM     16  N   GLY B   2       0.900   6.000   0.000  1.00 20.00           N
    ATOM     17  CA  GLY B   2       1.800   7.100   0.000  1.00 20.00           C
    ATOM     18  C   GLY B   2       3.200   6.600   0.000  1.00 20.00           C
    ATOM     19  O   GLY B   2       3.500   5.400   0.000  1.00 20.00           O
    TER      20      GLY B   2
    END
    """
        do {
            let pdbData = try JSONEncoder().encode(pdb)
            let pdbLiteral = String(decoding: pdbData, as: UTF8.self)
            let script = """
    window.__molappAudit = null;
    window.__molappAuditProgress = 'starting';
    (async function () {
      try {
        const pdb = \(pdbLiteral);
        async function cmd(command, payload) {
          return await window.molapp.handleNativeCommand({
            id: Math.random().toString(36).slice(2),
            command,
            payload
          });
        }
        window.__molappAuditProgress = 'loading structure';
        await cmd('loadLocalStructure', { fileName: 'twochain.pdb', format: 'pdb', data: pdb });
        await new Promise(resolve => setTimeout(resolve, 800));
        window.__molappAuditProgress = 'creating selection';
        await cmd('setSelection', { type: 'expression', label: 'sele: chain A', ast: { kind: 'chain', value: 'A' } });
        await new Promise(resolve => setTimeout(resolve, 500));
        function collectComponents() {
          return window.molapp.viewer.plugin.managers.structure.hierarchy.current.structures[0].components.map(c => ({
            label: c.cell.obj?.label,
            elements: c.cell.obj?.data?.elementCount,
            reprs: (c.representations || []).map(r => r.cell.params?.values?.type?.name)
          }));
        }
        const globalResults = {};
        for (const representation of ['surface', 'ribbon']) {
          window.__molappAuditProgress = 'setting global ' + representation;
          await cmd('setRepresentation', { representation });
          await new Promise(resolve => setTimeout(resolve, 600));
          window.__molappAuditProgress = 'collecting global ' + representation;
          globalResults[representation] = collectComponents();
        }
        const objectResults = {};
        for (const representation of ['surface', 'ribbon']) {
          window.__molappAuditProgress = 'setting object ' + representation;
          await cmd('setObjectRepresentation', { name: 'Local structure', representation });
          await new Promise(resolve => setTimeout(resolve, 600));
          window.__molappAuditProgress = 'collecting object ' + representation;
          objectResults[representation] = collectComponents();
        }
        const stickThenRibbonResults = {};
        for (const representation of ['stick', 'ribbon']) {
          window.__molappAuditProgress = 'setting global stick sequence ' + representation;
          await cmd('setRepresentation', { representation });
          await new Promise(resolve => setTimeout(resolve, 600));
          window.__molappAuditProgress = 'collecting global stick sequence ' + representation;
          stickThenRibbonResults[representation] = collectComponents();
        }
        const rapidDisplayResults = {};
        window.__molappAuditProgress = 'setting rapid surface then ribbon';
        const rapidSurface = cmd('setRepresentation', { representation: 'surface' });
        const rapidRibbon = cmd('setRepresentation', { representation: 'ribbon' });
        await Promise.all([rapidSurface, rapidRibbon]);
        await new Promise(resolve => setTimeout(resolve, 600));
        window.__molappAuditProgress = 'collecting rapid ribbon';
        rapidDisplayResults.ribbon = collectComponents();
        const results = {};
        for (const representation of ['ribbon', 'surface', 'stick']) {
          window.__molappAuditProgress = 'setting ' + representation;
          await cmd('setObjectRepresentation', { name: 'sele', representation });
          await new Promise(resolve => setTimeout(resolve, 600));
          window.__molappAuditProgress = 'collecting ' + representation;
          results[representation] = collectComponents();
        }
        window.__molappAuditProgress = 'pinch';
        const pinchType = typeof window.molapp.handleNativePinch;
        window.molapp.handleNativePinch(1.2, 512, 384);
        window.__molappAudit = JSON.stringify({ ok: true, value: { pinchType, globalResults, objectResults, stickThenRibbonResults, rapidDisplayResults, results } });
      } catch (error) {
        window.__molappAudit = JSON.stringify({ ok: false, error: String(error && (error.stack || error.message || error)) });
      }
    })();
    true;
    """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.completion(.failure(error))
                    return
                }

                self.pollForAuditResult()
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func pollForAuditResult() {
        webView.evaluateJavaScript("window.__molappAudit") { value, error in
            if let error {
                self.completion(.failure(error))
                return
            }

            guard let json = value as? String else {
                self.auditPolls += 1
                guard self.auditPolls < 240 else {
                    self.webView.evaluateJavaScript("window.__molappAuditProgress") { progress, _ in
                        self.completion(.failure(ViewerAuditError.timeout(String(describing: progress ?? "unknown"))))
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.pollForAuditResult()
                }
                return
            }

            do {
                let envelope = try JSONDecoder().decode(ViewerAuditEnvelope.self, from: Data(json.utf8))
                if envelope.ok, let result = envelope.value {
                    self.completion(.success(result))
                } else {
                    self.completion(.failure(ViewerAuditError.javascript(envelope.error ?? "unknown error")))
                }
            } catch {
                self.completion(.failure(error))
            }
        }
    }
}

private enum ViewerAuditError: Error {
    case timeout(String)
    case javascript(String)
}
