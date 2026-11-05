@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
@testable import GlossMap
import XCTest

/// Pins what the list shows while a search or the findings filter narrows it.
final class ListOutlineTests: XCTestCase {
    private let reading = Reading(sources: [
        ("Sources/Shop/Cart/Cart.swift", """
        /// A cart.
        struct Cart {
            /// One line of it.
            struct Line {}
            /// Empties it.
            func empty() {}
        }
        """),
        ("Sources/Shop/Ledger.swift", "struct Ledger {}"),
        ("Sources/Bank/Vault.swift", "/// A vault.\nstruct Vault {}")
    ])

    private func list(_ search: String, findingsOnly: Bool = false) -> ListOutline {
        let atlas = Atlas(Interface.build(reading), assessments: Linter.assess(reading))
        return atlas.listOutline(ListFilter(search: search, findingsOnly: findingsOnly, minimumRank: 0))
    }

    /// Every row's id under a module's rows, depth first.
    private func ids(_ rows: [OutlineItem]) -> [String] {
        rows.flatMap { [$0.id] + ids($0.children) }
    }

    func testASearchKeepsWhatMatchesInPlaceAndOnlyTheModulesThatHoldIt() {
        let byMember = list("EMPTY")
        XCTAssertEqual(byMember.modules.map(\.name), ["Shop"], "A module without a match is left out.")
        XCTAssertEqual(ids(byMember.modules[0].rows), ["folder:Shop/Cart", "Shop/Cart"],
                       "A member's name matches its type, kept under its folder, case aside.")
        XCTAssertEqual(byMember.matches, 1)
        let nested = list("line")
        XCTAssertEqual(ids(nested.modules[0].rows), ["folder:Shop/Cart", "Shop/Cart", "Shop/Cart.Line"],
                       "A nested type keeps the type around it, so it shows in place.")
    }

    func testTheFindingsFilterKeepsOnlyTypesWithFindings() {
        XCTAssertEqual(ids(list("", findingsOnly: true).modules.flatMap(\.rows)), ["Shop/Ledger"], "Ledger has no doc.")
    }

    func testWithNothingNarrowingEveryModuleShows() {
        let all = list("  ")
        XCTAssertEqual(all.modules.map(\.name), ["Shop", "Bank"])
        XCTAssertEqual(all.matches, 0, "Nothing narrows, so nothing is counted as a match.")
    }

    func testAShortSearchInAHugeProjectShowsAtMostTheLimit() {
        let types = (0..<(ListFilter.limit + 20)).map { "/// Type \($0).\nstruct Shape\($0) {}" }.joined(separator: "\n")
        let atlas = Atlas(Interface.build(sources: [("Sources/Big/Shapes.swift", types)]))
        let found = atlas.listOutline(ListFilter(search: "s", findingsOnly: false, minimumRank: 0))
        XCTAssertEqual(found.matches, ListFilter.limit + 20)
        XCTAssertEqual(found.shown, ListFilter.limit)
        XCTAssertEqual(ids(found.modules.flatMap(\.rows)).count, ListFilter.limit, "The first matches, in graph order, and no more.")
    }
}
