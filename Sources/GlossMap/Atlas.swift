import GlossCore

/// The interface arranged for reading: nodes, the contracts each one shows, and lookups between them.
///
/// Every front end reads the same arrangement, so the page and the app never decide differently which
/// types are a module's entry points, how nested types fold into their roots, or what a map level draws.
public struct Atlas: Sendable {
    /// A contract with the linter's assessment of it. The model and the lint meet here, in the view,
    /// and nowhere earlier; a contract's own fields read through as the reviewed value's.
    @dynamicMemberLookup
    public struct Reviewed: Sendable {
        /// The declaration as read: its signature and its doc comment, before any rule judges it.
        public var contract: Contract
        /// The linter's verdict on the same declaration: whether it owes a doc, why it is excused, and
        /// what the rules found.
        public var assessment: Assessment

        /// Reads a contract field through the reviewed value, so view code reads both halves alike.
        ///
        /// - Parameter path: A field of the contract.
        /// - Returns: The contract's value for it.
        public subscript<Value>(dynamicMember path: KeyPath<Contract, Value>) -> Value { contract[keyPath: path] }
        /// The rule findings on the declaration, in source order; empty when its doc passes.
        public var findings: [Assessment.Finding] { assessment.findings }
        /// `true` when the harness demands a doc comment here, so a missing one shows as a gap.
        public var requiresDoc: Bool { assessment.requiresDoc }
        /// Why the harness excuses the declaration, in words a reader can act on, or `nil` when it does not.
        public var exemption: String? { assessment.exemption }
    }

    /// The contracts one node shows: the type's own declaration, if scanned, and its members.
    public struct Group: Sendable {
        /// The type's own declaration, or `nil` for an extension of a type no scanned source declares
        /// and for file scope.
        public var head: Reviewed?
        /// The declarations filed under the node, members added in extensions included, in scan order;
        /// a nested type heads a group of its own.
        public var members: [Reviewed] = []
        /// The findings on the head and members together; types nested in the node are left out, as
        /// ``Atlas/findings(under:)`` counts them.
        public var findingCount: Int { (head?.findings.count ?? 0) + members.reduce(0) { $0 + $1.findings.count } }
    }

    /// An edge between two root nodes, with nested types folded into their roots.
    public struct Rolled: Sendable {
        /// The id of the dependent root node.
        public var from: String
        /// The id of the root node it depends on, never the same as ``from``.
        public var to: String
        /// The roles of every edge folded into it, each once, in ``GlossCore/Mention/Role`` order; never
        /// empty, and only `body` means implementation.
        public var roles: [Mention.Role]
    }

    /// Every node of the graph, in the order the interface first declares them.
    public private(set) var nodes: [Graph.Node]
    /// Every dependency between nodes, nested types not yet folded into their roots.
    public private(set) var edges: [Graph.Edge]
    /// The contracts each node shows, keyed by node id; ``group(_:)`` reads it with an empty fallback.
    public private(set) var groups: [String: Group] = [:]
    /// Each node by its id.
    public private(set) var byID: [String: Graph.Node] = [:]
    /// The module names in order of first appearance.
    public private(set) var modules: [String] = []
    /// The ids of the nodes that are no type's nested type, which the map draws as boxes.
    public private(set) var rootIDs: [String] = []
    /// Each module's color, as a slot below ``moduleColorCount`` that every front end maps to its own
    /// palette; see ``colorSlots(for:)``.
    public private(set) var moduleColors: [String: Int] = [:]
    // Indexes built once, so an interface of thousands of types never rescans every edge per type.
    private var edgesFrom: [String: [Graph.Edge]] = [:]
    private var edgesTo: [String: [Graph.Edge]] = [:]
    private var children: [String: [Graph.Node]] = [:]
    private var findingsUnder: [String: Int] = [:]
    private var directories: [String: [String]] = [:]
    private var rolledWithBody: [Rolled] = []
    private var rolledSignature: [Rolled] = []

