@testable import LucidRead
@testable import LucidLint
@testable import GlossModel
import GlossMap
import XCTest

/// Pins how an interface is compared with a base, and how a base is read from git.
final class DiffTests: XCTestCase {
    private let base = """
    /// A cart.
    struct Cart {
        /// Lines.
        var lines: [Line]
        /// The coupon applied, if any.
        var coupon: Coupon?
        /// The sum.
        func total() -> Int { _ = Helper(); return 0 }
        /// Adds a line.
        func add(_ line: Line) {}
    }
    /// A line.
    struct Line {}
    /// A coupon.
    struct Coupon {}
    /// Helps.
    struct Helper {}
    /// Checks out.
    struct Checkout {
        /// The cart checked out.
        var cart: Cart
        /// Charges the cart.
        func charge() { _ = cart.total() }
    }
    /// Prints a receipt.
    struct Receipt {
        /// The cart printed.
        var cart: Cart
        /// Prints it.
        func print(_ line: Line) { cart.add(line) }
    }
    """

    private let head = """
    /// A cart.
    struct Cart {
        /// The lines so far.
        var lines: [Line]
        /// The discount applied.
        var discount: Discount
        /// The sum.
        func total() -> Double { 0 }
        /// Adds a line.
        func add(_ line: Line) {}
        /// Tidies the cart.
        func tidy(_ helper: Helper) {}
    }


    /// A line.
    struct Line {}
    /// A discount.
    struct Discount {}
    /// Helps.
    struct Helper {}
    /// Checks out.
    struct Checkout {
        /// The cart checked out.
        var cart: Cart
        /// Charges the cart.
        func charge() { _ = cart.total() }
    }
    /// Prints a receipt.
    struct Receipt {
        /// The cart printed.
        var cart: Cart
        /// Prints it.
        func print(_ line: Line) { cart.add(line) }
    }
    """

    private func diff() -> InterfaceDiff {
        InterfaceDiff(base: Interface.build(sources: [("Sources/Shop/Cart.swift", base)]),
                      head: Interface.build(sources: [("Sources/Shop/Cart.swift", head)]))
    }

    func testNodesAreAddedRemovedOrChangedByTheirDeclarations() throws {
        let diff = diff()
        XCTAssertEqual(diff.change(ofNode: "Shop/Discount")?.change, .added)
        XCTAssertEqual(diff.change(ofNode: "Shop/Coupon")?.change, .removed)
        XCTAssertNil(diff.change(ofNode: "Shop/Line"), "A type that only moved is no change.")
        let cart = try XCTUnwrap(diff.change(ofNode: "Shop/Cart"))
        XCTAssertEqual(cart.change, .changed)
        func change(_ name: String) -> InterfaceDiff.DeclarationChange? { cart.declarations.first { $0.name == name } }
        XCTAssertEqual(change("lines").map { [$0.signatureChanged, $0.docChanged] }, [false, true], "Only the doc changed.")
        XCTAssertEqual(change("total()").map { [$0.signatureChanged, $0.docChanged] }, [true, false], "Only the signature changed.")
        XCTAssertEqual(change("discount")?.change, .added)
        XCTAssertEqual(change("tidy(_:)")?.change, .added)
        XCTAssertEqual(change("coupon")?.change, .removed)
        XCTAssertNil(change("add(_:)"), "A declaration written and documented the same is no change.")
    }

    func testDeclarationChangesKeepWhatWasWrittenAndWhatIs() throws {
        let cart = try XCTUnwrap(diff().change(ofNode: "Shop/Cart"))
        func change(_ name: String) -> InterfaceDiff.DeclarationChange? { cart.declarations.first { $0.name == name } }
        XCTAssertEqual(change("total()")?.was, "func total() -> Int")
        XCTAssertEqual(change("total()")?.now, "func total() -> Double")
        XCTAssertEqual(change("coupon")?.was, "var coupon: Coupon?")
        XCTAssertNil(try XCTUnwrap(change("coupon")).now, "Only the base has a gone one.")
        XCTAssertNil(try XCTUnwrap(change("discount")).was, "Only the head has a new one.")
        XCTAssertEqual(change("discount")?.now, "var discount: Discount")
    }

