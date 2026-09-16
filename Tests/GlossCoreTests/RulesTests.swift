@testable import GlossCore
import XCTest

/// Pins each rule against a literal doc comment, so a message or threshold change is a visible diff.
final class RulesTests: XCTestCase {
    private func lint(_ source: String) -> [Rule] {
        Checker.check(source: source, file: "T.swift").map(\.rule)
    }

    func testConformingFunctionIsClean() {
        let source = """
        /// Records the probe and advances the schedule. Recording first keeps replay deterministic.
        ///
        /// - Parameters:
        ///   - probe: The probe to record; must be unique per run.
        ///   - budget: How many more probes may follow; zero ends the sweep.
        /// - Returns: The schedule position the probe was recorded at.
        /// - Throws: ``SweepError/exhausted`` when `budget` is zero.
        func record(_ probe: Probe, budget: Int) throws -> Int { 0 }
        """
        XCTAssertEqual(lint(source), [])
    }

    func testSingleParameterFormIsAccepted() {
        let source = """
        /// Returns the canonical name.
        ///
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
        XCTAssertEqual(lint("/// Handles e.g. ``Foo/bar()`` calls. Needed for parity.\nfunc f() {}"), [])
        XCTAssertEqual(lint("///\n/// Records it.\nfunc f() {}"), [.summaryEmpty])
    }

    func testMarkupSpacing() {
        XCTAssertEqual(lint("/// Records it.\n/// - Returns: It.\nfunc f() -> Int { 0 }"), [.markupSpacing])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Returns: It.\nfunc f() -> Int { 0 }"), [])
    }

    func testMarkupRules() {
        XCTAssertEqual(lint("/// Records it.\n///\n/// - returns: Nothing.\nfunc f() -> Int { 0 }"), [.markupCase])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Return: It.\nfunc f() -> Int { 0 }"), [.markupUnknown, .returnsMissing])
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
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Parameter a: A.\n///\n/// - Parameter c: C.\nfunc f(a: Int) {}"), [.parameterUnknown])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Parameter a:\nfunc f(a: Int) {}"), [.parameterEmpty])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Parameter at: The index.\nfunc f(at index: Int) {}"), [])
        let mixed = """
        /// Records it.
        ///
        /// - Parameters:
        ///   - a: A.
        /// - Parameter b: B.
        func f(a: Int, b: Int) {}
        """
        XCTAssertEqual(lint(mixed), [.parameterForm])
    }

    func testReturnsAndThrows() {
        XCTAssertEqual(lint("/// Records it.\nfunc f() -> Int { 0 }"), [.returnsMissing])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Returns: Nothing.\nfunc f() {}"), [.returnsUnexpected])
        XCTAssertEqual(lint("/// Records it.\nfunc f() throws {}"), [.throwsMissing])
        XCTAssertEqual(lint("/// Records it.\n///\n/// - Throws: Never.\nfunc f() {}"), [.throwsUnexpected])
        XCTAssertEqual(lint("/// Records it.\nfunc f() -> Void {}"), [])
    }

    func testTypesAndPropertiesOnlyGetSummaryRules() {
        XCTAssertEqual(lint("struct S {}"), [.missingDoc])
        XCTAssertEqual(lint("/// A bag of probes.\nstruct S { var count: Int }"), [])
        XCTAssertEqual(lint("/// A bag of probes.\nstruct S {\n    /// how many\n    var count: Int\n}"), [.summaryCapital, .summarySentences, .summaryTerminator])
    }

    func testKnownRequirementsAreExempt() {
        XCTAssertEqual(lint("struct S: Decodable {\n    init(from decoder: Decoder) throws {}\n}"), [.missingDoc])
        XCTAssertEqual(lint("/// A thing.\nstruct S: Decodable {\n    init(from decoder: Decoder) throws {}\n}"), [])
        XCTAssertEqual(lint("/// A thing.\nstruct S {\n    func hash(into hasher: inout Hasher) {}\n    static func buildBlock(_ parts: Int...) -> Int { 0 }\n}"), [])
    }

    func testConformanceExtensionMembersNeedNoDocButKeepShape() {
        XCTAssertEqual(lint("extension S: P {\n    func requirement() -> Int { 0 }\n}"), [])
        XCTAssertEqual(lint("extension S {\n    func helper() -> Int { 0 }\n}"), [.missingDoc])
        XCTAssertEqual(lint("extension S: P {\n    /// Does it.\n    func requirement() -> Int { 0 }\n}"), [.returnsMissing])
    }

    func testExemptMarker() {
        XCTAssertEqual(lint("// gloss:exempt implements Foo.bar, documented there\nfunc bar() {}"), [])
        XCTAssertEqual(lint("// gloss:exempt\nfunc bar() {}"), [.exemptReason])
        XCTAssertEqual(lint("// gloss:exempt because\n/// Does it.\nfunc bar() {}"), [.exemptDocumented])
    }

    func testLocalDeclarationsAreSkipped() {
        XCTAssertEqual(lint("/// Runs it.\nfunc f() { func g() {}; struct T {} }"), [])
    }
}

extension RulesTests {
    func testCodeSpansMatchByBacktickRunLength() {
        XCTAssertEqual(Sentences.stripCodeSpans("a `` ```x <y> `` b."), "a ` b.")
        XCTAssertEqual(Sentences.stripCodeSpans("a `x` b."), "a ` b.")
        XCTAssertEqual(Sentences.stripCodeSpans("a `x b."), "a `x b.")
        XCTAssertEqual(lint("/// The spec a `` ```fence <spec> `` names. Needed for parity.\nfunc f() {}"), [])
    }

    func testMisplacedMarkupBlockIsOneFinding() {
        let source = """
        /// Records it.
        ///
        /// Some notes first.
        /// - Parameters:
        ///   - a: A.
        ///   - b: B.
        /// - Returns: It.
        func f(a: Int, b: Int) -> Int { 0 }
        """
        XCTAssertEqual(lint(source), [.markupOrder])
    }

    func testMembersOfPrivateTypesArePrivate() {
        XCTAssertEqual(lint("private struct S { func f() {} }"), [])
        XCTAssertEqual(lint("fileprivate enum E { struct T { func f() {} } }"), [])
        XCTAssertEqual(lint("private extension S { func f() {} }"), [])
        XCTAssertEqual(lint("/// A thing.\nstruct S { private struct T { func f() {} }\n    func g() {} }"), [.missingDoc])
    }

    func testMacroDeclarationsAreCallables() {
        XCTAssertEqual(lint("@attached(member) public macro Traced(label: String) = #externalMacro(module: \"M\", type: \"T\")"),
                       [.missingDoc])
        XCTAssertEqual(lint("/// Instruments the type. Needed for capture.\n///\n/// - Parameter label: The trace label.\n@attached(member) public macro Traced(label: String) = #externalMacro(module: \"M\", type: \"T\")"),
                       [])
    }

    func testBacktickedNamesAreChecked() {
        XCTAssertEqual(lint("func `default`() {}"), [.missingDoc])
    }
}

extension RulesTests {
    func testMemberwiseInitializersNeedNoDocAndNoEntries() {
        let plain = "/// A pair.\nstruct S {\n    var a: Int; var b: Int\n    init(a: Int, into b: Int) { self.a = a; self.b = b }\n}"
        XCTAssertEqual(lint(plain), [])
        let summarized = "/// A pair.\nstruct S {\n    var a: Int\n    /// Builds a pair.\n    init(a: Int) { self.a = a }\n}"
        XCTAssertEqual(lint(summarized), [])
        let computed = "/// A pair.\nstruct S {\n    var a: Int\n    init(a: Int) { self.a = a + 1 }\n}"
        XCTAssertEqual(lint(computed), [.missingDoc])
        let extra = "/// A pair.\nstruct S {\n    var a: Int\n    init(a: Int) { self.a = a; validate() }\n}"
        XCTAssertEqual(lint(extra), [.missingDoc])
        XCTAssertEqual(lint("/// A pair.\nstruct S {\n    init() {}\n}"), [.missingDoc])
    }
}

extension RulesTests {
    func testSymbolLinks() {
        XCTAssertEqual(lint("/// Pairs with `advance(_:)` later.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Reads `TraceContext.current` first.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Reads `Spec.verify(replaying:)` first.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Pairs with ``advance(_:)`` later.\nfunc f() {}"), [])
        XCTAssertEqual(lint("/// Reads ``TraceContext/current`` first.\nfunc f() {}"), [])
        XCTAssertEqual(lint("/// Uses `nil`, `.strict`, `Date()`, `NotificationCenter.default`, and `\"a.b\"`.\nfunc f() {}"), [])
        XCTAssertEqual(SymbolReference.linkForm("Spec.verify(replaying:)"), "Spec/verify(replaying:)")
    }
}