    /// Indexes the interface by node.
    ///
    /// - Parameter interface: The interface to arrange.
    public init(_ interface: Interface) {
        nodes = interface.graph.nodes
        edges = interface.graph.edges
        var seenModules = Set<String>()
        for node in nodes {
            byID[node.id] = node
            if seenModules.insert(node.module).inserted { modules.append(node.module) }
            if node.root == node.id { rootIDs.append(node.id) }
        }
        for (contract, assessment) in zip(interface.contracts, interface.assessments) {
            let id = Graph.id(contract.module, Graph.key(of: contract))
            let reviewed = Reviewed(contract: contract, assessment: assessment)
            if contract.opensScope {
                groups[id, default: Group()].head = reviewed
            } else {
                groups[id, default: Group()].members.append(reviewed)
            }
        }
        for edge in edges {
            edgesFrom[edge.from, default: []].append(edge)
            edgesTo[edge.to, default: []].append(edge)
        }
        for node in nodes {
            findingsUnder[node.root, default: 0] += groups[node.id]?.findingCount ?? 0
            guard node.root != node.id, let dot = node.name.lastIndex(of: ".") else { continue }
            let parent = Graph.id(node.module, String(node.name[..<dot]))
            if byID[parent] != nil { children[parent, default: []].append(node) }
        }
        for node in nodes {
            guard let file = groups[node.id]?.head?.file ?? groups[node.id]?.members.first?.file else { continue }
            let parts = file.split(separator: "/").map(String.init)
            if let index = parts.lastIndex(of: node.module), index + 2 < parts.count {
                directories[node.id] = Array(parts[(index + 1)..<(parts.count - 1)])
            }
        }
        rolledWithBody = Self.roll(edges, byID: byID, includeBody: true)
        rolledSignature = Self.roll(edges, byID: byID, includeBody: false)
        moduleColors = Self.colorSlots(for: modules)
    }

    /// How many module colors every front end defines.
    public static let moduleColorCount = ModulePalette.colors.count

    /// Gives each module a color slot from a hash of its name, so a module keeps its color across runs,
    /// edits, and front ends with nothing stored. Two modules that hash to one slot are told apart: in
    /// name order, the later takes the next free slot, so a module's color only changes when a new
    /// module collides with it.
    ///
    /// - Parameter modules: The module names.
    /// - Returns: Each module's slot, from 0 to ``moduleColorCount`` minus 1; distinct while there are no
    ///   more modules than slots.
    public static func colorSlots(for modules: [String]) -> [String: Int] {
        var slots: [String: Int] = [:]
        var taken = Set<Int>()
        for module in modules.sorted() {
            // FNV-1a over the name's bytes: stable across runs and platforms, unlike `hashValue`.
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in module.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
            var slot = Int(hash % UInt64(moduleColorCount))
            if taken.count < moduleColorCount {
                while taken.contains(slot) { slot = (slot + 1) % moduleColorCount }
            }
            taken.insert(slot)
            slots[module] = slot
        }
        return slots
    }

    /// The access level a view opens on, as ``GlossCore/Contract/rank(_:)``: internal, so every
    /// module's own types show, an app's included, whose types are never public.
    public static let defaultMinimumRank = 1

    /// The contracts a node shows.
    ///
    /// - Parameter id: A node id.
    /// - Returns: Its group, or an empty one for an unknown id.
    public func group(_ id: String) -> Group {
        groups[id] ?? Group()
    }

    /// The root nodes, in graph order: the types the map draws.
    public var roots: [Graph.Node] {
        rootIDs.compactMap { byID[$0] }
    }

    /// The folder a type lives in, as the map's folder level groups it: the first directory under the
    /// module's own.
    ///
    /// - Parameter node: A node; its declaration's file decides, or its first member's.
    /// - Returns: The folder name, or empty for a file directly in the module's directory.
    public func folder(of node: Graph.Node) -> String {
        directories[node.id]?.first ?? ""
    }

    /// Every directory between a node's module and its file, outermost first.
    ///
    /// - Parameter node: A node; its declaration's file decides, or its first member's.
    /// - Returns: The directory names, or empty for a file directly in the module's directory.
    public func directories(of node: Graph.Node) -> [String] {
        directories[node.id] ?? []
    }

    /// How deep a node sits under its root type, for indenting a list.
    ///
    /// - Parameter node: A node.
    /// - Returns: 0 for a root, one more per enclosing type.
    public func depth(_ node: Graph.Node) -> Int {
        node.root == node.id ? 0 : node.name.split(separator: ".").count - 1
    }

    /// The node's full name as a reader says it.
    ///
    /// - Parameter node: A node.
    /// - Returns: The qualified name, `extension Name`, or `Module top level`.
    public func label(_ node: Graph.Node) -> String {
        switch node.keyword {
        case "file": "\(node.module) top level"
        case "extension": "extension \(node.name)"
        default: node.name
        }
    }

    /// The node's name as a list shows it under its parent: the last path component.
    ///
    /// - Parameter node: A node.
    /// - Returns: The label, shortened for nested types.
    public func shortLabel(_ node: Graph.Node) -> String {
        if node.keyword == "file" { return "top level" }
        return depth(node) > 0 ? String(node.name.split(separator: ".").last ?? "") : label(node)
    }

