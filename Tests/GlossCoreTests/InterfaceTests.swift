@testable import GlossCore
import XCTest

/// Pins the contract model and the page against literal sources, so what the view can show is a visible diff.
final class InterfaceTests: XCTestCase {
    private func contracts(_ source: String) -> [Contract] {
        Checker.contracts(source: source, file: "Sources/Shop/Cart.swift")
    }

    func testFunctionContractCarriesTypesDocsAndEffects() throws {
        let source = """
        public struct Cart {
            /// Adds an item. Adding is idempotent per SKU.
            ///
            /// - Parameters:
            ///   - item: The item to add.
            ///   - quantity: How many; zero is ignored.
            /// - Returns: The new line count.
            /// - Throws: ``CartError/full`` past the limit.
            /// - Note: Prices are not rechecked.
            ///
            /// Lines are kept in insertion order.
            public mutating func add(_ item: Item,
                                     quantity: Int = 1) async throws(CartError) -> Int { 0 }
        }
        """
        let add = try XCTUnwrap(contracts(source).first { $0.name == "add" })
        XCTAssertEqual(add.container, ["Cart"])
        XCTAssertEqual(add.qualifiedName, "Cart.add")
        XCTAssertEqual(add.access, "public")
        XCTAssertEqual(add.declaration, "public mutating func add(_ item: Item, quantity: Int = 1) async throws(CartError) -> Int")
        XCTAssertEqual(add.parameters.map(\.type), ["Item", "Int"])
        XCTAssertEqual(add.parameters.map(\.hasDefault), [false, true])
        XCTAssertEqual(add.parameters.map(\.doc), ["The item to add.", "How many; zero is ignored."])
        XCTAssertEqual(add.returnType, "Int")
        XCTAssertEqual(add.returns, "The new line count.")
        XCTAssertEqual(add.throwsClause, "throws(CartError)")
        XCTAssertTrue(add.isAsync)
        XCTAssertEqual(add.summary, "Adds an item. Adding is idempotent per SKU.")
        XCTAssertEqual(add.callouts, [.init(keyword: "Note", text: "Prices are not rechecked.")])
        XCTAssertEqual(add.notes, ["Lines are kept in insertion order."])
        XCTAssertEqual(add.findings, [])
    }

