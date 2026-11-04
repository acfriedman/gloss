import GlossRead

/// How the scanned types depend on one another, drawn from the type names each declaration mentions.
///
/// A node is a type with its members, an extension of a type no scanned source declares, or a module's
/// file-scope declarations. An edge says the source mentions the target, and its roles say where.
public struct Graph: Sendable, Equatable, Codable {
    /// One node: the same unit the page shows as one view.
    public struct Node: Sendable, Equatable, Codable {
        /// `Module/Qualified.Name`, or `Module/` for file scope.
        public var id: String
        /// The module whose declarations the node gathers.
        public var module: String
        /// The qualified type name, the extended type's name, or empty for file scope.
        public var name: String
        /// `struct`, `class`, `enum`, `actor`, or `protocol`; `extension` for a type declared elsewhere;
        /// `file` for file scope.
        public var keyword: String
        /// The type's own access, or the widest access among the members of an extension or file scope.
        public var access: String
        /// The outermost enclosing node, which the module map folds nested types into.
        public var root: String
    }

    /// One dependency, with every role it is made of and the declarations that make it.
    public struct Edge: Sendable, Equatable, Codable {
        /// The id of the node whose declarations mention the target.
        public var from: String
        /// The id of the mentioned node, never the same as ``Graph/Edge/from``.
        public var to: String
        /// The roles in ``Mention/Role`` order; an edge made only of `body` is implementation.
        public var roles: [Mention.Role]
        /// The qualified names of the declarations whose mentions make this edge.
        public var via: [String]
    }

    /// Every node, in order of first appearance across the contracts.
    public var nodes: [Node]
    /// Every dependency, one per ordered pair of nodes, in order of first mention.
    public var edges: [Edge]

    /// The node id for a group key in a module.
    ///
    /// - Parameters:
    ///   - module: The module name.
    ///   - key: The group key from ``key(of:)``.
    /// - Returns: `Module/Key`.
    public static func id(_ module: String, _ key: String) -> String {
        module + "/" + key
    }

    /// The group a contract belongs to: a type is its own group, and anything else joins its container.
    ///
    /// - Parameter contract: Any contract.
    /// - Returns: A qualified type name, an extended type's name, or empty for file scope.
    public static func key(of contract: Contract) -> String {
        contract.opensScope ? contract.qualifiedName : contract.container.joined(separator: ".")
    }

    /// Builds the nodes and edges, and records on each mention the node it resolves to. Resolution
    /// follows Swift's lookup: the innermost enclosing type first, then outward, then other modules.
    ///
    /// - Parameter contracts: Every contract, with modules set; their mentions are resolved in place.
    /// - Returns: Nodes in order of first appearance and edges in order of first mention.
    static func build(_ contracts: inout [Contract]) -> Graph {
        var declared: [String: Set<String>] = [:]
        for contract in contracts where contract.opensScope {
            declared[contract.module, default: []].insert(contract.qualifiedName)
        }

        var nodes: [Node] = []
        var position: [String: Int] = [:]
        for contract in contracts {
            let key = Self.key(of: contract)
            let id = Self.id(contract.module, key)
            if position[id] == nil {
                let isType = declared[contract.module]?.contains(key) == true
                let root = key.split(separator: ".").first.map(String.init) ?? ""
                position[id] = nodes.count
                nodes.append(Node(id: id, module: contract.module, name: key,
                                  keyword: key.isEmpty ? "file" : isType ? "" : "extension",
                                  access: "private",
                                  root: isType ? Self.id(contract.module, root) : id))
            }
            guard let index = position[id] else { continue }
            if contract.opensScope {
                nodes[index].keyword = contract.keyword
                nodes[index].access = contract.access
            } else if nodes[index].keyword == "extension" || nodes[index].keyword == "file",
                      Contract.rank(contract.access) > Contract.rank(nodes[index].access) {
                nodes[index].access = contract.access
            }
        }

        func resolve(_ raw: String, module: String, scope: [String]) -> String? {
            var name = raw
            while true {
                for depth in stride(from: scope.count, through: 0, by: -1) {
                    let candidate = (scope.prefix(depth) + [name]).joined(separator: ".")
                    if declared[module]?.contains(candidate) == true { return Self.id(module, candidate) }
                }
                for (other, names) in declared.sorted(by: { $0.key < $1.key }) where other != module && names.contains(name) {
                    return Self.id(other, name)
                }
                guard let dot = name.lastIndex(of: ".") else { return nil }
                name = String(name[..<dot])
            }
        }

        // A body that reaches a type through a variable, as in `workspace.select(…)`, depends on the type
        // the variable's declaration names: a parameter's, else a property's of the same type, when exactly
        // one name it mentions is a scanned type.
        var held: [String: [String: [String]]] = [:]
        for contract in contracts where ["var", "let"].contains(contract.keyword) {
            let owner = Self.id(contract.module, Self.key(of: contract))
            held[owner, default: [:]][contract.name] = contract.mentions.filter { $0.role == .property }.map(\.name)
        }
        for index in contracts.indices {
            let contract = contracts[index]
            let owner = Self.id(contract.module, Self.key(of: contract))
            let scope = contract.opensScope ? contract.container + [contract.name] : contract.container
            for mention in contract.mentions.indices {
                guard let variable = contract.mentions[mention].variable else { continue }
                let taken = contract.mentions.filter { $0.role == .parameter && $0.parameters.contains(variable) }.map(\.name)
                let named = taken.isEmpty ? held[owner]?[variable] ?? [] : taken
                let types = Set(named.filter { resolve($0, module: contract.module, scope: scope) != nil })
                if types.count == 1, let type = types.first { contracts[index].mentions[mention].name = type }
            }
        }

        var edges: [Edge] = []
        var edgeIndex: [String: Int] = [:]
        for index in contracts.indices {
            let contract = contracts[index]
            let owner = Self.id(contract.module, Self.key(of: contract))
            let scope = contract.opensScope ? contract.container + [contract.name] : contract.container
            for mention in contract.mentions.indices {
                guard let target = resolve(contract.mentions[mention].name, module: contract.module, scope: scope) else { continue }
                contracts[index].mentions[mention].resolved = target
                guard target != owner else { continue }
                let key = owner + "\u{0}" + target
                if edgeIndex[key] == nil {
                    edgeIndex[key] = edges.count
                    edges.append(Edge(from: owner, to: target, roles: [], via: []))
                }
                guard let edge = edgeIndex[key] else { continue }
                let role = contract.mentions[mention].role
                if !edges[edge].roles.contains(role) { edges[edge].roles.append(role) }
                if !edges[edge].via.contains(contract.qualifiedName) { edges[edge].via.append(contract.qualifiedName) }
            }
        }
        let order = Mention.Role.allCases
        for edge in edges.indices {
            edges[edge].roles.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        }
        return Graph(nodes: nodes, edges: edges)
    }
}
