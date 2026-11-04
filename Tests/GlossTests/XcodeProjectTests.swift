@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
import Foundation
import XCTest

/// Pins what an Xcode project's sources need from gloss: links into the packages it imports, links that
/// name its own module though gloss names its folders, and `/** */` docs read like `///` ones.
final class XcodeProjectTests: XCTestCase {
    private func deadLinks(_ sources: [(String, String)]) -> [String] {
        Linter.check(sources: sources).filter { $0.rule == .deadLink }.map { String($0.message.prefix { $0 != " " }) }
    }

    func testALinkIntoAnImportedModuleResolves() {
        let cart = """
        import Foundation
        #if canImport(Alamofire)
        import Alamofire
        #endif

        /// Sent by ``Alamofire/Session``, unlike ``Ledger/Session``.
        struct Cart {}
        """
        XCTAssertEqual(deadLinks([("App/Cart.swift", cart)]), ["``Ledger/Session``"], "Only the module no file imports is dead.")
        XCTAssertEqual(Reading(sources: [("App/Cart.swift", cart)]).imports, ["Alamofire", "Foundation"])
    }

    func testALinkUnderTheProjectsOwnModuleNameResolvesByWhatFollows() {
        let sources = [
            ("MyApp/Features/Cart.swift", "/// A cart.\nstruct Cart {\n    /// Empties it.\n    func empty() {}\n}"),
            ("MyApp/Screens/Checkout.swift", "/// Shows ``MyApp/Cart``, empties it with ``MyApp/Cart/empty()``, but not ``MyApp/Basket``.\nstruct Checkout {}"),
            ("MyApp/Screens/Receipt.swift", "/// Not ``Cart/missing()``, since a cart is declared and has none.\nstruct Receipt {}")
        ]
        XCTAssertEqual(SourceFiles.module(of: sources[0].0), "Features", "Outside `Sources`, gloss names the module by folder.")
        XCTAssertEqual(deadLinks(sources), ["``MyApp/Basket``", "``Cart/missing()``"])
    }

    func testABlockCommentIsReadLikeLineComments() throws {
        let source = """
        /**
         Adds two numbers.

         - Parameters:
           - a: One of them.
           - b: The other.
         - Returns: Their sum.
         */
        func add(_ a: Int, _ b: Int) -> Int { a + b }

        /**
         * Doubles a number.
         *
         * - Parameter x: The number.
         * - Returns: Twice it.
         */
        func double(_ x: Int) -> Int { x * 2 }

        /** Halves a number. */
        func half() {}
        """
        let entries = DeclarationReader.read(source: source, file: "Math.swift")
        XCTAssertEqual(entries.map { $0.doc?.lines.first?.text }, ["Adds two numbers.", "Doubles a number.", "Halves a number."])
        XCTAssertEqual(entries[0].doc?.lines.first?.line, 2, "Lines keep their places in the file.")
        XCTAssertEqual(entries[1].doc?.lines.map(\.text), ["Doubles a number.", "", "- Parameter x: The number.", "- Returns: Twice it."],
                       "Leading stars go when every line has one.")
        let contract = Contract.make(entries[0])
        XCTAssertEqual(contract.summary, "Adds two numbers.")
        XCTAssertEqual(contract.parameters.map(\.doc), ["One of them.", "The other."])
        XCTAssertEqual(Linter.check(source: source, file: "Math.swift").map(\.rule), [.blockDoc, .blockDoc, .blockDoc],
                       "The form is the one finding; what each says follows the rules.")
    }

    func testWithBlockDocTurnedOffABlockCommentIsCheckedLikeAnyDoc() throws {
        let style = try HouseStyle.parse(Data(#"{ "rules": { "block-doc": "off" } }"#.utf8), root: "/repo")
        let source = "/**\n adds two.\n */\nfunc add(_ a: Int) -> Int { a }"
        XCTAssertEqual(Linter.check(source: source, file: "Math.swift", style: style).map(\.rule),
                       [.parameterMissing, .returnsMissing, .summaryCapital], "All on the summary's line, so in code order.")
    }

    func testHiddenAndDependencyFoldersAreNotScanned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gloss-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for file in [".DS_Store", "App/Cart.swift", "App/.cache/Old.swift", "SourcePackages/checkouts/Lib.swift", "Pods/Kit/Kit.swift",
                     "DerivedData/Build/Gen.swift", "Carthage/Checkouts/Dep.swift", "App/Ledger.swift"] {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let found = try SourceFiles.swiftFiles(under: root.path, includeTests: false).map { String($0.dropFirst(root.path.count + 1)) }
        XCTAssertEqual(found, ["App/Cart.swift", "App/Ledger.swift"], "A hidden file met first does not end the walk.")
    }
}
