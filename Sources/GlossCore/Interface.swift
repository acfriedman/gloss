/// Every declaration found under a set of paths: what each one promises, what the linter concluded
/// about it, and how the types depend on one another. The interface as one document.
///
/// The model and the lint are built separately from one reading and only meet here, side by side.
/// The JSON form is the stable surface for other tools; ``InterfacePage`` renders the same value.
public struct Interface: Sendable, Equatable, Codable {
    /// The version of this JSON shape. It changes only when a field is removed or changes meaning.
    ///
    /// Version 2 moved `requiresDoc`, `exemption`, and `findings` out of each contract into `assessments`.
    public var schema = 2
    /// The scanned paths, in the order they were read and as they are reported.
    public var files: [String]
    /// One contract per declaration, in file order and then source order.
    public var contracts: [Contract]
    /// One assessment per contract, at the same index.
    public var assessments: [Assessment]
    /// The dependency graph drawn from the contracts' mentions.
    public var graph: Graph

    /// Reads every source once, then builds the contracts and the assessments from that reading.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents.
    /// - Returns: The interface in file order, then source order, with each contract's module named
    ///   from its path and its mentions resolved.
    public static func build(sources: [(file: String, source: String)]) -> Interface {
        let phase = Timing.begin("build interface"); defer { Timing.end(phase, "\(sources.count) files") }
        // Each file is read, and its declarations made into contracts and linted, on its own, so the
        // files are spread over every core; the results keep the files' order.
        let readings = Timing.measure("parse", "\(sources.count) files") {
            concurrentMap(sources) { (file: $0.file, entries: DeclarationReader.read(source: $0.source, file: $0.file)) }
        }
        let index = Timing.measure("index symbols") { SymbolIndex(readings) }
        let made = Timing.measure("contracts and lint") {
            concurrentMap(readings) { reading -> (contracts: [Contract], assessments: [Assessment]) in
                let module = Self.module(of: reading.file)
                let contracts = reading.entries.map { entry -> Contract in
                    var contract = Contract.make(entry)
                    contract.module = module
                    return contract
                }
                return (contracts, reading.entries.map { Linter.assess($0, index: index) })
            }
        }
        var contracts = made.flatMap(\.contracts)
        let graph = Timing.measure("graph", "\(contracts.count) declarations") { Graph.build(&contracts) }
        return Interface(files: sources.map(\.file), contracts: contracts, assessments: made.flatMap(\.assessments), graph: graph)
    }

    /// Names the module a file belongs to by the SwiftPM layout: the directory right under `Sources`
    /// or `Tests`. Outside that layout the file's own directory stands in, which is right for most
    /// Xcode projects and harmless for the rest.
    ///
    /// - Parameter file: The path as given.
    /// - Returns: The module name, or `Module` for a bare file name.
    public static func module(of file: String) -> String {
        let parts = file.split(separator: "/").map(String.init)
        if let root = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }), root + 2 < parts.count {
            return parts[root + 1]
        }
        return parts.count >= 2 ? parts[parts.count - 2] : "Module"
    }
}
