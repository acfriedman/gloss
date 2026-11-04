/// Every source read once: each file's declarations with their doc comments, and an index of what they
/// declare, so a link in one file can be checked against all of them.
///
/// The lint and the contract model are both built from one reading, and neither knows the other.
public struct Reading: Sendable {
    /// Each file's path, as it is reported, and the declarations read from it, in the order given.
    public var files: [(file: String, entries: [DeclarationReader.Entry])]
    /// The symbols every file declares, which a doc comment's links are resolved against.
    public var index: SymbolIndex

    /// Reads every source, spreading the files over every core, then indexes what they declare.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents.
    public init(sources: [(file: String, source: String)]) {
        let files = Timing.measure("parse", "\(sources.count) files") {
            concurrentMap(sources) { (file: $0.file, entries: DeclarationReader.read(source: $0.source, file: $0.file)) }
        }
        self.files = files
        index = Timing.measure("index symbols") { SymbolIndex(files) }
    }
}
