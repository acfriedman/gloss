@testable import GlossRead
@testable import GlossLint
@testable import GlossModel
import GlossMap
import Foundation
import XCTest

/// Pins what a commit hook's lint judges: the commit as staged, and only the declarations it touched.
final class ChangeLintTests: XCTestCase {
    private let legacy = """
    struct Checkout {
        /// Charges the cart.
        func charge() {}
        func refund() {}
        /// Voids it.
        func void() { print("void") }
    }
    """

    private func findings(_ base: String, _ head: String) -> [String] {
        let reading = Reading(sources: [("App/Checkout.swift", head), ("App/Cart.swift", "/// A cart.\nstruct Cart {}")])
        let diff = InterfaceDiff(base: Interface.build(sources: [("App/Checkout.swift", base), ("App/Cart.swift", "/// A cart.\nstruct Cart {}")]),
                                 head: Interface.build(reading))
        return ChangedFindings(diff).filter(Linter.check(reading)).map { "\($0.line) \($0.rule.rawValue)" }
    }

    func testOnlyTheDeclarationsAChangeTouchedAreJudged() {
        let head = legacy
            .replacingOccurrences(of: "/// Charges the cart.\n    func charge() {}", with: "/// Charges the ``Cart``, unlike ``Basket``.\n    func charge(_ amount: Int) {}")
            .replacingOccurrences(of: "func void() { print(\"void\") }", with: "func void() { print(\"voided\") }")
        XCTAssertEqual(findings(legacy, head), ["2 dead-link", "2 parameter-missing"],
                       "The changed charge is judged in full, its link to the untouched cart resolving, and the touched void has no finding; the untouched type and refund keep theirs unreported.")
    }

    func testABodyOnlyEditStillAnswersForTheDoc() {
        let base = "/// Voids.\nstruct Checkout {\n    func void() { print(1) }\n}"
        let head = "/// Voids.\nstruct Checkout {\n    func void() { print(2) }\n}"
        XCTAssertEqual(findings(base, head), ["3 missing-doc"], "Touching a declaration's body makes its missing doc this change's to fix.")
        XCTAssertEqual(findings(base, base), [], "Nothing changed, so nothing is judged.")
    }

    func testAMovedTypeTouchesNothing() {
        let cart = "struct Cart {\n    func total() -> Int { 0 }\n}"
        let diff = InterfaceDiff(base: Interface.build(sources: [("Sources/Old/Cart.swift", cart)]),
                                 head: Interface.build(sources: [("Sources/New/Cart.swift", cart)]))
        XCTAssertEqual(ChangedFindings(diff).count, 0)
    }

    func testTheIndexIsReadNotTheWorkingTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gloss-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("App/Cart.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try git(["init", "-q"], in: root)
        try Data("struct Cart {}\n".utf8).write(to: file)
        try git(["add", "-A"], in: root)
        try git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "Add a cart"], in: root)
        try Data("struct Cart { var staged = 1 }\n".utf8).write(to: file)
        try git(["add", "-A"], in: root)
        try Data("struct Cart { var unstaged = 2 }\n".utf8).write(to: file)
        let staged = try Revision.stagedSources(under: root.path, relativeTo: root.path, includeTests: false)
        XCTAssertEqual(staged.map(\.file), ["App/Cart.swift"])
        XCTAssertEqual(staged.first?.source, "struct Cart { var staged = 1 }\n", "What the commit will hold, not the edit after it.")
        XCTAssertEqual(try Revision.sources(at: "HEAD", under: root.path, relativeTo: root.path, includeTests: false).first?.source, "struct Cart {}\n")
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
