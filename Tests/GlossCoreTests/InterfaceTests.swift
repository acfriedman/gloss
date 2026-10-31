@testable import GlossCore
import XCTest

/// Pins the contract model and the page against literal sources, so what the view can show is a visible diff.
final class InterfaceTests: XCTestCase {
    private func contracts(_ source: String) -> [Contract] {
        DeclarationReader.read(source: source, file: "Sources/Shop/Cart.swift").map(Contract.make)
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

    func testAssessmentsSitBesideTheirContracts() throws {
        let interface = Interface.build(sources: [("Sources/Shop/Cart.swift", "func total() -> Int { 0 }\n/// Adds.\nfunc add() {}")])
        XCTAssertEqual(interface.contracts.map(\.name), ["total", "add"])
        XCTAssertEqual(interface.assessments.map { $0.findings.map(\.rule) }, [["missing-doc"], []])
        XCTAssertEqual(interface.assessments.map(\.requiresDoc), [true, true])
        XCTAssertFalse(interface.contracts[0].isDocumented)
    }

    func testReadingFeedsLintAndModelAlike() {
        let source = "/// Adds.\nfunc add(_ x: Int) {}"
        let entries = DeclarationReader.read(source: source, file: "T.swift")
        XCTAssertEqual(entries.map(\.declaration.name), ["add"])
        XCTAssertEqual(Linter.check(source: source, file: "T.swift").map(\.rule), [.parameterMissing])
        XCTAssertEqual(entries.map(Contract.make).first?.parameters.map(\.type), ["Int"])
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
        XCTAssertTrue(html.contains("href=\"#g-Shop-Cart\""))
        XCTAssertTrue(html.contains("id=\"map\""))
        XCTAssertFalse(html.contains("<lines>"), "Doc text reaches the page only escaped, inside the page data.")
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
        let index = try XCTUnwrap(interface.contracts.firstIndex { $0.keyword == "code" })
        XCTAssertEqual(interface.contracts[index].name, "top-level code")
        XCTAssertFalse(interface.assessments[index].requiresDoc)
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

    func testEntryPointsAreUsedFromOutsideOrUnusedInside() {
        let interface = Interface.build(sources: [
            ("Sources/Core/Engine.swift", "public struct Engine { func run(_ plan: Plan) -> Report { Report() } }"),
            ("Sources/Core/Plan.swift", "public struct Plan {}\npublic struct Report {}\nstruct Orphan {}"),
            ("Sources/Tool/main.swift", "print(Report())")
        ])
        let site = InterfacePage.Site(interface)
        XCTAssertEqual(site.entryPoints(in: "Core").map(\.name), ["Engine", "Report"])
        XCTAssertEqual(site.entryPoints(in: "Tool").map(\.keyword), ["file"])
    }

    func testMemberLinesShowWhatFlowsInAndOut() throws {
        let contracts = contracts("""
        struct Cart {
            var total: Int
            func add(_ item: Item, count: Int) async throws -> Receipt { Receipt() }
            override func reset() {}
        }
        """)
        let add = try XCTUnwrap(contracts.first { $0.name == "add" })
        XCTAssertEqual(add.parameters.map(\.label), [nil, "count"])
        XCTAssertEqual(add.parameters.map(\.type), ["Item", "Int"])
        XCTAssertTrue(add.isAsync)
        XCTAssertEqual(add.throwsClause, "throws")
        XCTAssertEqual(add.returnType, "Receipt")
        XCTAssertEqual(contracts.first { $0.name == "total" }?.valueType, "Int")
        XCTAssertEqual(contracts.first { $0.name == "reset" }?.isOverride, true)
    }

    func testPageKeepsMapAndPanelSideBySide() {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "/// Holds lines. Kept apart from pricing.\npublic struct Cart { struct Line {} }")
        ])
        let html = InterfacePage.render(interface, title: "Shop")
        XCTAssertTrue(html.contains("<section class=\"stage\" id=\"map\""))
        XCTAssertTrue(html.contains("<aside class=\"panel\""))
        XCTAssertTrue(html.contains("id=\"start\" data-view data-root=\"\""))
        XCTAssertTrue(html.contains("<section class=\"view\" id=\"type\" data-view"), "Type views are built in the page from its data.")
        XCTAssertTrue(html.contains("[hidden] { display: none !important; }"), "Author styles must not reveal hidden elements.")
    }

    func testPageDataCarriesFlowUsesAndBriefs() throws {
        let interface = Interface.build(sources: [
            ("Sources/Shop/Cart.swift", """
            /// Holds lines until checkout. Kept apart from pricing so totals stay pure.
            public struct Cart {
                /// Adds a line. Lines keep their order, see `Line.id`.
                public func add(_ line: Line) -> Receipt { Pricing.total(line) }
                struct Note {}
            }
            public struct Line {}
            public struct Receipt {}
            enum Pricing {}
            """)
        ])
        let site = InterfacePage.Site(interface)
        let data = InterfacePage.pageData(site, scopesOf: ["Shop/Cart": ["s-types"]])
        let index = Dictionary(uniqueKeysWithValues: data.nodes.enumerated().map { ($1.id, $0) })
        let cart = data.nodes[try XCTUnwrap(index["Shop/Cart"])]
        XCTAssertEqual(cart.a, "g-Shop-Cart")
        XCTAssertEqual(cart.sc, ["s-types"])
        XCTAssertEqual(cart.n, [try XCTUnwrap(index["Shop/Cart.Note"])])
        let roles = Dictionary(uniqueKeysWithValues: (cart.o ?? []).map { (data.nodes[$0[0]].id, $0[1]) })
        XCTAssertEqual(roles["Shop/Line"], InterfacePage.roleMask([.parameter]))
        XCTAssertEqual(roles["Shop/Receipt"], InterfacePage.roleMask([.returns]))
        XCTAssertEqual(roles["Shop/Pricing"], InterfacePage.roleMask([.body]))
        let add = data.contracts[try XCTUnwrap(cart.c?.first)]
        XCTAssertEqual(add.b, "Adds a line.".utf16.count, "The brief ends at the first sentence.")
        XCTAssertEqual(add.u?.map { data.nodes[$0[0]].id }, ["Shop/Line", "Shop/Receipt", "Shop/Pricing"])
        XCTAssertEqual(add.u?.map { $0[1] }, [0, 0, 1], "Only Pricing is used in the body alone.")
        let json = InterfacePage.encode(data)
        XCTAssertFalse(json.contains("</"), "No string in the data can close the script element holding it.")
    }

    func testSmallInterfacesOpenOnAllTypes() {
        let one = InterfacePage.Site(Interface.build(sources: [("Sources/Shop/Cart.swift", "struct Cart { var line: Line }\nstruct Line {}")]))
        XCTAssertEqual(InterfacePage.mapScopes(one).map(\.id), ["s-types"])
        let two = InterfacePage.Site(Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "public struct Cart {}"),
            ("Sources/App/main.swift", "print(Cart())")
        ]))
        XCTAssertEqual(InterfacePage.mapScopes(two).map(\.id), ["s-types", "s-modules", "s-m-Shop", "s-m-App"])
    }

    func testLargeModulesZoomThroughFolders() throws {
        let models = (0..<20).map { ("Sources/Big/Models/M\($0).swift", "struct M\($0) {}") }
        let views = (0..<20).map { ("Sources/Big/Views/V\($0).swift", "struct V\($0) { var model: M\($0) }") }
        let site = InterfacePage.Site(Interface.build(sources: models + views))
        let scopes = InterfacePage.mapScopes(site)
        XCTAssertEqual(scopes.map(\.id), ["s-m-Big", "s-f-Big-Models", "s-f-Big-Views"])
        let module = InterfacePage.figure(scopes[0], site: site, includeBody: true)
        XCTAssertEqual(module.items.map(\.label), ["Models/", "Views/"], "Over the budget, a module draws its folders.")
        XCTAssertEqual(module.links.count, 1)
        let folder = InterfacePage.figure(scopes[2], site: site, includeBody: true)
        XCTAssertEqual(folder.shown.count, 20)
        XCTAssertTrue(folder.items.contains { $0.label == "Models/" && $0.classes.contains("boundary") },
                      "What a folder depends on outside it is drawn as a boundary box.")
    }

    func testLevelsOverTheBudgetListTheLeastConnected() {
        let types = (0..<35).map { ("Sources/Flat/T\($0).swift", $0 < 10 ? "struct T\($0) { var next: T\($0 + 1) }" : "struct T\($0) {}") }
        let site = InterfacePage.Site(Interface.build(sources: types))
        let scope = InterfacePage.mapScopes(site)[0]
        let figure = InterfacePage.figure(scope, site: site, includeBody: true)
        XCTAssertEqual(figure.shown.count, InterfacePage.mapBudget)
        XCTAssertEqual(figure.overflow.count, 5)
        XCTAssertTrue(figure.shown.contains("Flat/T0"), "Connected types are kept over unconnected ones.")
    }

    func testFirstSentenceIgnoresPeriodsInCode() {
        XCTAssertEqual(InterfacePage.firstSentence("Reads `a.b` first. Then more."), "Reads `a.b` first.")
        XCTAssertEqual(InterfacePage.firstSentence("No period"), "No period")
    }

    func testInlineCodeSpans() {
        XCTAssertEqual(InterfacePage.inline("Use ``Cart/add(_:)`` or `x < y`."),
                       "Use <code class=\"link\">Cart/add(_:)</code> or <code>x &lt; y</code>.")
        XCTAssertEqual(InterfacePage.inline("An open ` tick"), "An open ` tick")
    }
}
