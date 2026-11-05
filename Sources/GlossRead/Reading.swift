/// Every source read once: each file's declarations with their doc comments, and an index of what they
/// declare, so a link in one file can be checked against all of them.
///
/// The lint and the contract model are both built from one reading, and neither knows the other. An
/// Objective-C header among the sources is not parsed: only the type names it declares are read, so a
/// link to one resolves. A module's page is read as a page, for the lint to check and the app to show.
public struct Reading: Sendable {
    /// Each file's path, as it is reported, and the declarations read from it, in the order given.
    public var files: [(file: String, entries: [DeclarationReader.Entry])]
    /// The symbols every file declares, which a doc comment's links are resolved against.
    public var index: SymbolIndex
    /// The modules any file imports, by their first names, sorted.
    public var imports: [String]
    /// The types the Objective-C headers declare, by the names Swift imports them as, sorted.
    public var objectiveCTypes: [String]
    /// The module pages among the sources, in the order given.
    public var modulePages: [ModulePage]

    /// Reads every source, spreading the files over every core, then indexes what they declare.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents: Swift files,
    ///   any Objective-C headers whose types the Swift docs may link, and the module pages.
    public init(sources: [(file: String, source: String)]) {
        let swift = sources.filter { $0.file.hasSuffix(".swift") }
        let headers = sources.filter { $0.file.hasSuffix(".h") }
        modulePages = sources.filter { ModulePage.isPage($0.file) }.map { ModulePage.parse($0.source, file: $0.file) }
        let read = Timing.measure("parse", "\(swift.count) files") {
            concurrentMap(swift) { (file: $0.file, read: DeclarationReader.readFile(source: $0.source, file: $0.file)) }
        }
        let objectiveCTypes = Timing.measure("read headers", "\(headers.count) files") {
            Set(concurrentMap(headers) { ObjectiveCHeaders.typeNames(in: $0.source) }.flatMap { $0 }).sorted()
        }
        self.objectiveCTypes = objectiveCTypes
        let files = read.map { (file: $0.file, entries: $0.read.entries) }
        let imports = Set(read.flatMap(\.read.imports)).sorted()
        self.files = files
        self.imports = imports
        index = Timing.measure("index symbols") { SymbolIndex(files, imports: imports, objectiveCTypes: objectiveCTypes) }
    }
}
