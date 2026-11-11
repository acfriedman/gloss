import LucidRead

/// How an interface differs from a base it is compared against: the types, declarations, and
/// dependencies added, removed, or changed.
///
/// Things are matched by name, never by place, so code that only moves within or between files is no
/// change. A node is matched by its id; a declaration by its node, keyword, and name as a caller writes
/// it, an overload by its declaration as written first and then in order; a dependency by the nodes at
/// its ends. A type that keeps its name and moves to another module reads as moved, when it is the only
/// type of that name gone from the base and the only one new in the head, a declared type and an
/// extension told apart; a dependency that moved with its ends is then no change. A renamed type reads
/// as one removed and one added.
public struct InterfaceDiff: Sendable, Equatable {
    /// How something differs from the base.
    public enum Change: String, Sendable, Equatable, Codable {
        /// It is new: the base does not have it.
        case added
        /// It is gone: only the base has it.
        case removed
        /// Both have it, and they differ in what they declare: a signature, a doc, or what they hold.
        case changed
        /// Both have it, declared and documented the same, and only what it does inside differs: a body,
        /// an accessor, or an initial value. It changes no one's view of the interface.
        case implementation
        /// It moved to another module under the same name, so callers import it from elsewhere; what it
        /// declares may differ too.
        case moved
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
        /// For a changed declaration, whether what it does differs: its body, accessors, or initial value.
        public var bodyChanged: Bool
        /// The declaration as the base writes it, for a changed or a gone one; `nil` for a new one.
        public var was: String?
        /// The declaration as written now, for a new or a changed one; `nil` for a gone one.
        public var now: String?
        /// The doc's summary in the base, for a changed or a gone one.
        public var wasSummary: String?
        /// The doc's summary now, for a new or a changed one.
        public var nowSummary: String?
        /// Where the declaration is now, its file and lines, for a new or a changed one.
        public var place: Place?
        /// Where the declaration was in the base, for a changed or a gone one.
        public var wasPlace: Place?
    }

    /// Where a declaration is written: its file, as the interface names it, and its lines.
    public struct Place: Sendable, Equatable, Hashable {
        /// The file, as the interface names it.
        public var file: String
        /// The lines, its doc comment's first through its last.
        public var lines: ClosedRange<Int>
    }

    /// One node that differs from the base: new, gone, holding declarations that differ, or holding
    /// declarations whose bodies alone differ.
    public struct NodeChange: Sendable, Equatable {
        /// The node as the interface that has it gives it: the head's, or the base's for a removed one.
        public var node: Graph.Node
        /// Whether the node is new, gone, or changed.
        public var change: Change
        /// The declarations filed under the node that differ, in source order; every one of them for a
        /// new or a gone node, and only those that differ from where it was for a moved one.
        public var declarations: [DeclarationChange]
        /// For a moved node, the node as the base gives it, in the module it moved from; `nil` otherwise.
        public var movedFrom: Graph.Node? = nil
    }

    /// One dependency that differs from the base.
    public struct EdgeChange: Sendable, Equatable {
        /// The id of the dependent node, as the head names it when the node moved.
        public var from: String
        /// The id of the node it depends on, as the head names it when the node moved.
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
    /// Where each node's change is in ``nodes``, by node id.
    private var nodeIndex: [String: Int] = [:]
    /// Where each dependency's change is in ``edges``, by its ends' ids joined.
    private var edgeIndex: [String: Int] = [:]

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
        let phase = Timing.begin("diff")
        func grouped(_ interface: Interface) -> [String: [Contract]] {
            Dictionary(grouping: interface.contracts) { Graph.id($0.module, Graph.key(of: $0)) }
        }
        let baseContracts = grouped(base)
        let headContracts = grouped(head)
        let baseNodes = Set(base.graph.nodes.map(\.id))
        let headNodes = Set(head.graph.nodes.map(\.id))
        // A gone type and a new one are one move when each is the only one of its name on its side, a
        // declared type and an extension of one told apart, so an extension added beside a moved type is
        // still new. File scope has no name to match by.
        func moveKey(_ node: Graph.Node) -> String { node.name + (node.keyword == "extension" ? " extension" : "") }
        let gone = Dictionary(grouping: base.graph.nodes.filter { !headNodes.contains($0.id) && !$0.name.isEmpty }, by: moveKey)
        let new = Dictionary(grouping: head.graph.nodes.filter { !baseNodes.contains($0.id) && !$0.name.isEmpty }, by: moveKey)
        var movedFrom: [String: Graph.Node] = [:]
        for (key, was) in gone where was.count == 1 {
            if let now = new[key], now.count == 1 { movedFrom[now[0].id] = was[0] }
        }
        let movedTo = Dictionary(uniqueKeysWithValues: movedFrom.map { ($0.value.id, $0.key) })

