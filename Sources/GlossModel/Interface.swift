import GlossRead

/// Every declaration found under a set of paths: what each one promises, and how the types depend on
/// one another. The interface as one document.
///
/// It is built from a ``GlossRead/Reading`` and holds only what the docs say, never whether they follow
/// the house style; that is the lint's, which reads the same ``GlossRead/Reading`` on its own.
public struct Interface: Sendable, Equatable, Codable {
    /// The scanned paths, in the order they were read and as they are reported.
    public var files: [String]
    /// One contract per declaration, in file order and then source order.
    public var contracts: [Contract]
    /// The dependency graph drawn from the contracts' mentions.
    public var graph: Graph

    /// Reads every source once, then builds the contracts from that reading.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents.
    /// - Returns: The interface in file order, then source order, with each contract's module named
    ///   from its path and its mentions resolved.
    public static func build(sources: [(file: String, source: String)]) -> Interface {
        build(Reading(sources: sources))
    }

    /// Builds the contracts and their graph from sources already read.
    ///
    /// - Parameter reading: The sources, read once.
    /// - Returns: The interface in file order, then source order, with each contract's module named
    ///   from its path and its mentions resolved.
    public static func build(_ reading: Reading) -> Interface {
        let phase = Timing.begin("build interface"); defer { Timing.end(phase, "\(reading.files.count) files") }
        // Each file's declarations are made into contracts on their own, so the files are spread over
        // every core; the results keep the files' order.
        let made = Timing.measure("contracts") {
            concurrentMap(reading.files) { file -> [Contract] in
                let module = SourceFiles.module(of: file.file)
                return file.entries.map { entry -> Contract in
                    var contract = Contract.make(entry)
                    contract.module = module
                    return contract
                }
            }
        }
        var contracts = made.flatMap { $0 }
        let graph = Timing.measure("graph", "\(contracts.count) declarations") { Graph.build(&contracts) }
        return Interface(files: reading.files.map(\.file), contracts: contracts, graph: graph)
    }
}
