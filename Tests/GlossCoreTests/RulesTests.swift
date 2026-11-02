@testable import GlossCore
import XCTest

/// Pins each rule against a literal doc comment, so a message or threshold change is a visible diff.
final class RulesTests: XCTestCase {
    private func lint(_ source: String) -> [Rule] {
        Linter.check(source: source, file: "T.swift").map(\.rule)
    }

    func testConformingFunctionIsClean() {
        let source = """
        /// Stores the item and advances the cursor. Storing first keeps retries idempotent.
        ///
        /// - Parameters:
        ///   - item: The item to store; must be unique per batch.
        ///   - budget: How many more items may follow; zero ends the batch.
        /// - Returns: The cursor position the item was stored at.
        /// - Throws: ``QueueError/exhausted`` when `budget` is zero.
        func store(_ item: Item, budget: Int) throws -> Int { 0 }
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
        XCTAssertEqual(lint("/// Stores the item\nfunc f() {}"), [.summarySentences, .summaryTerminator])
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

    func testTypesPropertiesAndCasesNeedDocsButOnlySummaryRules() {
        XCTAssertEqual(lint("struct S {}"), [.missingDoc])
        XCTAssertEqual(lint("/// A bag of items.\nstruct S { var count: Int }"), [.missingDoc])
        XCTAssertEqual(lint("/// A bag of items.\nstruct S {\n    /// How many items it holds.\n    var count: Int\n}"), [])
        XCTAssertEqual(lint("/// A bag of items.\nstruct S {\n    /// how many\n    var count: Int\n}"), [.summaryCapital, .summarySentences, .summaryTerminator])
        XCTAssertEqual(lint("/// A bag of items.\nstruct S { private var count: Int }"), [])
        XCTAssertEqual(lint("/// A bag of items.\nstruct S { public private(set) var count: Int }"), [.missingDoc], "A private setter keeps the getter public.")
        XCTAssertEqual(lint("/// A color.\nenum C {\n    case red\n    /// The color of grass.\n    case green\n}"), [.missingDoc])
    }

    func testParameterEntriesFollowTheSignatureOnce() {
        let outOfOrder = "/// Moves it.\n///\n/// - Parameters:\n///   - to: Where it goes.\n///   - from: Where it was.\nfunc move(from: Int, to: Int) {}"
        XCTAssertEqual(lint(outOfOrder), [.parameterOrder])
        let twice = "/// Moves it.\n///\n/// - Parameters:\n///   - from: Where it was.\n///   - from: Again.\n///   - to: Where it goes.\nfunc move(from: Int, to: Int) {}"
        XCTAssertEqual(lint(twice), [.parameterDuplicate])
        let singles = "/// Moves it.\n///\n/// - Parameter from: Where it was.\n/// - Parameter from: Again.\n/// - Parameter to: Where it goes.\nfunc move(from: Int, to: Int) {}"
        XCTAssertEqual(lint(singles), [.parameterDuplicate])
        let labels = "/// Moves it.\n///\n/// - Parameters:\n///   - origin: Where it was.\n///   - to: Where it goes.\nfunc move(from origin: Int, to: Int) {}"
        XCTAssertEqual(lint(labels), [], "An internal name or a label both name the parameter, in place.")
    }

    func testAssociatedTypesAreTypes() {
        XCTAssertEqual(lint("/// A store.\nprotocol Store {\n    associatedtype Item\n}"), [.missingDoc])
        XCTAssertEqual(lint("/// A store.\nprotocol Store {\n    /// What it holds.\n    associatedtype Item\n}"), [])
    }

    func testFencedCodeIsNeitherProseNorMarkup() {
        let source = """
        /// Parses a name.
        ///
        /// - Parameter text: The raw name.
        ///
        /// Call it like this, where `Cart.total` is only code:
        ///
        /// ```swift
        /// let name = parse(Cart.total)
        ///
        /// - Note: not a callout
        /// ```
        func parse(_ text: String) {}
        """
        XCTAssertEqual(lint(source), [.symbolLink], "Only the backticked path in prose is a link; the fence is code.")
    }

    func testDeadLinksNameSomethingTheSourcesDeclare() {
        let cart = ("Sources/Shop/Cart.swift", """
        /// A cart.
        struct Cart {
            /// The sum of its lines.
            var total: Int
            /// Whether the cart is kept for later.
            var `default`: Bool
            /// Adds a line; ``total`` grows by it.
            ///
            /// - Parameter line: The amount.
            func add(_ line: Int) {}
        }
        """)
        func rules(_ report: String) -> [Rule] {
            Linter.check(sources: [cart, ("Sources/Shop/Report.swift", report)]).map(\.rule)
        }
        XCTAssertEqual(rules("/// Reads ``Cart/total``, ``Cart/add(_:)``, ``Shop/Cart``, ``String``, and ``Swift/Array``.\nstruct Report {}"), [])
        XCTAssertEqual(rules("/// Reads ``Cart/count``.\nstruct Report {}"), [.deadLink])
        XCTAssertEqual(rules("/// Reads ``Cart/default``.\nstruct Report {}"), [], "A keyword-named member is linked without backticks.")
        XCTAssertEqual(rules("/// Reads ``Cart/hashValue``, which a conformance supplies.\nstruct Report {}"), [])
        XCTAssertEqual(rules("/// Calls ``Cart/add(_:)-7tndx`` and reads ``Cart/total-swift.property``.\nstruct Report {}"), [],
                       "DocC's disambiguation suffixes tell overloads apart; they are not part of the name.")
        XCTAssertEqual(rules("/// Calls ``Cart/add(to:)``.\nstruct Report {}"), [.deadLink], "A link with labels must match them.")
        XCTAssertEqual(rules("/// Reads ``Ledger``.\n///\n/// ```\n/// ``Nowhere``\n/// ```\nstruct Report {}"), [.deadLink], "Code in a fence is not a link.")
    }

    func testAScriptsTopLevelVariablesAreItsLocals() {
        XCTAssertEqual(lint("let name = \"x\"\nprint(name)"), [], "A script's variables belong to its top-level code.")
        XCTAssertEqual(lint("let name = \"x\""), [.missingDoc], "Without statements, a global is a declaration.")
        XCTAssertEqual(lint("print(1)\n/// Holds things.\nstruct S { var count: Int }"), [.missingDoc], "Only top-level variables join the code.")
    }

    func testWellKnownPropertiesAndCodingKeysNeedNoDoc() {
        let source = """
        /// A screen.
        struct Screen: View, Identifiable, CustomStringConvertible {
            var id: Int
            var body: some View { EmptyView() }
            var description: String { "screen" }
            enum CodingKeys: String, CodingKey {
                case id
            }
        }
        """
        XCTAssertEqual(lint(source), [.missingDoc], "Only the CodingKeys enum itself, a type, needs a doc.")
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
        let plain = "/// A pair.\nstruct S {\n    /// One side.\n    var a: Int\n    /// The other side.\n    var b: Int\n    init(a: Int, into b: Int) { self.a = a; self.b = b }\n}"
        XCTAssertEqual(lint(plain), [])
        let summarized = "/// A pair.\nstruct S {\n    /// One side.\n    var a: Int\n    /// Builds a pair.\n    init(a: Int) { self.a = a }\n}"
        XCTAssertEqual(lint(summarized), [])
        let computed = "/// A pair.\nstruct S {\n    /// One side.\n    var a: Int\n    init(a: Int) { self.a = a + 1 }\n}"
        XCTAssertEqual(lint(computed), [.missingDoc])
        let extra = "/// A pair.\nstruct S {\n    /// One side.\n    var a: Int\n    init(a: Int) { self.a = a; validate() }\n}"
        XCTAssertEqual(lint(extra), [.missingDoc])
        XCTAssertEqual(lint("/// A pair.\nstruct S {\n    init() {}\n}"), [.missingDoc])
    }
}

extension RulesTests {
    func testSymbolLinks() {
        XCTAssertEqual(lint("/// Pairs with `advance(_:)` later.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Reads `Session.current` first.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Reads `Cache.load(from:)` first.\nfunc f() {}"), [.symbolLink])
        XCTAssertEqual(lint("/// Pairs with ``advance(_:)`` later.\nfunc f() {}"), [])
        XCTAssertEqual(lint("/// Reads ``Session/current`` first.\nfunc f() {}"), [])
        XCTAssertEqual(lint("/// Uses `nil`, `.strict`, `Date()`, `NotificationCenter.default`, and `\"a.b\"`.\nfunc f() {}"), [])
        XCTAssertEqual(SymbolReference.linkForm("Cache.load(from:)"), "Cache/load(from:)")
        XCTAssertEqual(lint("/// See `OrderStore.swift` and `plan.json.gz`.\nfunc f() {}"), [])
        XCTAssertEqual(lint("/// Uses `throws(E)` and `private(set)`.\nfunc f() {}"), [])
    }

    func testReferenceShapesAreMatchedExactly() {
        let references = ["advance(_:)", "_reset()", "Cache.load(from:)", "A.B.make(x:y:)", "Session.current", "Outer.Inner.value_2"]
        for span in references { XCTAssertTrue(SymbolReference.isReference(span), span) }
        let others = ["Date()", "load(from: x)", "Cache.Load", "cache.load", "Session..current", "Session.", ".current",
                      "advance(_:", "a.b(c:)", "Café.menu", "Cache.load(from:)x", "nil", ""]
        for span in others { XCTAssertFalse(SymbolReference.isReference(span), span) }
    }
}
