import GlossCore
import XCTest

/// Pins each rule against a literal doc comment, so a message or threshold change is a visible diff.
final class RulesTests: XCTestCase {
    private func lint(_ source: String) -> [Rule] {
        Checker.check(source: source, file: "T.swift").map(\.rule)
    }

    func testConformingFunctionIsClean() {
        let source = """
        /// Records the probe and advances the schedule. Recording first keeps replay deterministic.
        /// - Parameters:
        ///   - probe: The probe to record; must be unique per run.
        ///   - budget: How many more probes may follow; zero ends the sweep.
        /// - Returns: The schedule position the probe was recorded at.
        /// - Throws: `SweepError.exhausted` when `budget` is zero.
        func record(_ probe: Probe, budget: Int) throws -> Int { 0 }
        """
        XCTAssertEqual(lint(source), [])
    }

    func testSingleParameterFormIsAccepted() {
        let source = """
        /// Returns the canonical name.
        /// - Parameter raw: The name as typed, any case.
        /// - Returns: The lowercased name.
        func canonical(raw: String) -> String { raw }
        """
        XCTAssertEqual(lint(source), [])
    }

    func testMissingDocOnInternalFunctionOnlyNotPrivate() {
        XCTAssertEqual(lint("func f() {}"), [.missingDoc])
        XCTAssertEqual(lint("private func f() {}"), [])
        XCTAssertEqual(lint("override func f() {}"), [])
    }

    func testBlockCommentIsRefused() {
        XCTAssertEqual(lint("/** Does a thing. */\nfunc f() {}"), [.blockDoc])
    }

    func testSummaryShape() {
        XCTAssertEqual(lint("/// Records the probe\nfunc f() {}"), [.summarySentences, .summaryTerminator])
        XCTAssertEqual(lint("/// One. Two. Three.\nfunc f() {}"), [.summarySentences])
        XCTAssertEqual(lint("/// records it.\nfunc f() {}"), [.summaryCapital])
        XCTAssertEqual(lint("/// This method records it.\nfunc f() {}"), [.summaryOpener])
        XCTAssertEqual(lint("/// Handles e.g. `Foo.bar()` calls. Needed for parity.\nfunc f() {}"), [])
        XCTAssertEqual(lint("///\n/// Records it.\nfunc f() {}"), [.summaryEmpty])
    }

    func testMarkupRules() {
        XCTAssertEqual(lint("/// Records it.\n/// - returns: Nothing.\nfunc f() -> Int { 0 }"), [.markupCase])
        XCTAssertEqual(lint("/// Records it.\n/// - Return: It.\nfunc f() -> Int { 0 }"), [.markupUnknown, .returnsMissing])
        let split = """
        /// Records it.
        ///
        /// Some notes first.
        /// - Returns: It.
        func f() -> Int { 0 }
        """
        XCTAssertEqual(lint(split), [.markupOrder])
    }

    func testParameterCoverage() {
        XCTAssertEqual(lint("/// Records it.\nfunc f(a: Int, at b: Int) {}"), [.parameterMissing, .parameterMissing])
        XCTAssertEqual(lint("/// Records it.\n/// - Parameter a: A.\n/// - Parameter c: C.\nfunc f(a: Int) {}"), [.parameterUnknown])
        XCTAssertEqual(lint("/// Records it.\n/// - Parameter a:\nfunc f(a: Int) {}"), [.parameterEmpty])
        XCTAssertEqual(lint("/// Records it.\n/// - Parameter at: The index.\nfunc f(at index: Int) {}"), [])
        let mixed = """
        /// Records it.
        /// - Parameters:
        ///   - a: A.
        /// - Parameter b: B.
        func f(a: Int, b: Int) {}
        """
        XCTAssertEqual(lint(mixed), [.parameterForm])
    }

    func testReturnsAndThrows() {
        XCTAssertEqual(lint("/// Records it.\nfunc f() -> Int { 0 }"), [.returnsMissing])
        XCTAssertEqual(lint("/// Records it.\n/// - Returns: Nothing.\nfunc f() {}"), [.returnsUnexpected])
        XCTAssertEqual(lint("/// Records it.\nfunc f() throws {}"), [.throwsMissing])
        XCTAssertEqual(lint("/// Records it.\n/// - Throws: Never.\nfunc f() {}"), [.throwsUnexpected])
        XCTAssertEqual(lint("/// Records it.\nfunc f() -> Void {}"), [])
    }

    func testTypesAndPropertiesOnlyGetSummaryRules() {
        XCTAssertEqual(lint("struct S {}"), [.missingDoc])
        XCTAssertEqual(lint("/// A bag of probes.\nstruct S { var count: Int }"), [])
        XCTAssertEqual(lint("/// A bag of probes.\nstruct S {\n    /// how many\n    var count: Int\n}"), [.summaryCapital, .summarySentences, .summaryTerminator])
    }

    func testLocalDeclarationsAreSkipped() {
        XCTAssertEqual(lint("/// Runs it.\nfunc f() { func g() {}; struct T {} }"), [])
    }
}