    func testAccessFollowsExtensionsProtocolsAndEnums() {
        let source = """
        public extension Cart { func total() -> Int { 0 } }
        public protocol Store { func save() }
        public enum Mode { case fast }
        struct Box { var value: Int }
        private struct Hidden { func peek() {} }
        """
        let access = Dictionary(contracts(source).map { ($0.qualifiedName, $0.access) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(access["Cart.total"], "public")
        XCTAssertEqual(access["Store.save"], "public")
        XCTAssertEqual(access["Mode.fast"], "public")
        XCTAssertEqual(access["Box.value"], "internal")
        XCTAssertEqual(access["Hidden.peek"], "private")
    }

    func testHeaderDropsBodiesAndAnnotatedInitialValues() {
        let source = """
        struct Box {
            static let limits: Set<String> = ["a", "b"]
            var count = 0
            var isEmpty: Bool { count == 0 }
            private(set) var label: String
        }
        """
        let headers = contracts(source).map(\.declaration)
        XCTAssertEqual(headers, [
            "struct Box",
            "static let limits: Set<String>",
            "var count = 0",
            "var isEmpty: Bool { get }",
            "private(set) var label: String"
        ])
        XCTAssertEqual(contracts(source).last?.access, "internal")
    }

    func testFindingsAttachToTheirDeclaration() throws {
        let contract = try XCTUnwrap(contracts("func total() -> Int { 0 }").first)
        XCTAssertEqual(contract.findings.map(\.rule), ["missing-doc"])
        XCTAssertFalse(contract.isDocumented)
        XCTAssertTrue(contract.requiresDoc)
    }

    func testModuleComesFromTheSwiftPMLayout() {
        XCTAssertEqual(Interface.module(of: "Sources/GlossCore/Rules.swift"), "GlossCore")
        XCTAssertEqual(Interface.module(of: "/repo/Packages/Shop/Sources/Cart/Views/Line.swift"), "Cart")
        XCTAssertEqual(Interface.module(of: "App/Features/Checkout.swift"), "Features")
        XCTAssertEqual(Interface.module(of: "main.swift"), "Module")
    }

    func testPageGroupsExtensionsWithTheirTypeAndEscapes() {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "/// A cart. It holds `<lines>`.\nstruct Cart {}\nextension String { func shout() {} }"),
            ("Sources/Shop/Cart+Total.swift", "extension Cart { func total() -> Int { 0 } }")
        ])
        let site = InterfacePage.Site(interface)
        XCTAssertEqual(site.nodes.map(site.label), ["Cart", "extension String"])
        XCTAssertEqual(site.groups["Shop/Cart"]?.members.map(\.name), ["total"])
        let html = InterfacePage.render(interface, title: "Shop")
        XCTAssertTrue(html.contains("<code>&lt;lines&gt;</code>"))
        XCTAssertTrue(html.contains("id=\"g-Shop-Cart\""))
        XCTAssertTrue(html.contains("id=\"map\""))
        XCTAssertEqual(html, InterfacePage.render(interface, title: "Shop"), "Rendering must be deterministic.")
    }

    func testGraphResolvesInnermostScopeFirstAndTagsRoles() throws {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Line.swift", "struct Line {}\nstruct Receipt { struct Line {} }"),
            ("Sources/Shop/Cart.swift", """
            struct Cart: Codable {
                var lines: [Line]
                func receipt(for line: Line) throws(CartError) -> Receipt { Pricing.total(lines) }
            }
            extension Receipt { func first() -> Line { Line() } }
            enum CartError: Error {}
            enum Pricing {}
            """)
        ])
        let edges = Dictionary(interface.graph.edges.map { ("\($0.from) -> \($0.to)", $0.roles) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(edges["Shop/Cart -> Shop/Line"], [.property, .parameter])
        XCTAssertEqual(edges["Shop/Cart -> Shop/Receipt"], [.returns])
        XCTAssertEqual(edges["Shop/Cart -> Shop/CartError"], [.throws])
        XCTAssertEqual(edges["Shop/Cart -> Shop/Pricing"], [.body])
        XCTAssertEqual(edges["Shop/Receipt -> Shop/Receipt.Line"], [.returns, .body], "Inside Receipt, Line is Receipt.Line.")
        XCTAssertNil(edges["Shop/Cart -> Shop/Codable"], "Unscanned types are not nodes.")
        let nested = try XCTUnwrap(interface.graph.nodes.first { $0.id == "Shop/Receipt.Line" })
        XCTAssertEqual(nested.root, "Shop/Receipt")
    }

    func testTopLevelCodeCarriesItsMentions() throws {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "/// A cart.\npublic struct Cart {}"),
            ("Sources/shop/main.swift", "let cart = 1\nif cart > 0 { print(Cart()) }")
        ])
        let code = try XCTUnwrap(interface.contracts.first { $0.keyword == "code" })
        XCTAssertEqual(code.name, "top-level code")
        XCTAssertFalse(code.requiresDoc)
        XCTAssertTrue(interface.graph.edges.contains { $0.from == "shop/" && $0.to == "Shop/Cart" && $0.roles == [.body] })
    }

    func testLayoutFlowsDownwardAndHandlesCycles() {
        let items = ["A", "B", "C"].map { GraphLayout.Item(id: $0, label: $0, detail: "", link: $0) }
        let links = [("A", "B"), ("B", "C"), ("C", "A"), ("A", "C")].map { GraphLayout.Link(from: $0.0, to: $0.1, dashed: false, title: "") }
        let layout = GraphLayout.layered(items, links)
        let y = Dictionary(uniqueKeysWithValues: layout.boxes.map { ($0.item.id, $0.y) })
        XCTAssertLessThan(y["A"]!, y["B"]!)
        XCTAssertLessThan(y["B"]!, y["C"]!)
        XCTAssertEqual(layout.curves.count, 4)
        XCTAssertEqual(layout.curves.filter(\.reversed).count, 1, "Only the edge closing the cycle runs against the flow.")
    }

    func testInlineCodeSpans() {
        XCTAssertEqual(InterfacePage.inline("Use ``Cart/add(_:)`` or `x < y`."),
                       "Use <code class=\"link\">Cart/add(_:)</code> or <code>x &lt; y</code>.")
        XCTAssertEqual(InterfacePage.inline("An open ` tick"), "An open ` tick")
    }
}
