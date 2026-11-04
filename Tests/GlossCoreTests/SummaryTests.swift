import GlossCore
import GlossMap
import XCTest

/// Pins what the summary page counts.
final class SummaryTests: XCTestCase {
    func testTheSummaryCountsSizeDocsAndFindingsByModule() {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Cart.swift", """
            /// A cart.
            public struct Cart {
                /// The sum.
                public func total() -> Int { 0 }
                func tidy() {}
                private var cache = 0
            }
            """),
            ("Sources/Ledger/Ledger.swift", """
            /// A ledger.
            struct Ledger {}
            """)
        ])
        let summary = Atlas(interface).interfaceSummary()
        XCTAssertEqual(summary.modules.map(\.name), ["Shop", "Ledger"])
        XCTAssertEqual(summary.types, 2)
        XCTAssertEqual(summary.declarations, 4, "Cart, total, tidy, and Ledger; the private property is left out.")
        XCTAssertEqual(summary.publicDeclarations, 2)
        XCTAssertEqual(summary.modules[0].owed - summary.modules[0].documented, 1, "tidy() owes a doc.")
        XCTAssertEqual(summary.findingsByRule.first?.name, "missing-doc")
        XCTAssertEqual(summary.mostFindings.map(\.name), ["Shop/Cart"])
        XCTAssertEqual(summary.byAccess.map(\.name), ["public", "internal", "private"], "Widest first, only levels that have any.")
    }
}
