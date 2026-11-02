/// How an interface differs from a base it is compared against: the types, declarations, and
/// dependencies added, removed, or changed.
///
/// Things are matched by name, never by place, so code that only moves within or between files is no
/// change. A node is matched by its id; a declaration by its node, keyword, and name as a caller writes
/// it, an overload by its declaration as written first and then in order; a dependency by the nodes at
/// its ends. A renamed type reads as one removed and one added.
public struct InterfaceDiff: Sendable, Equatable {
    /// How something differs from the base.
    public enum Change: String, Sendable, Equatable, Codable {
        /// It is new: the base does not have it.
        case added
        /// It is gone: only the base has it.
        case removed
        /// Both have it, and they differ.
        case changed
    }

    /// One declaration that differs from the base.
    public struct DeclarationChange: Sendable, Equatable {
        /// The id of the node the declaration is filed under.
        public var node: String
        /// The declaration's name as a caller writes it, as ``Contract/callName`` gives it.
        public var name: String
        /// The introducing keyword, such as `func` or `var`.
        public var keyword: String
        /// Whether the declaration is new, gone, or changed.
        public var change: Change
        /// For a changed declaration, whether it is written differently: its signature, access, or
        /// attributes.
        public var signatureChanged: Bool
        /// For a changed declaration, whether its doc says something different.
        public var docChanged: Bool
    }

    /// One node that differs from the base: new, gone, or holding declarations that differ.
    public struct NodeChange: Sendable, Equatable {
        /// The node as the interface that has it gives it: the head's, or the base's for a removed one.
        public var node: Graph.Node
        /// Whether the node is new, gone, or changed.
        public var change: Change
        /// The declarations filed under the node that differ, in source order; every one of them for a
        /// new or a gone node.
        public var declarations: [DeclarationChange]
    }

    /// One dependency that differs from the base.
    public struct EdgeChange: Sendable, Equatable {
        /// The id of the dependent node.
        public var from: String
        /// The id of the node it depends on.
        public var to: String
        /// Whether the dependency is new, gone, or changed.
        public var change: Change
        /// Its roles in the base; empty for a new one.
        public var before: [Mention.Role]
        /// Its roles now; empty for a gone one.
        public var after: [Mention.Role]
        /// The declarations, by qualified name, that make the dependency now and did not in the base.
        public var viaAdded: [String]
        /// The declarations, by qualified name, that made the dependency in the base and do not now.
        public var viaRemoved: [String]

        /// `true` when the dependency is now part of the interface and was not: a new one in a
        /// signature, or one that was only inside bodies and now is in a signature.
        public var entersInterface: Bool {
            !after.isEmpty && after != [.body] && (before.isEmpty || before == [.body])
        }

        /// `true` when the dependency was part of the interface and is not now: gone from every
        /// signature, whether or not a body still uses it.
        public var leavesInterface: Bool {
            !before.isEmpty && before != [.body] && (after.isEmpty || after == [.body])
        }
    }

    /// The nodes that differ: the head's in its order, then the removed ones in the base's order.
    public var nodes: [NodeChange]
    /// The dependencies that differ: the head's in its order, then the removed ones in the base's order.
    public var edges: [EdgeChange]

    /// `true` when nothing differs.
    public var isEmpty: Bool {
        nodes.isEmpty && edges.isEmpty
    }