    func testChangeReasonsSayHowAChangeReachesANeighbor() throws {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Cart.swift", head)]))
        let diff = diff()
        let checkout = atlas.changeReasons(of: "Shop/Checkout", in: diff)
        XCTAssertEqual(checkout.count, 1)
        guard case .member(let total)? = checkout.first?.kind else { return XCTFail("Checkout reaches a member.") }
        XCTAssertEqual(total.name, "total()")
        XCTAssertEqual(checkout.first?.changed, "Shop/Cart")
        XCTAssertEqual(checkout.first?.via, ["Checkout.charge"], "The declaration that calls it.")
        let helper = atlas.changeReasons(of: "Shop/Helper", in: diff)
        guard case .dependency(let edge)? = helper.first?.kind else { return XCTFail("Helper is reached by its dependency.") }
        XCTAssertEqual([edge.from, edge.to], ["Shop/Cart", "Shop/Helper"])
        XCTAssertTrue(atlas.changeReasons(of: "Shop/Receipt", in: diff).isEmpty, "add(_:) did not change.")
        XCTAssertTrue(atlas.changeReasons(of: "Shop/Cart", in: diff).isEmpty, "A changed type is not reached; it changed.")
    }

    func testEdgesSayWhenADependencyEntersTheInterface() throws {
        let diff = diff()
        XCTAssertEqual(diff.change(from: "Shop/Cart", to: "Shop/Discount")?.change, .added)
        XCTAssertEqual(diff.change(from: "Shop/Cart", to: "Shop/Coupon")?.change, .removed)
        XCTAssertNil(diff.change(from: "Shop/Cart", to: "Shop/Line"), "Same roles through the same declarations.")
        let helper = try XCTUnwrap(diff.change(from: "Shop/Cart", to: "Shop/Helper"))
        XCTAssertEqual(helper.before, [.body])
        XCTAssertEqual(helper.after, [.parameter])
        XCTAssertTrue(helper.entersInterface, "Used only inside a body before, taken as a parameter now.")
        XCTAssertEqual(helper.viaAdded, ["Cart.tidy"])
        XCTAssertEqual(helper.viaRemoved, ["Cart.total"])
        XCTAssertTrue(try XCTUnwrap(diff.change(from: "Shop/Cart", to: "Shop/Coupon")).leavesInterface)
    }

    func testBoxesFoldWhatTheyHoldIntoOneMark() {
        let head = Interface.build(sources: [("Sources/Shop/Cart.swift", head), ("Sources/Promo/Promo.swift", "/// A promo.\nstruct Promo {}")])
        let diff = InterfaceDiff(base: Interface.build(sources: [("Sources/Shop/Cart.swift", base)]), head: head)
        let atlas = Atlas(head)
        XCTAssertEqual(atlas.change(of: .type("Shop/Discount"), in: diff), .added)
        XCTAssertEqual(atlas.change(of: .type("Shop/Cart"), in: diff), .changed)
        XCTAssertNil(atlas.change(of: .type("Shop/Line"), in: diff))
        XCTAssertEqual(atlas.change(of: .module("Shop"), in: diff), .changed, "A module holding changes, a removed type among them.")
        XCTAssertEqual(atlas.change(of: .module("Promo"), in: diff), .added, "A module whose every type is new is new.")
        XCTAssertEqual(atlas.change(of: .folder("Shop", ""), in: diff), .changed)
    }

    func testTheChangesFigureDrawsOnlyWhatAChangeReaches() {
        let atlas = Atlas(Interface.build(sources: [("Sources/Shop/Cart.swift", head)]))
        let diff = diff()
        let figure = atlas.changesFigure(diff, minimumRank: 0)
        XCTAssertEqual(Set(figure.layout.boxes.map(\.item.label)), ["Cart", "Discount", "Helper", "Checkout"],
                       "Helper's dependency changed and Checkout calls total(), whose signature changed.")
        XCTAssertEqual(Set(figure.untouched), ["Shop/Line", "Shop/Receipt"],
                       "Cart uses Line as it did, and Receipt only calls add(_:), which did not change.")
        XCTAssertTrue(figure.layout.curves.allSatisfy { ["Shop/Cart", "Shop/Discount"].contains($0.link.from) || ["Shop/Cart", "Shop/Discount"].contains($0.link.to) },
                      "Only dependencies with a change at an end.")
        let everything = atlas.changesFigure(diff, minimumRank: 0, includeUntouched: true)
        XCTAssertEqual(everything.layout.boxes.count, 6, "Asked for, the untouched are drawn too.")
        XCTAssertTrue(everything.untouched.isEmpty)
        let tight = atlas.changesFigure(diff, minimumRank: 0, budget: 2)
        XCTAssertEqual(tight.layout.boxes.count, 2)
        XCTAssertEqual(Set(tight.overflow), ["Shop/Helper", "Shop/Checkout"], "Neighbors give way to changes.")
        let tighter = atlas.changesFigure(diff, minimumRank: 0, budget: 1)
        XCTAssertEqual(tighter.layout.boxes.map(\.item.label), ["Cart"], "The most connected change stays.")
        XCTAssertEqual(tighter.overflow.first, "Shop/Discount")
        XCTAssertEqual(tighter.overflow.count, Set(tighter.overflow).count, "A change left out is not listed again as a neighbor.")
    }

