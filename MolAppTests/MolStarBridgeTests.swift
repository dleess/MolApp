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
        XCTAssertEqual(MoleculeVisibilityFeature.disulfide.rawValue, "disulfide")
    }
}