    /// Compares an interface with its base.
    ///
    /// - Parameters:
    ///   - base: The interface compared against, such as the one a branch started from.
    ///   - head: The interface as it is now.
    public init(base: Interface, head: Interface) {
        func grouped(_ interface: Interface) -> [String: [Contract]] {
            Dictionary(grouping: interface.contracts) { Graph.id($0.module, Graph.key(of: $0)) }
        }
        let baseContracts = grouped(base)
        let headContracts = grouped(head)
        let baseNodes = Set(base.graph.nodes.map(\.id))
        let headNodes = Set(head.graph.nodes.map(\.id))

        var nodes: [NodeChange] = []
        for node in head.graph.nodes {
            let declarations = Self.declarations(of: node.id, base: baseContracts[node.id] ?? [], head: headContracts[node.id] ?? [])
            if !baseNodes.contains(node.id) {
                nodes.append(NodeChange(node: node, change: .added, declarations: declarations))
            } else if !declarations.isEmpty {
                nodes.append(NodeChange(node: node, change: .changed, declarations: declarations))
            }
        }
        for node in base.graph.nodes where !headNodes.contains(node.id) {
            nodes.append(NodeChange(node: node, change: .removed,
                                    declarations: Self.declarations(of: node.id, base: baseContracts[node.id] ?? [], head: [])))
        }

        func key(_ edge: Graph.Edge) -> String { edge.from + "\u{0}" + edge.to }
        let baseEdges = Dictionary(base.graph.edges.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let headKeys = Set(head.graph.edges.map(key))
        var edges: [EdgeChange] = []
        for edge in head.graph.edges {
            guard let before = baseEdges[key(edge)] else {
                edges.append(EdgeChange(from: edge.from, to: edge.to, change: .added, before: [], after: edge.roles,
                                        viaAdded: edge.via, viaRemoved: []))
                continue
            }
            let added = edge.via.filter { !before.via.contains($0) }
            let removed = before.via.filter { !edge.via.contains($0) }
            guard before.roles != edge.roles || !added.isEmpty || !removed.isEmpty else { continue }
            edges.append(EdgeChange(from: edge.from, to: edge.to, change: .changed, before: before.roles, after: edge.roles,
                                    viaAdded: added, viaRemoved: removed))
        }
        for edge in base.graph.edges where !headKeys.contains(key(edge)) {
            edges.append(EdgeChange(from: edge.from, to: edge.to, change: .removed, before: edge.roles, after: [],
                                    viaAdded: [], viaRemoved: edge.via))
        }
        self.nodes = nodes
        self.edges = edges
    }

    /// How a node differs from the base.
    ///
    /// - Parameter id: A node id from either interface.
    /// - Returns: The change, or `nil` when the node is the same in both.
    public func change(ofNode id: String) -> NodeChange? {
        nodes.first { $0.node.id == id }
    }

    /// How a dependency differs from the base.
    ///
    /// - Parameters:
    ///   - from: The id of the dependent node.
    ///   - to: The id of the node it depends on.
    /// - Returns: The change, or `nil` when the dependency is the same in both or in neither.
    public func change(from: String, to: String) -> EdgeChange? {
        edges.first { $0.from == from && $0.to == to }
    }

    /// The declarations of one node that differ, matched by keyword and name as a caller writes it:
    /// among those alike, the ones written the same pair first, then the rest in order.
    ///
    /// - Parameters:
    ///   - node: The node's id.
    ///   - base: The node's contracts in the base, in source order.
    ///   - head: The node's contracts now, in source order.
    /// - Returns: The head's changed and added declarations in its order, then the removed ones.
    private static func declarations(of node: String, base: [Contract], head: [Contract]) -> [DeclarationChange] {
        func key(_ contract: Contract) -> String { contract.keyword + " " + contract.callName }
        var unmatched = Dictionary(grouping: base.indices, by: { key(base[$0]) })
        var partner: [Int: Int] = [:]
        // Declarations written the same pair first, so an edit to one overload does not shift the rest.
        for (index, contract) in head.enumerated() {
            guard let same = unmatched[key(contract)]?.firstIndex(where: { base[$0].declaration == contract.declaration }) else { continue }
            partner[index] = unmatched[key(contract)]?.remove(at: same)
        }
        for (index, contract) in head.enumerated() where partner[index] == nil {
            guard let next = unmatched[key(contract)], !next.isEmpty else { continue }
            partner[index] = unmatched[key(contract)]?.removeFirst()
        }

        var changes: [DeclarationChange] = []
        for (index, contract) in head.enumerated() {
            guard let match = partner[index] else {
                changes.append(DeclarationChange(node: node, name: contract.callName, keyword: contract.keyword, change: .added,
                                                 signatureChanged: false, docChanged: false))
                continue
            }
            let signature = base[match].declaration != contract.declaration
            let doc = Self.doc(of: base[match]) != Self.doc(of: contract)
            guard signature || doc else { continue }
            changes.append(DeclarationChange(node: node, name: contract.callName, keyword: contract.keyword, change: .changed,
                                             signatureChanged: signature, docChanged: doc))
        }
        let removed = unmatched.values.flatMap { $0 }.sorted()
        for index in removed {
            changes.append(DeclarationChange(node: node, name: base[index].callName, keyword: base[index].keyword, change: .removed,
                                             signatureChanged: false, docChanged: false))
        }
        return changes
    }

    /// What a contract's doc says, as one value to compare: its summary, its entries, its callouts, and
    /// its notes.
    ///
    /// - Parameter contract: A contract.
    /// - Returns: The doc's parts, each on a line of its own.
    private static func doc(of contract: Contract) -> [String] {
        [contract.summary ?? "", contract.returns ?? "", contract.throwsDoc ?? ""]
            + contract.parameters.map { $0.name + ": " + ($0.doc ?? "") }
            + contract.callouts.map { $0.keyword + ": " + $0.text }
            + contract.notes
    }
}