    func testABodyChangedAloneIsAChangeInside() throws {
        let before = Interface.build(sources: [("Sources/Shop/Pad.swift", """
        /// Pads.
        struct Pad {
            /// Pads a value.
            func pad(_ value: Int) -> Int { value + 1 }
            /// Trims a value.
            func trim(_ value: Int) -> Int { value - 1 }
        }
        """)])
        let after = Interface.build(sources: [("Sources/Shop/Pad.swift", """
        /// Pads.
        struct Pad {
            /// Pads a value.
            func pad(_ value: Int) -> Int { value + 2 }
            /// Trims a value.
            func trim(_ value: Int) -> Int {
                // Only spacing and a comment differ.
                value   -   1
            }
        }
        """)])
        let pad = try XCTUnwrap(InterfaceDiff(base: before, head: after).change(ofNode: "Shop/Pad"))
        XCTAssertEqual(pad.change, .implementation, "Declared and documented the same; only a body differs.")
        XCTAssertEqual(pad.declarations.map(\.name), ["pad(_:)"], "Reformatting and comments are no change.")
        XCTAssertEqual(pad.declarations.first?.bodyChanged, true)
        XCTAssertEqual(Atlas(after).change(of: .type("Shop/Pad"), in: InterfaceDiff(base: before, head: after)), .implementation)
    }

    func testADroppedDependencyReachesTheTypeItWasOn() throws {
        let before = Interface.build(sources: [("Sources/Shop/Cart.swift", """
        /// A cart.
        struct Cart {
            /// Totals it.
            func total() -> Int { Ledger.sum() }
        }
        /// A ledger.
        struct Ledger {
            /// Sums.
            static func sum() -> Int { 0 }
        }
        """)])
        let after = Interface.build(sources: [("Sources/Shop/Cart.swift", """
        /// A cart.
        struct Cart {
            /// Totals it.
            func total() -> Int { 0 }
        }
        /// A ledger.
        struct Ledger {
            /// Sums.
            static func sum() -> Int { 0 }
        }
        """)])
        let diff = InterfaceDiff(base: before, head: after)
        XCTAssertEqual(diff.change(from: "Shop/Cart", to: "Shop/Ledger")?.change, .removed)
        let atlas = Atlas(after)
        let figure = atlas.changesFigure(diff, minimumRank: 0)
        XCTAssertEqual(Set(figure.layout.boxes.map(\.item.label)), ["Cart", "Ledger"], "The type it no longer uses is reached.")
        XCTAssertEqual(figure.layout.curves.map(\.link.title), ["Cart no longer uses Ledger"])
        let reasons = atlas.changeReasons(of: "Shop/Ledger", in: diff)
        guard case .dependency(let edge)? = reasons.first?.kind else { return XCTFail("Ledger is reached by the dropped dependency.") }
        XCTAssertEqual(edge.change, .removed)
    }

    func testAnInterfaceComparedWithItselfHasNoChanges() {
        let interface = Interface.build(sources: [("Sources/Shop/Cart.swift", base)])
        XCTAssertTrue(InterfaceDiff(base: interface, head: interface).isEmpty)
    }

    func testOverloadsPairByWhatIsWrittenBeforeOrder() throws {
        let before = Interface.build(sources: [("Sources/Shop/Pad.swift", """
        /// Pads.
        struct Pad {
            /// Pads an int.
            func pad(_ value: Int) {}
            /// Pads a string.
            func pad(_ value: String) {}
        }
        """)])
        let after = Interface.build(sources: [("Sources/Shop/Pad.swift", """
        /// Pads.
        struct Pad {
            /// Pads a string.
            func pad(_ value: String) {}
            /// Pads an int.
            func pad(_ value: Int) {}
        }
        """)])
        XCTAssertTrue(InterfaceDiff(base: before, head: after).isEmpty, "Reordered overloads are no change.")
    }

