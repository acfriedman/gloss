@testable import GlossCore
@testable import GlossMap
@testable import GlossPage
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
        let atlas = Atlas(interface)
        XCTAssertEqual(atlas.nodes.map(atlas.label), ["Cart", "extension String"])
        XCTAssertEqual(atlas.groups["Shop/Cart"]?.members.map(\.name), ["total"])
        let html = InterfacePage.render(interface, title: "Shop")
        XCTAssertTrue(html.contains("href=\"#g-Shop-Cart\""))
        XCTAssertTrue(html.contains("id=\"map\""))
        XCTAssertTrue(html.contains("data-min=\"1\" aria-pressed=\"true\""), "The page opens on internal, as the app does.")
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
        let items = ["A", "B", "C"].map { GraphLayout.Item(unit: .type($0), label: $0, detail: "") }
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
        let atlas = Atlas(interface)
        XCTAssertEqual(atlas.entryPoints(in: "Core").map(\.name), ["Engine", "Report"])
        XCTAssertEqual(atlas.entryPoints(in: "Tool").map(\.keyword), ["file"])
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
        XCTAssertTrue(html.contains("id=\"overview\" data-view data-root=\"\""))
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
        let atlas = Atlas(interface)
        let data = InterfacePage.pageData(atlas, scopesOf: ["Shop/Cart": ["s-types"]])
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
        let one = Atlas(Interface.build(sources: [("Sources/Shop/Cart.swift", "struct Cart { var line: Line }\nstruct Line {}")]))
        XCTAssertEqual(one.mapScopes().map(\.id), ["s-types"])
        let two = Atlas(Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "public struct Cart {}"),
            ("Sources/App/main.swift", "print(Cart())")
        ]))
        XCTAssertEqual(two.mapScopes().map(\.id), ["s-types", "s-modules", "s-m-Shop", "s-m-App"])
    }

    func testLargeModulesZoomThroughFolders() throws {
        let models = (0..<20).map { ("Sources/Big/Models/M\($0).swift", "struct M\($0) {}") }
        let views = (0..<20).map { ("Sources/Big/Views/V\($0).swift", "struct V\($0) { var model: M\($0) }") }
        let atlas = Atlas(Interface.build(sources: models + views))
        let scopes = atlas.mapScopes()
        XCTAssertEqual(scopes.map(\.id), ["s-m-Big", "s-f-Big-Models", "s-f-Big-Views"])
        let module = atlas.figure(scopes[0], includeBody: true)
        XCTAssertEqual(module.items.map(\.label), ["Models/", "Views/"], "Over the budget, a module draws its folders.")
        XCTAssertEqual(module.links.count, 1)
        let folder = atlas.figure(scopes[2], includeBody: true)
        XCTAssertEqual(folder.shown.count, 20)
        XCTAssertTrue(folder.items.contains { $0.label == "Models/" && $0.flags.contains(.boundary) },
                      "What a folder depends on outside it is drawn as a boundary box.")
    }

    func testFocusDrawsUsersAboveAndDependenciesBelow() throws {
        let source = """
        public struct Cart { public var lines: [Line] }
        public struct Line { public var price: Price }
        public struct Price {}
        public struct Checkout { public func run(_ cart: Cart) {} }
        """
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Cart.swift", source)]))
        let focus = try XCTUnwrap(atlas.reach(from: "Shop/Cart", toward: .both, depth: 1, minimumRank: 3))
        let y = Dictionary(uniqueKeysWithValues: focus.layout.boxes.map { ($0.item.id, $0.y) })
        XCTAssertEqual(Set(y.keys), ["Shop/Checkout", "Shop/Cart", "Shop/Line"], "At depth 1, only direct neighbors are drawn.")
        XCTAssertLessThan(try XCTUnwrap(y["Shop/Checkout"]), try XCTUnwrap(y["Shop/Cart"]))
        XCTAssertLessThan(try XCTUnwrap(y["Shop/Cart"]), try XCTUnwrap(y["Shop/Line"]))
        XCTAssertEqual(focus.layout.curves.map(\.link.title).sorted(), ["Cart holds Line", "Checkout takes Cart"])
        XCTAssertEqual([focus.above, focus.below, focus.overflow.count], [1, 1, 0])
        let deeper = try XCTUnwrap(atlas.reach(from: "Shop/Cart", toward: .both, depth: 2, minimumRank: 3))
        XCTAssertTrue(deeper.layout.boxes.contains { $0.item.id == "Shop/Price" }, "Depth 2 reaches both ways a step further.")
    }

    func testLevelPathsNameTheWayBackFromTheWidestLevel() {
        let atlas = Atlas(Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "struct Cart {}"),
            ("Sources/App/Main.swift", "struct Main { var cart: Cart }")
        ]))
        let paths = Dictionary(uniqueKeysWithValues: atlas.mapScopes().map { ($0.id, $0.path) })
        XCTAssertEqual(paths["s-modules"], ["s-types", "s-modules"])
        XCTAssertEqual(paths["s-m-App"], ["s-types", "s-modules", "s-m-App"])
    }

    func testHighlightColorsBySyntaxAndTellsProjectTypesApart() {
        let code = "@MainActor public func total(of lines: [Line], limit: Int = 10) throws -> Price"
        let runs = Highlight.runs(code, projectTypes: ["Line", "Price"])
        XCTAssertEqual(runs.map(\.text).joined(), code, "Runs spell the source exactly.")
        let kinds = Dictionary(runs.map { ($0.text.trimmingCharacters(in: .whitespaces), $0.kind) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(kinds["@MainActor"], .attribute)
        XCTAssertEqual(kinds["total"], .declaration)
        XCTAssertEqual(kinds["Line"], .projectType)
        XCTAssertEqual(kinds["Int"], .type)
        XCTAssertEqual(kinds["10"], .number)
        XCTAssertEqual(kinds["Price"], .projectType)
        XCTAssertEqual(runs.first { $0.text.contains("func") }?.kind, .keyword)
        XCTAssertEqual(Highlight.runs("public var rendered: String { get }").first { $0.kind == .declaration }?.text, "rendered")
    }

    func testReachDrawsWholeStepsThatFitAndMarksTheCut() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Shop.swift", """
        struct App { var store: Store; var view: Screen }
        struct Store { var cart: Cart }
        struct Screen { var cart: Cart }
        struct Cart { var lines: [Line] }
        struct Line { var price: Price }
        struct Price {}
        """)]))
        func boxes(_ reach: Reach) -> [String] { reach.layout.boxes.map(\.item.label).sorted() }
        let all = try XCTUnwrap(atlas.reach(from: "Shop/App", toward: .dependencies, minimumRank: 0))
        XCTAssertEqual([all.depth, all.totalDepth, all.drawn, all.total], [4, 4, 5, 5])
        XCTAssertEqual(all.layout.boxes.first { $0.item.label == "App" }?.y, 6, "The root is drawn at the top.")
        let tight = try XCTUnwrap(atlas.reach(from: "Shop/App", toward: .dependencies, minimumRank: 0, budget: 4))
        XCTAssertEqual(tight.depth, 2, "Whole steps only: App, Store and Screen, then Cart, is four boxes.")
        XCTAssertEqual(boxes(tight), ["App", "Cart", "Screen", "Store"])
        let cart = try XCTUnwrap(tight.layout.boxes.first { $0.item.label == "Cart" })
        XCTAssertTrue(cart.item.flags.contains(.boundary))
        XCTAssertEqual(cart.item.detail, "struct · +1 below", "A box at the cut counts its next step.")
        let users = try XCTUnwrap(atlas.reach(from: "Shop/Line", toward: .users, depth: 1, minimumRank: 0))
        XCTAssertEqual(boxes(users), ["Cart", "Line"])
        XCTAssertEqual(users.layout.boxes.first { $0.item.label == "Cart" }?.item.detail, "struct · +2 above")
    }

    func testLanesKeepEachGroupsBoxesInsideItsOwnColumn() {
        func item(_ id: String, _ group: String?) -> GraphLayout.Item {
            GraphLayout.Item(unit: .type(id), label: id, detail: "struct", group: group)
        }
        let links = [("App", "Store"), ("App", "Cart"), ("Store", "Cart"), ("Cart", "Price")].map {
            GraphLayout.Link(from: $0.0, to: $0.1, dashed: false, title: "")
        }
        let items = [item("App", "UI"), item("Store", "Core"), item("Cart", "Core"), item("Price", "Money")]
        let layout = GraphLayout.layered(items, links, emphasis: "Core")
        XCTAssertEqual(Set(layout.lanes.map(\.name)), ["UI", "Core", "Money"])
        XCTAssertEqual(layout.lanes.filter(\.isEmphasized).map(\.name), ["Core"])
        for box in layout.boxes {
            let lane = layout.lanes.first { $0.name == box.item.group }
            XCTAssertNotNil(lane)
            if let lane {
                XCTAssertGreaterThanOrEqual(box.x, lane.x, "\(box.item.label) starts inside \(lane.name).")
                XCTAssertLessThanOrEqual(box.x + box.width, lane.x + lane.width, "\(box.item.label) ends inside \(lane.name).")
                XCTAssertGreaterThanOrEqual(box.y, lane.y)
            }
        }
        let sorted = layout.lanes.sorted { $0.x < $1.x }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThan(left.x + left.width, right.x, "Lanes do not overlap.")
        }
        XCTAssertEqual(GraphLayout.layered(items.map { item($0.id, "One") }, links).lanes, [], "One group draws no lanes.")
        XCTAssertEqual(GraphLayout.layered(items.map { item($0.id, nil) }, links), GraphLayout.layered(items.map { item($0.id, nil) }, links))
        XCTAssertEqual(GraphLayout.layered(items, links), GraphLayout.layered(items, links), "Lanes are laid out deterministically.")
    }

    func testSplitLanesGiveAGroupOnBothSidesAContainerOnEach() {
        func item(_ id: String, _ group: String) -> GraphLayout.Item {
            GraphLayout.Item(unit: .type(id), label: id, detail: "struct", group: group)
        }
        let items = [item("Screen", "App"), item("Panel", "Page"), item("Atlas", "Map"),
                     item("Store", "App"), item("Graph", "Core"), item("Layout", "Map")]
        let links = [("Screen", "Atlas"), ("Panel", "Atlas"), ("Atlas", "Store"), ("Atlas", "Graph"), ("Atlas", "Layout")].map {
            GraphLayout.Link(from: $0.0, to: $0.1, dashed: false, title: "")
        }
        let split = GraphLayout.layered(items, links, emphasis: "Map", splitAt: "Atlas")
        let whole = GraphLayout.layered(items, links, emphasis: "Map")
        XCTAssertEqual(split.lanes.filter { $0.name == "App" }.count, 2, "App sits above and below, so it gets two containers.")
        XCTAssertEqual(whole.lanes.filter { $0.name == "App" }.count, 1)
        XCTAssertLessThan(split.width, whole.width, "Each band holds only its own groups, so the figure is narrower.")
        let atlas = split.boxes.first { $0.item.label == "Atlas" }
        let screen = split.boxes.first { $0.item.label == "Screen" }
        let store = split.boxes.first { $0.item.label == "Store" }
        XCTAssertLessThan(screen?.y ?? 0, atlas?.y ?? 0)
        XCTAssertLessThan(atlas?.y ?? 0, store?.y ?? 0)
    }

    func testModuleColorsAreStableAndDistinct() {
        let modules = ["GlossCore", "GlossMap", "GlossPage", "GlossApp", "gloss"]
        let slots = Atlas.colorSlots(for: modules)
        XCTAssertEqual(Set(slots.values).count, modules.count, "No two modules share a color while slots last.")
        XCTAssertEqual(slots, Atlas.colorSlots(for: modules.reversed()), "Order of appearance does not matter.")
        XCTAssertEqual(Atlas.colorSlots(for: ["GlossCore"])["GlossCore"], Atlas.colorSlots(for: ["GlossCore", "Zebra"])["GlossCore"],
                       "Adding a module that does not collide leaves the others' colors alone.")
        XCTAssertTrue(slots.values.allSatisfy { (0..<Atlas.moduleColorCount).contains($0) })
    }

    func testSplitBandsMergeWhereSplittingSavesNothing() {
        func item(_ id: String, _ group: String) -> GraphLayout.Item {
            GraphLayout.Item(unit: .type(id), label: id, detail: "struct", group: group)
        }
        func link(_ from: String, _ to: String) -> GraphLayout.Link { GraphLayout.Link(from: from, to: to, dashed: false, title: "") }
        let ownAbove = GraphLayout.layered(
            [item("Focus", "Map"), item("Atlas", "Map"), item("Graph", "Core"), item("Layout", "Map")],
            [link("Focus", "Atlas"), link("Atlas", "Graph"), link("Atlas", "Layout")], emphasis: "Map", splitAt: "Atlas")
        XCTAssertEqual(ownAbove.lanes.filter { $0.name == "Map" }.count, 1,
                       "Only the root's own module above: no second container for it.")
        let steps = GraphLayout.layered(
            [item("App", "UI"), item("Store", "UI"), item("Ledger", "Core"), item("Entry", "Core")],
            [link("App", "Store"), link("Store", "Ledger"), link("Ledger", "Entry")], emphasis: "UI", splitAt: "App")
        XCTAssertEqual(steps.lanes.map(\.name), ["UI", "Core"], "Rows of one module merge; a new module starts a band.")
        XCTAssertLessThan(steps.lanes[0].y + steps.lanes[0].height, steps.lanes[1].y, "The bands stack, not sit side by side.")
    }

    func testSplitBandsKeepAContinuingGroupWholeAndStackTheRest() throws {
        func item(_ id: String, _ group: String) -> GraphLayout.Item {
            GraphLayout.Item(unit: .type(id), label: id, detail: "struct", group: group)
        }
        func link(_ from: String, _ to: String) -> GraphLayout.Link { GraphLayout.Link(from: from, to: to, dashed: false, title: "") }
        let layout = GraphLayout.layered(
            [item("Root", "Map"), item("Ap1", "App"), item("Pg1", "Page"), item("Ap2", "App"), item("Tp2", "Top")],
            [link("Ap1", "Root"), link("Pg1", "Root"), link("Ap2", "Ap1"), link("Tp2", "Pg1")], emphasis: "Map", splitAt: "Root")
        XCTAssertEqual(layout.lanes.filter { $0.name == "App" }.count, 1,
                       "App runs through both rows above, so its neighbors changing beside it does not split it.")
        let top = try XCTUnwrap(layout.lanes.first { $0.name == "Top" })
        let page = try XCTUnwrap(layout.lanes.first { $0.name == "Page" })
        XCTAssertEqual(top.x + top.width / 2, page.x + page.width / 2, accuracy: 0.5, "Lanes whose rows never meet share a column.")
        XCTAssertLessThan(top.y + top.height, page.y)
    }

    func testLanesGoAroundTheRootHeaviestNearest() throws {
        func item(_ id: String, _ group: String) -> GraphLayout.Item {
            GraphLayout.Item(unit: .type(id), label: id, detail: "struct", group: group)
        }
        let items = [item("Page", "P"), item("Data", "P"), item("Core1", "C"), item("Core2", "C"), item("Map1", "M")]
        let links = ["Data", "Core1", "Core2", "Map1"].map { GraphLayout.Link(from: "Page", to: $0, dashed: false, title: "") }
        let layout = GraphLayout.layered(items, links, emphasis: "P", splitAt: "Page")
        XCTAssertEqual(layout.lanes.sorted { $0.x < $1.x }.map(\.name), ["M", "P", "C"],
                       "The root's module in the middle, the module it reaches most beside it, the next on the other side.")
        let root = try XCTUnwrap(layout.boxes.first { $0.item.label == "Page" })
        let lane = try XCTUnwrap(layout.lanes.first { $0.name == "P" })
        XCTAssertEqual(root.x + root.width / 2, lane.x + lane.width / 2, accuracy: 0.5, "The root sits centered in its lane.")
    }

    func testUndocumentedUsesForwardTheDocsOfWhatTheyReach() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Store.swift", """
        /// Keeps the shopper's cart.
        struct Store {
            private var cart: Cart
            private var note: Note
            func clear() { cart.empty() }
            func restart() { _ = Cart.make(); self.cart.empty() }
            func read() -> Int { note.count }
        }
        /// A cart.
        struct Cart {
            /// Removes every line.
            func empty() {}
            /// Makes an empty cart.
            static func make() -> Cart { Cart() }
        }
        /// A note left at checkout.
        struct Note {
            var count = 0
        }
        """)]))
        let cart = atlas.reasons(from: "Shop/Store", to: "Shop/Cart")
        XCTAssertEqual(cart.map(\.name), ["cart", "clear()", "restart()"],
                       "A body that reaches a type only through a property still depends on it.")
        XCTAssertEqual(cart[1].forwarded, [Reason.Forward(name: "empty()", summary: "Removes every line.")])
        XCTAssertEqual(cart[2].forwarded.map(\.name), ["make()", "empty()"], "Members named outright and through self alike.")
        XCTAssertEqual(cart[0].forwarded, [Reason.Forward(name: "Cart", summary: "A cart.")],
                       "A use that reaches no documented member forwards the type's own summary.")
        let note = atlas.reasons(from: "Shop/Store", to: "Shop/Note")
        XCTAssertEqual(note.last?.forwarded, [Reason.Forward(name: "Note", summary: "A note left at checkout.")],
                       "An undocumented member falls back to the type's summary.")
    }

    func testRoleWordsReadAsOneEnglishPhrase() {
        XCTAssertEqual(Wording.words([.property]), "holds")
        XCTAssertEqual(Wording.words([.parameter, .body]), "takes and uses")
        XCTAssertEqual(Wording.words([.property, .parameter, .returns]), "holds, takes, and returns")
        XCTAssertEqual(Wording.words([]), "")
    }

    func testReasonsQuoteTheDocWhereTheTypeIsUsed() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Store.swift", """
        /// Keeps the shopper's cart.
        struct Store {
            /// The cart being filled.
            var cart: Cart
            /// Adds an item to the cart.
            ///
            /// - Parameters:
            ///   - count: How many to add.
            ///   - item: The item to put in the cart.
            /// - Returns: The cart after the add.
            func add(_ count: Int, of item: Item) -> Cart { Cart() }
            func tidy() { _ = Item() }
        }
        struct Cart {}
        struct Item {}
        """)]))
        let cart = atlas.reasons(from: "Shop/Store", to: "Shop/Cart")
        XCTAssertEqual(cart.map(\.name), ["cart", "add(_:of:)"])
        XCTAssertEqual(cart.first?.summary, "The cart being filled.", "A property answers with its summary.")
        XCTAssertEqual(cart.last?.roles, [.returns, .body])
        XCTAssertEqual(cart.last?.entries, [Reason.Entry(role: .returns, parameter: nil, text: "The cart after the add.")])
        let item = atlas.reasons(from: "Shop/Store", to: "Shop/Item")
        XCTAssertEqual(item.map(\.name), ["add(_:of:)", "tidy()"], "Signature uses come before uses inside a body.")
        XCTAssertEqual(item.first?.entries, [Reason.Entry(role: .parameter, parameter: "item", text: "The item to put in the cart.")],
                       "Only the parameter that takes the type answers.")
        XCTAssertTrue(try XCTUnwrap(item.last).isUnexplained, "An undocumented use says nothing about why.")
        XCTAssertTrue(atlas.reasons(from: "Shop/Cart", to: "Shop/Store").isEmpty)
    }

    func testTrailsLeadBackToTheRootTopToBottom() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Types.swift", """
        struct Root { var a: A; var b: B }
        struct A { var c: C }
        struct B { var c: C }
        struct C { var d: D }
        struct D {}
        struct X { var y: Y }
        struct Y { var root: Root }
        """)]))
        func hops(_ trail: [GraphLayout.Link]) -> [String] { trail.map { "\($0.from)>\($0.to)" } }
        let down = try XCTUnwrap(atlas.reach(from: "Shop/Root", toward: .dependencies, depth: 3, minimumRank: 0))
        let toD = down.trails(to: "Shop/D")
        XCTAssertEqual(toD.trails.map(hops), [["Shop/Root>Shop/A", "Shop/A>Shop/C", "Shop/C>Shop/D"]],
                       "Below the root, a trail reads from the root down, climbing by the first way only.")
        let toC = down.trails(to: "Shop/C", limit: 1)
        XCTAssertEqual(toC.trails.count, 1)
        XCTAssertEqual(toC.more, 1, "A type reached from two types has two trails; the cap counts the rest.")
        XCTAssertTrue(down.trails(to: "Shop/Root").trails.isEmpty)
        let up = try XCTUnwrap(atlas.reach(from: "Shop/Root", toward: .users, depth: 2, minimumRank: 0))
        XCTAssertEqual(up.trails(to: "Shop/X").trails.map(hops), [["Shop/X>Shop/Y", "Shop/Y>Shop/Root"]],
                       "Above the root, a trail reads from the type down to the root, as the map draws it.")
    }

    func testReachStartsAtANestedTypeItself() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Map/Layout.swift", """
        struct Layout { var boxes: [Box]; struct Box { var item: Item }; struct Item { var unit: Unit } }
        struct Unit {}
        """)]))
        let box = try XCTUnwrap(atlas.reach(from: "Map/Layout.Box", toward: .dependencies, minimumRank: 0))
        XCTAssertEqual(box.layout.boxes.map(\.item.label), ["Layout.Box", "Layout.Item", "Unit"],
                       "A nested type reaches from itself, not from the type it is nested in.")
        let layout = try XCTUnwrap(atlas.reach(from: "Map/Layout", toward: .dependencies, minimumRank: 0))
        XCTAssertTrue(layout.layout.boxes.contains { $0.item.label == "Layout.Box" }, "A type's own nested types are among what it depends on.")
    }

    func testReachKeepsTheMostConnectedWhenOneStepIsOverTheBudget() throws {
        let fields = (0..<8).map { "var f\($0): T\($0)" }.joined(separator: "; ")
        let types = (0..<8).map { "struct T\($0) {}" }.joined(separator: "\n")
        let atlas = Atlas(Interface.build(sources: [("Sources/Hub/Hub.swift", "struct Hub { \(fields) }\nstruct Other { var t: T7 }\n\(types)")]))
        let reach = try XCTUnwrap(atlas.reach(from: "Hub/Hub", toward: .dependencies, minimumRank: 0, budget: 5))
        XCTAssertEqual(reach.drawn, 4)
        XCTAssertEqual(reach.overflow.count, 4)
        XCTAssertTrue(reach.layout.boxes.contains { $0.item.label == "T7" }, "The most connected type is kept.")
    }

    func testNotesKeepFencedCodeAsOneBlock() throws {
        let source = """
        /// Parses a name.
        ///
        /// Call it like this:
        ///
        /// ```swift
        /// let name = parse("a")
        ///
        /// print(name)
        /// ```
        func parse(_ text: String) {}
        """
        let contract = try XCTUnwrap(contracts(source).first)
        XCTAssertEqual(contract.notes, ["Call it like this:", "```swift\nlet name = parse(\"a\")\n\nprint(name)\n```"])
    }

    func testDeadLinksReachTheAssessments() {
        let interface = Interface.build(sources: [("Sources/Shop/Cart.swift", "/// A cart, unlike ``Basket``.\nstruct Cart {}")])
        XCTAssertEqual(interface.assessments.flatMap(\.findings).map(\.rule), ["dead-link"])
    }

    func testQuickOpenFindsTypesByWordStartsAndRanksExactNamesFirst() {
        let atlas = Atlas(Interface.build(sources: [("Sources/App/Views.swift", """
        struct DetailPaneView {}
        struct DetailPageView {}
        struct DependencyPicker {}
        struct Atlas { struct Reviewed {} }
        struct Layout {}
        struct GraphLayout {}
        """)]))
        func names(_ query: String) -> [String] { atlas.quickOpen(query).map(\.name) }
        XCTAssertEqual(names("dpv").prefix(2), ["DetailPaneView", "DetailPageView"], "Word starts beat scattered letters.")
        XCTAssertEqual(names("atlas").first, "Atlas", "An exact name ranks above a type nested in it.")
        XCTAssertEqual(names("layout").prefix(2), ["Layout", "GraphLayout"])
        XCTAssertEqual(names("reviewed"), ["Atlas.Reviewed"], "Nested types are found by their own name.")
        XCTAssertEqual(atlas.quickOpen("dpv").first?.matched, [0, 6, 10], "The matched letters are the word starts.")
        XCTAssertEqual(names(""), [])
        XCTAssertEqual(names("zzz"), [])
    }

    func testPropertyWrapperArgumentsCountAsWhatThePropertyHolds() {
        let interface = Interface.build(sources: [("Sources/App/Screen.swift", """
        final class Store {}
        struct Screen {
            @Environment(Store.self) private var store
            @State private var count = 0
        }
        """)])
        let edges = interface.graph.edges.map { "\($0.from) -> \($0.to) \($0.roles)" }
        XCTAssertEqual(edges, ["App/Screen -> App/Store [GlossCore.Mention.Role.property]"],
                       "A wrapper's argument is a dependency even with no type annotation; a wrapper no scanned source declares is not.")
    }

    func testOutlineFilesTypesUnderFoldersAndNestedTypesUnderTheirParents() throws {
        let atlas = Atlas(Interface.build(sources: [
            ("Sources/Big/Models/Cart.swift", "struct Cart { struct Line {} }"),
            ("Sources/Big/Models/Deep/Price.swift", "struct Price {}"),
            ("Sources/Big/App.swift", "struct App {}")
        ]))
        func shape(_ items: [OutlineItem]) -> [String] {
            items.map { item in
                let name: String = switch item.kind {
                case .folder(let name): name + "/"
                case .type(let node): atlas.shortLabel(node)
                }
                return item.children.isEmpty ? name : name + "(" + shape(item.children).joined(separator: " ") + ")"
            }
        }
        let all = atlas.outline(of: "Big", showing: { _ in true })
        XCTAssertEqual(shape(all), ["Models/(Deep/(Price) Cart(Line))", "App"])
        XCTAssertEqual(all.first?.typeCount, 3)
        let line = try XCTUnwrap(atlas.byID["Big/Cart.Line"])
        XCTAssertEqual(atlas.outlineAncestors(of: line), ["folder:Big/Models", "Big/Cart"])
        let found = atlas.outline(of: "Big", showing: { $0.id == "Big/Cart.Line" })
        XCTAssertEqual(shape(found), ["Models/(Cart(Line))"], "A match keeps the folders and types around it, and nothing else.")
    }

    func testZoomingOutClimbsFolderModuleAndOverview() {
        let small = Atlas(Interface.build(sources: [
            ("Sources/Shop/Cart.swift", "public struct Cart {}"),
            ("Sources/App/main.swift", "print(Cart())")
        ]))
        let scopes = small.mapScopes()
        let parents = Dictionary(uniqueKeysWithValues: scopes.map { ($0.id, $0.parent) })
        XCTAssertEqual(parents["s-types"], "s-modules")
        XCTAssertEqual(parents["s-m-Shop"], "s-modules")
        XCTAssertEqual(parents["s-modules"], .some(nil), "The module overview is the widest level.")
        let big = Atlas(Interface.build(sources: (0..<20).flatMap { [
            ("Sources/Big/Models/M\($0).swift", "struct M\($0) {}"),
            ("Sources/Big/Views/V\($0).swift", "struct V\($0) { var model: M\($0) }")
        ] }))
        let levels = big.mapScopes()
        XCTAssertEqual(levels.map(\.parent), [nil, "s-m-Big", "s-m-Big"])
    }

    func testLevelsOverTheBudgetListTheLeastConnected() {
        let types = (0..<35).map { ("Sources/Flat/T\($0).swift", $0 < 10 ? "struct T\($0) { var next: T\($0 + 1) }" : "struct T\($0) {}") }
        let atlas = Atlas(Interface.build(sources: types))
        let scope = atlas.mapScopes()[0]
        let figure = atlas.figure(scope, includeBody: true)
        XCTAssertEqual(figure.shown.count, Atlas.mapBudget)
        XCTAssertEqual(figure.overflow.count, 5)
        XCTAssertTrue(figure.shown.contains("Flat/T0"), "Connected types are kept over unconnected ones.")
    }

    func testFirstSentenceIgnoresPeriodsInCode() {
        XCTAssertEqual(Wording.firstSentence("Reads `a.b` first. Then more."), "Reads `a.b` first.")
        XCTAssertEqual(Wording.firstSentence("No period"), "No period")
    }

    func testInlineCodeSpans() {
        XCTAssertEqual(InterfacePage.inline("Use ``Cart/add(_:)`` or `x < y`."),
                       "Use <code class=\"link\">Cart/add(_:)</code> or <code>x &lt; y</code>.")
        XCTAssertEqual(InterfacePage.inline("An open ` tick"), "An open ` tick")
    }
}
