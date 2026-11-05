@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
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

    func testNotesTellAThemeFromEachTypesSide() throws {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let read = ChangeStory.parse("""
        # Price carts in fractions

        ## Totals return a Double

        Carts total in fractions now.

        ### ``Cart``

        Cart's total is a Double, and it holds no coupon.

        ### ``Cart/total()``

        Returns a Double.

        ### A heading that is not a link

        Stays prose of the note above.

        ## Discounts

        ``Discount`` and ``Coupon``.
        """)
        XCTAssertEqual(read.themes[0].paragraphs, ["Carts total in fractions now."])
        XCTAssertEqual(read.themes[0].notes.map(\.link), ["Cart", "Cart/total()"])
        XCTAssertEqual(read.themes[0].notes[1].paragraphs, ["Returns a Double.", "A heading that is not a link", "Stays prose of the note above."],
                       "A heading that is not one link is prose, a paragraph of its own.")
        XCTAssertEqual(read.themes[0].links, ["Cart", "Cart/total()"], "A note's link counts toward its theme.")
        let coverage = StoryCoverage(story: read, diff: diff, head: after, base: before)
        XCTAssertEqual(coverage.typeNotes["Shop/Cart"], [StoryCoverage.NotePlace(theme: 0, note: 0)])
        XCTAssertEqual(coverage.memberNotes[StoryCoverage.MemberLink(node: "Shop/Cart", name: "total()")], [StoryCoverage.NotePlace(theme: 0, note: 1)])
        XCTAssertTrue(coverage.unexplained.isEmpty)
        XCTAssertEqual(coverage.withoutNotes, ["Shop/Coupon"],
                       "A gone type needs a note of its own; new ones are told by the theme that links them.")
        XCTAssertFalse(coverage.isComplete)
    }

    func testADraftHasAThemePerModuleWithoutCommits() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let draft = ChangeStory.draft(for: diff, commits: nil)
        let read = ChangeStory.parse(draft)
        XCTAssertNotNil(read.headline)
        XCTAssertEqual(read.themes.map(\.title), ["Shop"])
        XCTAssertTrue(StoryCoverage(story: read, diff: diff, head: after, base: before).isComplete,
                      "A draft covers the change it was made from, a note to fill in for each type.")
        XCTAssertEqual(read.themes[0].notes.map(\.link), ["Cart/total()", "Cart/coupon", "Ledger/sum()", "Coupon"],
                       "Every change gets a reason: each member that differs, a body's too, and the gone coupon; new types are told by the theme.")
    }

    private let rounding = """
    /// Rounds a price to whole cents.
    ///
    /// - Parameter x: The price.
    /// - Returns: The price in whole cents.
    func round(_ x: Double) -> Int { 0 }
    """

    /// The same cart and free function, read from a module named `module`.
    private func moved(to module: String) -> Interface {
        Interface.build(sources: [("Sources/\(module)/Cart.swift", "/// A cart.\nstruct Cart {}"), ("Sources/\(module)/Round.swift", rounding)])
    }

    func testABareNameCoversBothSidesOfATypeThatMovedModules() {
        let before = moved(to: "Old")
        let after = moved(to: "New")
        let diff = InterfaceDiff(base: before, head: after)
        let coverage = StoryCoverage(story: ChangeStory.parse("""
        # Move the cart to New

        ## Move

        ``Cart`` and ``round(_:)`` move from Old to New, declared the same.

        ### ``Cart``

        Moved.

        ### ``round(_:)``

        Moved; a free function stands for its module's file scope.
        """), diff: diff, head: after, base: before)
        XCTAssertEqual(coverage.types[0], ["New/Cart", "New/", "Old/"],
                       "The cart is one move; a free function names its file scope, which has no name to move by.")
        let byOldModule = StoryCoverage(story: ChangeStory.parse("# Move\n\n## Move\n\n``Old/Cart`` left Old."),
                                        diff: diff, head: after, base: before)
        XCTAssertEqual(byOldModule.types[0], ["New/Cart"], "A link to the module a type left explains its move.")
        XCTAssertEqual(coverage.members[0], [StoryCoverage.MemberLink(node: "New/", name: "round(_:)"),
                                             StoryCoverage.MemberLink(node: "Old/", name: "round(_:)")])
        XCTAssertTrue(coverage.isComplete, "unexplained \(coverage.unexplained), without notes \(coverage.withoutNotes)")
    }

    func testAModuleFirstNarrowsALinkToThatModulesType() {
        let sources = { (doc: String) in Interface.build(sources: [("Sources/Shop/Cart.swift", "/// \(doc)\nstruct Cart {}"),
                                                                   ("Sources/Ledger/Cart.swift", "/// \(doc)\nstruct Cart {}")]) }
        let before = sources("A cart.")
        let after = sources("A cart of lines.")
        let diff = InterfaceDiff(base: before, head: after)
        let narrow = StoryCoverage(story: ChangeStory.parse("# Docs\n\n## Shop\n\n``Shop/Cart`` and ``Ledger/Basket``."),
                                   diff: diff, head: after, base: before)
        XCTAssertEqual(narrow.types[0], ["Shop/Cart"])
        XCTAssertEqual(narrow.unexplained, ["Ledger/Cart"], "Shop's link leaves Ledger's cart out.")
        XCTAssertEqual(narrow.deadLinks.map(\.link), ["Ledger/Basket"], "A module's link names only that module's types.")
        let bare = StoryCoverage(story: ChangeStory.parse("# Docs\n\n## Both\n\n``Cart``."), diff: diff, head: after, base: before)
        XCTAssertEqual(bare.types[0], ["Shop/Cart", "Ledger/Cart"])
    }

    func testADraftLinksAMovedTypeOnceAndAFreeFunctionByName() {
        let before = moved(to: "Old")
        let after = moved(to: "New")
        let diff = InterfaceDiff(base: before, head: after)
        let read = ChangeStory.parse(ChangeStory.draft(for: diff, commits: nil))
        XCTAssertEqual(read.themes.map(\.title), ["New", "Old"])
        XCTAssertEqual(read.themes.flatMap(\.notes).map(\.link), ["Cart", "round(_:)"], "One note per name, under the first theme.")
        XCTAssertTrue(StoryCoverage(story: read, diff: diff, head: after, base: before).isComplete)
    }

    func testALinkToAMemberTheTypeDoesNotDeclareNamesNothing() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let coverage = StoryCoverage(story: ChangeStory.parse("""
        # Totals

        ## Totals

        ``Cart/total()`` and ``Cart/coupon``, which is gone, but not ``Cart/totl()``.

        ### ``Cart/totl()``

        A typo, shown under no row.
        """), diff: diff, head: after, base: before)
        XCTAssertEqual(coverage.deadLinks.map(\.link), ["Cart/totl()"], "A gone member is still named; a mistyped one is not.")
        XCTAssertEqual(coverage.members[0].map(\.name), ["total()", "coupon"])
    }

    func testANewOrChangedMemberOfAnExistingTypeNeedsANoteOfItsOwn() {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", head)])
        let diff = InterfaceDiff(base: before, head: after)
        let typesOnly = StoryCoverage(story: ChangeStory.parse("""
        # Totals

        ## Totals

        ``Cart``, ``Discount``, and ``Coupon``.

        ### ``Cart``

        Totals in fractions.

        ### ``Discount``

        New.

        ### ``Coupon``

        Gone.
        """), diff: diff, head: after, base: before)
        XCTAssertEqual(typesOnly.membersWithoutNotes, [StoryCoverage.MemberLink(node: "Shop/Cart", name: "total()"),
                                                       StoryCoverage.MemberLink(node: "Shop/Cart", name: "coupon"),
                                                       StoryCoverage.MemberLink(node: "Shop/Ledger", name: "sum()")],
                       "Every change needs a reason beside it: the changed total, the gone coupon, and Ledger's body-only sum.")
        XCTAssertFalse(typesOnly.isComplete)
    }
}
