@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
@testable import GlossMap
import XCTest

/// Pins the two short answers a reach row gives: why what it relies on changed, and why it relies on it.
final class ReachWhyTests: XCTestCase {
    private func shop(total: String) -> String {
        """
        /// A cart.
        struct Cart {
            /// The sum.
            func total() -> \(total) { 0 }
        }
        /// Takes payment.
        struct Checkout {
            /// Charges a cart.
            ///
            /// - Parameter cart: The cart whose total is charged.
            func charge(_ cart: Cart) { print(cart.total()) }
        }
        """
    }

    private let theme = """
    # Price in fractions

    Totals lost cents.

    ## Totals return a Double

    ``Cart`` totals in fractions now. Rounding happened at the end, which lost cents. The rest is detail.

    """

    private func why(_ notes: String, commits: ChangeCommits? = nil, story: Bool = true) throws -> ReachWhy {
        let before = Interface.build(sources: [("Sources/Shop/Shop.swift", shop(total: "Int"))])
        let after = Interface.build(sources: [("Sources/Shop/Shop.swift", shop(total: "Double"))])
        let diff = InterfaceDiff(base: before, head: after)
        let atlas = Atlas(after)
        let reason = try XCTUnwrap(atlas.changeReasons(of: "Shop/Checkout", in: diff).first)
        let parsed = ChangeStory.parse(theme + notes)
        return atlas.why(reason, reaching: "Shop/Checkout", in: diff, story: story ? parsed : nil,
                         coverage: story ? StoryCoverage(story: parsed, diff: diff, head: after, base: before) : nil, commits: commits)
    }

    func testAMembersNoteLeadsInTwoSentencesAndTheUseSiteSaysWhyItIsUsed() throws {
        let why = try why("""
        ### ``Cart/total()``

        Returns a Double, so cents survive. Callers that round must round themselves. A third sentence.

        A second paragraph.
        """)
        XCTAssertEqual(why.changed?.lead, "Returns a Double, so cents survive. Callers that round must round themselves.")
        XCTAssertEqual(why.changed?.more, ["A third sentence.", "A second paragraph."], "The rest folds beneath the lead.")
        XCTAssertEqual(why.changed?.source, "the note on Cart/total()")
        XCTAssertEqual(why.user, "Shop/Checkout")
        XCTAssertEqual(why.uses.map(\.name), ["charge(_:)"])
        XCTAssertEqual(why.uses.first?.answer?.lead, "The cart whose total is charged.", "The entry that takes the type, not the summary.")
        XCTAssertEqual(why.uses.first?.answer?.source, "charge(_:)'s parameter cart")
    }

    func testWithoutAMembersNoteTheTypesNoteThenTheThemeAnswers() throws {
        XCTAssertEqual(try why("### ``Cart``\n\nIts total is a Double.").changed?.source, "the note on Cart")
        let byTheme = try why("")
        XCTAssertEqual(byTheme.changed?.lead, "``Cart`` totals in fractions now. Rounding happened at the end, which lost cents.",
                       "A theme answers for the types it links.")
        XCTAssertEqual(byTheme.changed?.source, "the theme Totals return a Double")
        XCTAssertNil(try why("", story: false).changed, "With no story and no commits, nothing says why.")
    }

    func testALeadEndsOnlyWhereASentenceDoes() {
        let split = Sentences.split("Calls `Cart.total()` first. Then e.g. rounds it. Last.", after: 2)
        XCTAssertEqual(split.lead, "Calls `Cart.total()` first. Then e.g. rounds it.", "Not inside code, nor after an abbreviation.")
        XCTAssertEqual(split.rest, "Last.")
        XCTAssertEqual(Sentences.split("One thought only", after: 2).lead, "One thought only")
    }
}
