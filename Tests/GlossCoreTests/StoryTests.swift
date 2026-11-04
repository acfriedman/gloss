@testable import GlossCore
import XCTest

/// Pins how a change's story is read, and how its links are matched to the changes they explain.
final class StoryTests: XCTestCase {
    private let base = """
    /// A cart.
    struct Cart {
        /// The sum.
        func total() -> Int { 0 }
        /// The coupon applied.
        var coupon: Coupon?
    }
    /// A coupon.
    struct Coupon {}
    /// A ledger.
    struct Ledger {
        /// Sums.
        func sum() -> Int { 0 }
    }
    """

    private let head = """
    /// A cart.
    struct Cart {
        /// The sum.
        func total() -> Double { 0 }
        /// The receipt.
        struct Receipt {}
    }
    /// A ledger.
    struct Ledger {
        /// Sums.
        func sum() -> Int { 1 }
    }
    /// A discount.
    struct Discount {}
    """

    private let story = """
    ---
    pr: #42
    ---
    # Price carts in fractions

    Totals were rounded, so carts lost cents.
    The coupon goes with them.

    ## Totals return a Double

    ``Cart/total()`` returns a `Double` now, and ``Coupon`` is gone.

    ## Discounts

    ``Shop/Discount`` replaces the coupon. ``Basket`` is a typo.

    ```swift
    let ignored = ``Ledger``
    ```
    """

    func testAStoryReadsAsAHeadlineASummaryAndThemes() {
        let read = ChangeStory.parse(story)
        XCTAssertEqual(read.pullRequest, 42)
        XCTAssertEqual(read.headline, "Price carts in fractions")
        XCTAssertEqual(read.summary, ["Totals were rounded, so carts lost cents. The coupon goes with them."], "Lines join into paragraphs.")
        XCTAssertEqual(read.themes.map(\.title), ["Totals return a Double", "Discounts"])
        XCTAssertEqual(read.themes[0].links, ["Cart/total()", "Coupon"])
        XCTAssertEqual(read.themes[1].links, ["Shop/Discount", "Basket"], "Links in fenced code are code, not links.")
        XCTAssertEqual(ChangeStory.path(forBranch: "feature/price"), ".gloss/changes/feature/price.md")
    }

    func testCoverageMatchesLinksToChangesAndFindsTheRest() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let coverage = StoryCoverage(story: ChangeStory.parse(story), diff: diff, head: after, base: before)
        XCTAssertEqual(coverage.types[0], ["Shop/Cart", "Shop/Cart.Receipt", "Shop/Coupon"],
                       "A member link explains its type, a type its nested types, and a gone type is still named.")
        XCTAssertEqual(coverage.members[0], [StoryCoverage.MemberLink(node: "Shop/Cart", name: "total()")])
        XCTAssertEqual(coverage.types[1], ["Shop/Discount"], "A link may start with its module.")
        XCTAssertEqual(coverage.deadLinks.map(\.link), ["Basket"])
        XCTAssertTrue(coverage.unexplained.isEmpty, "Ledger changed only inside its body, so it needs no theme.")
        XCTAssertFalse(coverage.isComplete)
        XCTAssertEqual(coverage.themes(explaining: "Shop/Coupon"), [0])

        let thin = StoryCoverage(story: ChangeStory.parse("# Price\n\n## Totals\n\n``Cart``"), diff: diff, head: after, base: before)
        XCTAssertEqual(thin.unexplained, ["Shop/Discount", "Shop/Coupon"], "The new and the gone type have no theme.")
    }

    func testADraftHasAThemePerModuleWithoutCommits() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let draft = ChangeStory.draft(for: diff, commits: nil)
        let read = ChangeStory.parse(draft)
        XCTAssertNotNil(read.headline)
        XCTAssertEqual(read.themes.map(\.title), ["Shop"])
        XCTAssertTrue(StoryCoverage(story: read, diff: diff, head: after, base: before).isComplete, "A draft covers the change it was made from.")
    }
}