        var nodes: [NodeChange] = []
        for node in head.graph.nodes {
            if let was = movedFrom[node.id] {
                let declarations = Self.declarations(of: node.id, base: baseContracts[was.id] ?? [], head: headContracts[node.id] ?? [])
                nodes.append(NodeChange(node: node, change: .moved, declarations: declarations, movedFrom: was))
                continue
            }
            let declarations = Self.declarations(of: node.id, base: baseContracts[node.id] ?? [], head: headContracts[node.id] ?? [])
            if !baseNodes.contains(node.id) {
                nodes.append(NodeChange(node: node, change: .added, declarations: declarations))
            } else if !declarations.isEmpty {
                let inside = declarations.allSatisfy { $0.change == .implementation }
                nodes.append(NodeChange(node: node, change: inside ? .implementation : .changed, declarations: declarations))
            }
        }
        for node in base.graph.nodes where !headNodes.contains(node.id) && movedTo[node.id] == nil {
            nodes.append(NodeChange(node: node, change: .removed,
                                    declarations: Self.declarations(of: node.id, base: baseContracts[node.id] ?? [], head: [])))
        }

        func key(_ edge: Graph.Edge) -> String { edge.from + "\u{0}" + edge.to }
        // The base's dependencies with each end that moved named as the head names it, so a dependency
        // that moved with its types is no change.
        let baseGraphEdges = base.graph.edges.map { edge -> Graph.Edge in
            var edge = edge
            edge.from = movedTo[edge.from] ?? edge.from
            edge.to = movedTo[edge.to] ?? edge.to
            return edge
        }
        let baseEdges = Dictionary(baseGraphEdges.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
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
        for edge in baseGraphEdges where !headKeys.contains(key(edge)) {
            edges.append(EdgeChange(from: edge.from, to: edge.to, change: .removed, before: edge.roles, after: [],
                                    viaAdded: [], viaRemoved: edge.via))
        }
        Timing.end(phase, "\(nodes.count) types and \(edges.count) dependencies differ")
        self.nodes = nodes
        self.edges = edges
        for (index, change) in nodes.enumerated() {
            if nodeIndex[change.node.id] == nil { nodeIndex[change.node.id] = index }
            // A moved node is found by the id it had in the base too.
            if let was = change.movedFrom, nodeIndex[was.id] == nil { nodeIndex[was.id] = index }
        }
        for (index, change) in edges.enumerated() where edgeIndex[change.from + "\u{0}" + change.to] == nil {
            edgeIndex[change.from + "\u{0}" + change.to] = index
        }
    }

    /// How a node differs from the base.
    ///
    /// - Parameter id: A node id from either interface; a moved node's id in the base finds its move.
    /// - Returns: The change, or `nil` when the node is the same in both.
    public func change(ofNode id: String) -> NodeChange? {
        nodeIndex[id].map { nodes[$0] }
    }

    /// How a dependency differs from the base.
    ///
    /// - Parameters:
    ///   - from: The id of the dependent node.
    ///   - to: The id of the node it depends on.
    /// - Returns: The change, or `nil` when the dependency is the same in both or in neither.
    public func change(from: String, to: String) -> EdgeChange? {
        edgeIndex[from + "\u{0}" + to].map { edges[$0] }
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
                                                 signatureChanged: false, docChanged: false, bodyChanged: false,
                                                 was: nil, now: contract.declaration, wasSummary: nil, nowSummary: contract.summary,
                                                 place: Place(contract), wasPlace: nil))
                continue
            }
            let signature = base[match].declaration != contract.declaration
            let doc = Self.doc(of: base[match]) != Self.doc(of: contract)
            let body = base[match].bodyFingerprint != contract.bodyFingerprint
            guard signature || doc || body else { continue }
            changes.append(DeclarationChange(node: node, name: contract.callName, keyword: contract.keyword,
                                             change: signature || doc ? .changed : .implementation,
                                             signatureChanged: signature, docChanged: doc, bodyChanged: body,
                                             was: base[match].declaration, now: contract.declaration,
                                             wasSummary: base[match].summary, nowSummary: contract.summary,
                                             place: Place(contract), wasPlace: Place(base[match])))
        }
        let removed = unmatched.values.flatMap { $0 }.sorted()
        for index in removed {
            changes.append(DeclarationChange(node: node, name: base[index].callName, keyword: base[index].keyword, change: .removed,
                                             signatureChanged: false, docChanged: false, bodyChanged: false,
                                             was: base[index].declaration, now: nil, wasSummary: base[index].summary, nowSummary: nil,
                                             place: nil, wasPlace: Place(base[index])))
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

extension InterfaceDiff.Place {
    /// Where a contract is written.
    ///
    /// - Parameter contract: A contract.
    init(_ contract: Contract) {
        self.init(file: contract.file, lines: contract.lines)
    }
}
