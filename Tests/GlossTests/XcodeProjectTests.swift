@testable import LucidRead
@testable import GlossModel
import XCTest

/// Pins what the model makes of an Xcode project's sources: `/** */` docs read as contracts like `///`
/// ones, and Objective-C headers lend their type names without becoming files of the interface.
final class XcodeProjectTests: XCTestCase {
    func testABlockCommentReadsAsAContract() {
        let source = """
        /**
         Adds two numbers.

         - Parameters:
           - a: One of them.
           - b: The other.
         - Returns: Their sum.
         */
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        """
        let contract = Contract.make(DeclarationReader.read(source: source, file: "Math.swift")[0])
        XCTAssertEqual(contract.summary, "Adds two numbers.")
        XCTAssertEqual(contract.parameters.map(\.doc), ["One of them.", "The other."])
    }

    func testAHeaderIsNoFileOfTheInterface() {
        let swift = "/// Prints a ``Receipt``.\nstruct Planner {}"
        let header = "NS_SWIFT_NAME(Receipt)\n@interface XYZReceipt : NSObject\n@end"
        let reading = Reading(sources: [("App/Planner.swift", swift), ("App/Cart.h", header)])
        XCTAssertEqual(Interface.build(reading).files, ["App/Planner.swift"])
    }
}
