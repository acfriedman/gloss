@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
import GlossMap
import XCTest

/// Pins how a module's page is read and checked against its module.
final class ModulePageTests: XCTestCase {
    private let cart = ("Sources/Shop/Cart.swift", "/// A cart.\npublic struct Cart {}\n/// A line.\npublic struct Line {}\n/// A helper.\nstruct Helper {}")

    private let page = """
    # Shop

    Sells what a shopper picks, so checkout has one place to ask. It knows carts and lines.

    ## Overview

    A ``Cart`` holds its lines.

    ## Topics

    ### Buying

    What a shopper fills.

    - ``Cart``
    - ``Line``

    ```swift
    let ignored = ``Nowhere``
    ```
    """

    private func rules(_ page: String) -> [String] {
        Linter.check(sources: [cart, ("Sources/Shop/README.md", page)]).map { "\($0.line) \($0.rule.rawValue)" }
    }

    func testAPageIsReadAsTitleSummaryOverviewAndTopics() {
        let read = ModulePage.parse(page, file: "Sources/Shop/README.md")
        XCTAssertEqual(read.module, "Shop")
        XCTAssertEqual(read.summary.map(\.text), ["Sells what a shopper picks, so checkout has one place to ask. It knows carts and lines."])
        XCTAssertEqual(read.overviewParagraphs, ["A ``Cart`` holds its lines."])
        XCTAssertEqual(read.topics.map(\.title), ["Buying"])
        XCTAssertEqual(read.topics.first?.links, ["Cart", "Line"])
        XCTAssertEqual(read.topics.first?.lead.map(\.text), ["What a shopper fills."])
        XCTAssertTrue(ModulePage.isPage("Sources/Shop/README.md"))
        XCTAssertFalse(ModulePage.isPage("README.md"), "The package's own README is not a module's page.")
        XCTAssertFalse(ModulePage.isPage("Sources/Shop/Notes/README.md"))
    }

    func testAPageThatFollowsTheRulesHasNoFindings() {
        XCTAssertEqual(rules(page), [], "Every public type is linked, the helper need not be, and a fenced link is code.")
    }

    func testAModuleWithoutAPageIsAskedForOne() {
        XCTAssertEqual(Linter.check(sources: [cart]).map(\.rule), [.moduleDocMissing])
        XCTAssertEqual(Linter.check(sources: [("App/Cart.swift", "/// A cart.\nstruct Cart {}")]).map(\.rule), [],
                       "Outside SwiftPM's layout gloss cannot tell a module from a folder, so none is asked for.")
    }

    func testThePageKeepsInStepAndShort() {
        let stale = page.replacingOccurrences(of: "- ``Line``\n", with: "- ``Basket``\n")
            .replacingOccurrences(of: "# Shop", with: "# Store")
            .replacingOccurrences(of: "A ``Cart`` holds its lines.", with: "One. Two. Three. Four. Five. Six.")
            .replacingOccurrences(of: "What a shopper fills.", with: "What a shopper fills. And more.")
        XCTAssertEqual(rules(stale), ["1 module-doc-title", "7 module-doc-length", "11 module-doc-length", "11 module-doc-unlisted", "16 dead-link"],
                       "Titled for another module, an Overview past five sentences, a lead past one, Line unlisted, and Basket gone.")
    }

    func testAPageSummaryAnswersToTheSummaryRules() {
        XCTAssertEqual(rules(page.replacingOccurrences(of: "Sells what a shopper picks, so checkout has one place to ask. It knows carts and lines.",
                                                       with: "sells things")), ["3 summary-capital", "3 summary-sentences", "3 summary-terminator"])
    }

    func testAHookJudgesThePageOfAModuleItTouches() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", "/// A cart.\npublic struct Cart {}")])
        let reading = Reading(sources: [cart, ("Sources/Shop/README.md", page.replacingOccurrences(of: "- ``Line``\n", with: ""))])
        let diff = InterfaceDiff(base: before, head: Interface.build(reading))
        XCTAssertEqual(ChangedFindings(diff).filter(Linter.check(reading)).map(\.rule), [.moduleDocUnlisted],
                       "The change adds Line, so its module's page must list it.")
    }
}
