@testable import GlossCore
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
}
