import GlossRead
import GlossModel
import GlossLint
import GlossMap
import XCTest

/// Pins what the summary page counts.
final class SummaryTests: XCTestCase {
    private let reading = Reading(sources: [
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

    func testTheSummaryCountsSizeDocsAndFindingsByModule() {
        let summary = Atlas(Interface.build(reading), assessments: Linter.assess(reading)).interfaceSummary()
        XCTAssertEqual(summary.modules.map(\.name), ["Shop", "Ledger"])
        XCTAssertEqual(summary.types, 2)
        XCTAssertEqual(summary.declarations, 4, "Cart, total, tidy, and Ledger; the private property is left out.")
        XCTAssertEqual(summary.publicDeclarations, 2)
        XCTAssertEqual(summary.modules[0].owed - summary.modules[0].documented, 1, "tidy() owes a doc.")
        XCTAssertEqual(summary.findingsByRule.first?.name, "missing-doc")
        XCTAssertEqual(summary.mostFindings.map(\.name), ["Shop/Cart"])
        XCTAssertEqual(summary.byAccess.map(\.name), ["public", "internal", "private"], "Widest first, only levels that have any.")
    }

    func testAnInterfaceArrangedWithoutTheLintReadsTheSameButOwesNothing() {
        let interface = Interface.build(reading)
        let alone = Atlas(interface)
        let linted = Atlas(interface, assessments: Linter.assess(reading))
        XCTAssertEqual(alone.interfaceSummary().declarations, linted.interfaceSummary().declarations)
        XCTAssertEqual(alone.interfaceSummary().owed, 0, "Only the house style owes docs.")
        XCTAssertEqual(alone.totalFindings, 0)
        XCTAssertEqual(linted.totalFindings, Linter.assess(reading).reduce(0) { $0 + $1.findings.count })
        XCTAssertGreaterThan(linted.totalFindings, 0)
        XCTAssertEqual(alone.group("Shop/Cart").members.map(\.summary), linted.group("Shop/Cart").members.map(\.summary),
                       "The docs read the same either way.")
    }
}
