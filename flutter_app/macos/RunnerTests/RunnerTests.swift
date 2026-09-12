import Cocoa
import FlutterMacOS
import XCTest
@testable import MolApp

class RunnerTests: XCTestCase {

  func testAtomicSaveCreatesAndReplacesTheSelectedFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("saved.molapp")
    for value in ["first state", "replacement state"] {
      let data = Data(value.utf8)
      var completed = false
      MainFlutterWindow.handleFileMethod(FlutterMethodCall(methodName: "writeAtomically", arguments: [
        "path": target.path, "bytes": FlutterStandardTypedData(bytes: data)
      ])) { result in
        XCTAssertNil(result)
        completed = true
      }
      XCTAssertTrue(completed)
      XCTAssertEqual(try Data(contentsOf: target), data)
    }
  }

  func testInvalidSaveArgumentsLeaveExistingDataUntouched() throws {
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let original = Data("original".utf8)
    try original.write(to: target)
    MainFlutterWindow.handleFileMethod(FlutterMethodCall(methodName: "writeAtomically", arguments: [
      "path": target.path, "bytes": "not typed bytes"
    ])) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "invalidArguments")
    }
    XCTAssertEqual(try Data(contentsOf: target), original)
  }

  func testSaveFailureIsReturnedToFlutter() {
    MainFlutterWindow.handleFileMethod(FlutterMethodCall(methodName: "writeAtomically", arguments: [
      "path": "/dev/null/no-file", "bytes": FlutterStandardTypedData(bytes: Data([1]))
    ])) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "writeFailed")
    }
  }

}
