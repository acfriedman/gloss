@testable import GlossRead
@testable import GlossLint
import Foundation
import XCTest

/// Pins how a project's house style is read and how the lint follows it.
final class HouseStyleTests: XCTestCase {
    private func style(_ json: String, root: String = "/repo", base: String? = nil) throws -> HouseStyle {
        try HouseStyle.parse(Data(json.utf8), root: root, base: base)
    }

    func testNoFileIsGlossOwnStyle() throws {
        let own = try style("{}")
        XCTAssertEqual(own.level(of: .missingDoc), .error)
        XCTAssertEqual(own.requireDocs, "internal")
        XCTAssertFalse(own.excludes("Sources/Shop/Cart.swift"))
    }

    func testRulesTakeACodeOverAPrefixAndALongerPrefixOverAShorter() throws {
        let style = try style("""
        { "severity": "warning", "rules": { "summary-*": "off", "summary-sentences": "error", "markup-*": "error" } }
        """)
        XCTAssertEqual(style.level(of: .summarySentences), .error, "A code wins over a prefix.")
        XCTAssertEqual(style.level(of: .summaryCapital), .off)
        XCTAssertEqual(style.level(of: .markupOrder), .error)
        XCTAssertEqual(style.level(of: .missingDoc), .warning, "Unnamed rules take the style's severity.")
    }

    func testAStyleFileSaysWhatIsWrongWithIt() {
        func problem(_ json: String) -> String? {
            do { _ = try style(json); return nil } catch { return String(describing: error) }
        }
        XCTAssertEqual(problem(#"{ "rules": { "missing-docs": "off" } }"#)?.contains("`missing-docs` names no rule"), true)
        XCTAssertEqual(problem(#"{ "exclude": "Sources" }"#)?.contains("`exclude` is a list"), true)
        XCTAssertEqual(problem(#"{ "severity": "loud" }"#)?.contains("`severity` is `error`, `warning`, or `off`"), true)
        XCTAssertEqual(problem(#"{ "excludes": [] }"#)?.contains("`excludes`, which gloss does not read"), true)
        XCTAssertEqual(problem(#"{ "requireDocs": "private" }"#)?.contains("`requireDocs` is `public`, `package`, or `internal`"), true)
        XCTAssertNotNil(problem("[]"), "A style is an object.")
    }

    func testExcludesMatchGlobsAndFoldersFromTheRoot() throws {
        let style = try style(#"{ "exclude": ["Sources/Generated", "**/*.pb.swift", "Sources/Shop/Draft?.swift"] }"#,
                              root: "/repo", base: "/repo/Sources")
        XCTAssertTrue(style.excludes("Generated/Model.swift"), "Read from the base, matched from the root.")
        XCTAssertTrue(style.excludes("/repo/Sources/Generated/Deep/Model.swift"), "A folder leaves out everything in it.")
        XCTAssertTrue(style.excludes("Shop/Proto/Cart.pb.swift"))
        XCTAssertTrue(style.excludes("Shop/Draft1.swift"))
        XCTAssertFalse(style.excludes("Shop/Draft12.swift"))
        XCTAssertFalse(style.excludes("Shop/Cart.swift"))
        XCTAssertFalse(style.excludes("/repo/SourcesGenerated/Model.swift"), "A folder's name is matched whole.")
    }

    func testRequireDocsDecidesMissingDocAloneAndALevelHowItIsReported() throws {
        let source = """
        public struct Cart {
            func tidy() {}
            /// tidies.
            func sweep() {}
        }
        """
        let rules = { (diagnostics: [Diagnostic]) in diagnostics.map { "\($0.severity) \($0.rule.rawValue)" } }
        XCTAssertEqual(rules(Linter.check(source: source, file: "Cart.swift")),
                       ["error missing-doc", "error missing-doc", "error summary-capital"])
        let style = try style(#"{ "requireDocs": "public", "rules": { "summary-*": "warning" } }"#)
        XCTAssertEqual(rules(Linter.check(source: source, file: "Cart.swift", style: style)), ["error missing-doc", "warning summary-capital"],
                       "Only the public cart owes a doc, and a doc that is written is still checked.")
        XCTAssertEqual(Linter.check(source: source, file: "Cart.swift", style: style).last?.rendered.contains(": warning: "), true)
    }

    func testAnExcludedFileIsReadButNotLinted() throws {
        let style = try style(#"{ "exclude": ["Sources/Gen"] }"#, root: "/repo", base: "/repo")
        let sources = [("Sources/Gen/Rates.swift", "struct Rates {}"), ("Sources/Shop/Cart.swift", "/// Priced by ``Rates``.\nstruct Cart {}")]
        XCTAssertEqual(Linter.check(sources: sources, style: style).map(\.rule), [.moduleDocMissing],
                       "No missing doc in Gen, and the link into it resolves; only Shop's page is missing, Gen being left out.")
        let assessments = Linter.assess(Reading(sources: sources), style: style)
        XCTAssertEqual(assessments.map(\.requiresDoc), [false, true])
        XCTAssertEqual(assessments.first?.exemption, "Excluded by the house style")
    }

    func testTheNearestStyleFileAboveAFolderIsFound() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gloss-style-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".gloss"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Shop"), withIntermediateDirectories: true)
        try Data(#"{ "severity": "warning" }"#.utf8).write(to: root.appendingPathComponent(HouseStyle.path))
        let found = try HouseStyle.find(from: root.appendingPathComponent("Sources/Shop").path)
        XCTAssertEqual(found.severity, .warning)
        XCTAssertEqual(found.root, root.standardizedFileURL.path, "Rooted at the folder holding `.gloss`.")
        XCTAssertEqual(found.base, root.appendingPathComponent("Sources/Shop").path)
    }
}