    /// The widest access among a node and its members, which decides whether an access filter shows it.
    ///
    /// - Parameter node: A node.
    /// - Returns: A rank from ``GlossCore/Contract/rank(_:)``; file scope counts as public, since it is
    ///   an entry point.
    public func rank(of node: Graph.Node) -> Int {
        if node.keyword == "file" { return 3 }
        let group = group(node.id)
        let contracts = [group.head].compactMap { $0 } + group.members
        return contracts.map { Contract.rank($0.access) }.max() ?? Contract.rank(node.access)
    }

    /// Whether one node is nested, at any depth, inside another.
    ///
    /// - Parameters:
    ///   - inner: The candidate nested node.
    ///   - outer: The candidate enclosing node.
    /// - Returns: `true` when both share a module and `inner`'s name extends `outer`'s with a dot.
    public func isNested(_ inner: Graph.Node, in outer: Graph.Node) -> Bool {
        inner.module == outer.module && !outer.name.isEmpty && inner.name.hasPrefix(outer.name + ".")
    }

    /// A node's place in the graph: edges in from other nodes, edges out to other nodes, and the types
    /// nested directly in it. Edges to or from its own nested types are left out of both lists.
    ///
    /// - Parameter node: The node.
    /// - Returns: Incoming edges with signature edges first, outgoing edges, and direct children.
    public func neighbors(of node: Graph.Node) -> (incoming: [Graph.Edge], outgoing: [Graph.Edge], nested: [Graph.Node]) {
        let incoming = (edgesTo[node.id] ?? []).filter { edge in
            guard let from = byID[edge.from] else { return false }
            return !isNested(from, in: node)
        }.enumerated().sorted { ($0.element.roles == [.body] ? 1 : 0, $0.offset) < ($1.element.roles == [.body] ? 1 : 0, $1.offset) }.map(\.element)
        let outgoing = (edgesFrom[node.id] ?? []).filter { edge in
            guard let to = byID[edge.to] else { return false }
            return !isNested(to, in: node)
        }
        return (incoming, outgoing, children[node.id] ?? [])
    }

    /// Why one node depends on another, in the words of the declarations the dependency runs through.
    ///
    /// - Parameters:
    ///   - from: The id of the dependent node.
    ///   - to: The id of the node it depends on.
    /// - Returns: One reason per declaration of `from` that mentions `to`: those in its signature first,
    ///   then those that use it only inside a body, each in scan order; empty when there is no such edge.
    ///
    /// A declaration whose own doc says nothing about the type, such as a view's `body` or a private
    /// property, gets docs forwarded from `to` instead: the summaries of the members its body reaches,
    /// or, when it reaches none that have one, the type's own summary.
    public func reasons(from: String, to: String) -> [Reason] {
        let group = group(from)
        let reasons = ([group.head].compactMap { $0 } + group.members).compactMap { $0.contract.reason(toward: to) }
        let target = self.group(to)
        let forwarded = reasons.map { reason -> Reason in
            guard reason.isUnexplained else { return reason }
            var reason = reason
            var named = Set<String>()
            for name in reason.members {
                for member in target.members where member.name == name {
                    guard let summary = member.summary, named.insert(member.contract.callName).inserted else { continue }
                    reason.forwarded.append(Reason.Forward(name: member.contract.callName, summary: summary))
                }
            }
            if reason.forwarded.isEmpty, let summary = target.head?.summary, let node = byID[to] {
                reason.forwarded = [Reason.Forward(name: label(node), summary: summary)]
            }
            return reason
        }
        return forwarded.filter { $0.roles != [.body] } + forwarded.filter { $0.roles == [.body] }
    }

    /// The finding count of a node together with every type nested in it.
    ///
    /// - Parameter root: A root node id.
    /// - Returns: The total.
    public func findings(under root: String) -> Int {
        findingsUnder[root] ?? 0
    }

    /// Edges between root nodes, nested types folded into their roots.
    ///
    /// - Parameter includeBody: `false` drops the `body` role, and with it every edge made only of it.
    /// - Returns: One edge per ordered pair of roots, in order of first appearance.
    public func rolled(includeBody: Bool) -> [Rolled] {
        includeBody ? rolledWithBody : rolledSignature
    }

    private static func roll(_ edges: [Graph.Edge], byID: [String: Graph.Node], includeBody: Bool) -> [Rolled] {
        var result: [Rolled] = []
        var index: [String: Int] = [:]
        for edge in edges {
            guard let from = byID[edge.from]?.root, let to = byID[edge.to]?.root, from != to else { continue }
            let roles = edge.roles.filter { includeBody || $0 != .body }
            guard !roles.isEmpty else { continue }
            let key = from + "\u{0}" + to
            if index[key] == nil {
                index[key] = result.count
                result.append(Rolled(from: from, to: to, roles: []))
            }
            guard let at = index[key] else { continue }
            for role in roles where !result[at].roles.contains(role) { result[at].roles.append(role) }
        }
        let order = Mention.Role.allCases
        return result.map { edge in
            var edge = edge
            edge.roles.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            return edge
        }
    }