    func testARevisionIsReadFromGitAsTheDiskWouldBeRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gloss-diff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources/Shop")
        let tests = root.appendingPathComponent("Tests/ShopTests")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try base.write(to: sources.appendingPathComponent("Cart.swift"), atomically: true, encoding: .utf8)
        try "struct CartTests {}".write(to: tests.appendingPathComponent("CartTests.swift"), atomically: true, encoding: .utf8)
        try git(["init", "-q"], in: root)
        try git(["add", "."], in: root)
        try git(["-c", "user.name=gloss", "-c", "user.email=gloss@example.com", "commit", "-q", "-m", "base"], in: root)
        try head.write(to: sources.appendingPathComponent("Cart.swift"), atomically: true, encoding: .utf8)

        let read = try Revision.sources(at: "HEAD", under: root.appendingPathComponent("Sources").path,
                                        relativeTo: root.path, includeTests: false)
        XCTAssertEqual(read.map(\.file), ["Sources/Shop/Cart.swift"], "Paths read as the working tree reports them, tests left out.")
        XCTAssertEqual(read.first?.source, base, "The committed text, not the edit on disk.")
        XCTAssertThrowsError(try Revision.sources(at: "nowhere", under: root.path, relativeTo: root.path, includeTests: false))

        try git(["branch", "-q", "-M", "develop"], in: root)
        try git(["tag", "v1"], in: root)
        XCTAssertEqual(try Revision.currentBranch(in: root.path), "develop")
        XCTAssertEqual(try Revision.refs(in: root.path), [Revision.Ref(name: "develop", kind: .branch), Revision.Ref(name: "v1", kind: .tag)])
    }

    func testEachChangeKnowsTheCommitsThatMadeIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gloss-why-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sources/Shop")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Cart.swift")
        func write(_ text: String) throws { try text.write(to: file, atomically: true, encoding: .utf8) }
        func commit(_ message: String) throws {
            try git(["add", "."], in: root)
            try git(["-c", "user.name=gloss", "-c", "user.email=gloss@example.com", "commit", "-q", "-m", message], in: root)
        }
        try git(["init", "-q"], in: root)
        try write("""
        /// A cart.
        struct Cart {
            /// The sum.
            func total() -> Int { 0 }
            /// The coupon applied.
            var coupon: Int?
            /// Adds a line.
            func add(_ line: Int) {}
        }
        """)
        try commit("Start the cart")
        let base = try XCTUnwrap(try Revision.commit("HEAD", in: root.path))
        try write("""
        /// A cart.
        struct Cart {
            /// The sum.
            func total() -> Double { 0 }
            /// Adds a line.
            func add(_ line: Int) {}
        }
        """)
        try commit("Return a Double from total")
        try write("""
        /// A cart.
        struct Cart {
            /// The sum.
            func total() -> Double { 0 }
            /// Adds a line.
            func add(_ line: Int) {}
            /// Tidies the cart.
            func tidy() {}
        }
        """)
        try commit("Add tidy\n\nSo a cart can drop empty lines.")
        let now = """
        /// A cart.
        struct Cart {
            /// The sum.
            func total() -> Double { 0 }
            /// Adds one line to the cart.
            func add(_ line: Int) {}
            /// Tidies the cart.
            func tidy() {}
        }
        """
        try write(now)

        let before = Interface.build(sources: try Revision.sources(at: base, under: root.appendingPathComponent("Sources").path,
                                                                 relativeTo: root.path, includeTests: false))
        let diff = InterfaceDiff(base: before, head: Interface.build(sources: [("Sources/Shop/Cart.swift", now)]))
        let commits = try ChangeCommits.read(diff, base: base, head: nil, root: root.path)
        let cart = try XCTUnwrap(diff.change(ofNode: "Shop/Cart"))
        func change(_ name: String) throws -> InterfaceDiff.DeclarationChange { try XCTUnwrap(cart.declarations.first { $0.name == name }) }
        XCTAssertEqual(commits.commits.map(\.subject), ["Return a Double from total", "Add tidy"], "The range's commits, oldest first.")
        XCTAssertEqual(try commits.commits(for: change("total()")).map(\.subject), ["Return a Double from total"])
        XCTAssertEqual(try commits.commits(for: change("coupon")).map(\.subject), ["Return a Double from total"], "The commit that deleted it.")
        XCTAssertEqual(try commits.commits(for: change("tidy()")).map(\.body), ["So a cart can drop empty lines."])
        XCTAssertTrue(try commits.commits(for: change("add(_:)")).isEmpty)
        XCTAssertTrue(try commits.isUncommitted(change("add(_:)")), "Its doc is edited and not committed.")
        XCTAssertFalse(try commits.isUncommitted(change("total()")))
        XCTAssertEqual(try change("add(_:)").wasSummary, "Adds a line.")
        XCTAssertEqual(commits.commits(for: cart).count, 2)
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }

    /// A cart with a nested line and a ledger that holds one, each file read from the module its key names.
    private func shop(_ modules: [String: String], cartDoc: String = "A cart.") -> Interface {
        Interface.build(sources: [
            ("Sources/\(modules["cart"]!)/Cart.swift", "/// \(cartDoc)\nstruct Cart {\n    /// One line.\n    struct Line {}\n}"),
            ("Sources/\(modules["ledger"]!)/Ledger.swift", "/// A ledger.\nstruct Ledger {\n    /// The cart it records.\n    var cart: Cart\n}")
        ])
    }

    func testATypeThatMovesModulesIsOneMoveWithItsNestedTypesAndDependencies() throws {
        let before = shop(["cart": "Old", "ledger": "Old"])
        let after = shop(["cart": "New", "ledger": "Old"])
        let diff = InterfaceDiff(base: before, head: after)
        XCTAssertEqual(diff.nodes.map(\.node.id), ["New/Cart", "New/Cart.Line"], "No gone cart beside the new one.")
        let cart = try XCTUnwrap(diff.change(ofNode: "New/Cart"))
        XCTAssertEqual(cart.change, .moved)
        XCTAssertEqual(cart.movedFrom?.id, "Old/Cart")
        XCTAssertTrue(cart.declarations.isEmpty, "Declared the same where it went.")
        XCTAssertEqual(diff.change(ofNode: "Old/Cart")?.node.id, "New/Cart", "The id it had finds the move.")
        XCTAssertEqual(diff.change(ofNode: "New/Cart.Line")?.change, .moved)
        XCTAssertTrue(diff.edges.isEmpty, "The ledger still holds a cart; it only lives elsewhere.")
        XCTAssertEqual(Atlas(after).change(of: .type("New/Cart"), in: diff), .moved)
        XCTAssertEqual(Atlas(after).change(of: .module("New"), in: diff), .moved, "Everything in New moved in.")
    }

    func testAMovedTypeStillSaysWhatChangedInIt() throws {
        let diff = InterfaceDiff(base: shop(["cart": "Old", "ledger": "Old"]), head: shop(["cart": "New", "ledger": "Old"], cartDoc: "A cart of lines."))
        let cart = try XCTUnwrap(diff.change(ofNode: "New/Cart"))
        XCTAssertEqual(cart.change, .moved)
        XCTAssertEqual(cart.declarations.map(\.name), ["Cart"])
        XCTAssertEqual(cart.declarations.first?.docChanged, true)
    }

    func testAMoveIsMatchedOnlyWhenItsNameIsUnique() {
        let twice = InterfaceDiff(base: Interface.build(sources: [("Sources/A/Cart.swift", "/// A cart.\nstruct Cart {}"),
                                                                 ("Sources/B/Cart.swift", "/// A cart.\nstruct Cart {}")]),
                                  head: Interface.build(sources: [("Sources/C/Cart.swift", "/// A cart.\nstruct Cart {}")]))
        XCTAssertEqual(twice.nodes.map { "\($0.change) \($0.node.id)" }, ["added C/Cart", "removed A/Cart", "removed B/Cart"],
                       "Two carts gone, so which one moved is not guessed.")
        let extended = InterfaceDiff(base: Interface.build(sources: [("Sources/Core/Cart.swift", "/// A cart.\nstruct Cart {}")]),
                                     head: Interface.build(sources: [("Sources/Read/Cart.swift", "/// A cart.\nstruct Cart {}"),
                                                                     ("Sources/Lint/Cart.swift", "extension Cart {\n    /// Checks it.\n    func check() {}\n}")]))
        XCTAssertEqual(extended.nodes.map { "\($0.change) \($0.node.id)" }, ["moved Read/Cart", "added Lint/Cart"],
                       "An extension beside a moved type is new, not a second candidate.")
    }
}