    /// The entry points of a module: root types used from another module, and root types nothing else
    /// in their own module uses but that do depend on something. A type that touches nothing is
    /// left out, since it is no way in, and so is an extension of another module's type unless
    /// another module uses it, since it adds to a door rather than being one.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Root nodes in graph order.
    public func entryPoints(in module: String) -> [Graph.Node] {
        var users: [String: [Graph.Node]] = [:]
        var dependents = Set<String>()
        for link in rolledWithBody {
            if let from = byID[link.from] { users[link.to, default: []].append(from) }
            dependents.insert(link.from)
        }
        return roots.filter { node in
            guard node.module == module else { return false }
            let incoming = users[node.id] ?? []
            if incoming.contains(where: { $0.module != module }) { return true }
            return node.keyword != "extension" && incoming.isEmpty && dependents.contains(node.id)
        }
    }

    /// The root types that use a node, read across nested types.
    ///
    /// - Parameter root: A root node id.
    /// - Returns: The users in graph order, body dependencies included.
    public func users(of root: String) -> [Graph.Node] {
        rolledWithBody.filter { $0.to == root }.compactMap { byID[$0.from] }
    }

    /// The modules one module depends on and the modules that depend on it.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Both lists in order of first dependency, body dependencies included.
    public func dependencies(ofModule module: String) -> (uses: [String], usedBy: [String]) {
        let moduleOf = { (id: String) in byID[id]?.module ?? "" }
        let uses = rolledWithBody.filter { moduleOf($0.from) == module && moduleOf($0.to) != module }.map { moduleOf($0.to) }
        let usedBy = rolledWithBody.filter { moduleOf($0.to) == module && moduleOf($0.from) != module }.map { moduleOf($0.from) }
        return (Self.orderedUnique(uses), Self.orderedUnique(usedBy))
    }

    /// What a folder's types depend on outside it, and what outside it depends on them: other folders
    /// of the same module, and other modules.
    ///
    /// - Parameters:
    ///   - folder: The folder name; empty for files directly in the module's directory.
    ///   - module: The module the folder belongs to.
    /// - Returns: Both lists as map boxes, in order of first dependency, body dependencies included.
    public func dependencies(ofFolder folder: String, in module: String) -> (uses: [MapScope.Unit], usedBy: [MapScope.Unit]) {
        let ids = Set(types(inFolder: folder, of: module).map(\.id))
        let outside = { (id: String) -> MapScope.Unit? in
            guard let node = byID[id], !ids.contains(id) else { return nil }
            return node.module == module ? .folder(module, self.folder(of: node)) : .module(node.module)
        }
        let uses = rolledWithBody.filter { ids.contains($0.from) }.compactMap { outside($0.to) }
        let usedBy = rolledWithBody.filter { ids.contains($0.to) }.compactMap { outside($0.from) }
        return (Self.orderedUnique(uses), Self.orderedUnique(usedBy))
    }

    /// The root types of one module.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Root nodes in graph order.
    public func types(in module: String) -> [Graph.Node] {
        roots.filter { $0.module == module }
    }

    /// The root types of one folder.
    ///
    /// - Parameters:
    ///   - folder: The folder name; empty for files directly in the module's directory.
    ///   - module: The module the folder belongs to.
    /// - Returns: Root nodes in graph order.
    public func types(inFolder folder: String, of module: String) -> [Graph.Node] {
        roots.filter { $0.module == module && self.folder(of: $0) == folder }
    }

    /// The folders of one module that hold root types.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Folder names in order of first type.
    public func folders(in module: String) -> [String] {
        Self.orderedUnique(types(in: module).map(folder(of:)))
    }

    /// One line sizing a set of root types: how many, how many public, and how many findings.
    ///
    /// - Parameter members: The root types.
    /// - Returns: Plain text such as `12 types · 8 public · 2 findings`.
    public func summary(of members: [Graph.Node]) -> String {
        let publicCount = members.filter { Contract.rank($0.access) >= 3 }.count
        let findings = members.reduce(0) { $0 + self.findings(under: $1.id) }
        var parts = ["\(members.count) type\(members.count == 1 ? "" : "s")", "\(publicCount) public"]
        if findings > 0 { parts.append("\(findings) finding\(findings == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// The elements in their first-seen order, each once.
    ///
    /// - Parameter items: Any sequence of hashable values.
    /// - Returns: The values without repeats.
    static func orderedUnique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}
