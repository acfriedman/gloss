import Foundation

/// The data the page renders each type's view from, embedded once as compact JSON.
///
/// Writing every member's contract out as HTML makes a large codebase's page larger than a browser
/// opens comfortably, so the page instead builds a type's view when a reader reaches it. Everything
/// that takes judgment (neighbors, roles, which types a member uses, where a summary's first sentence
/// ends) is decided here, so the page's script only fills templates.
extension InterfacePage {
    /// Every node and contract the type views need, cross-referenced by index.
    struct PageData: Encodable {
        /// One node: a type, an extension of an unscanned type, or a module's file scope.
        struct Node: Encodable {
            /// The graph id, which map boxes and chips carry.
            var id: String
            /// The anchor of the node's view.
            var a: String
            /// The label: qualified name, `extension Name`, or `Module top level`.
            var l: String
            /// The kind word: `struct`, `enum`, `extension`, `file scope`, and so on.
            var k: String
            var m: String
            /// The access level; file scope counts as public, since it is an entry point.
            var x: String
            /// The graph id of the root the map draws this node as.
            var r: String
            /// The root's label, for a nested node.
            var rl: String?
            /// The map levels that draw this node, widest first.
            var sc: [String]?
            /// The index of the type's own contract.
            var h: Int?
            /// The indices of its members' contracts.
            var c: [Int]?
            /// What uses it: `[node, role mask]` pairs, signature edges first.
            var i: [[Int]]?
            /// What it uses: `[node, role mask]` pairs.
            var o: [[Int]]?
            /// The types nested directly in it.
            var n: [Int]?
            /// Its finding count, members included.
            var f: Int?
        }

        /// One parameter of a callable.
        struct Parameter: Encodable {
            var l: String?
            var n: String
            var t: String
            /// `true` when the parameter has a default value.
            var v: Bool?
            var d: String?
        }

        /// One finding of a contract.
        struct Finding: Encodable {
            var r: String
            var l: Int
            var m: String
        }

        /// One contract, every field omitted when it is empty or false.
        struct Contract: Encodable {
            var n: String
            var k: String
            var x: String
            /// The declaration as written, without its body.
            var d: String
            var s: String?
            /// The length of the summary's first sentence in UTF-16 units, as the page's script measures
            /// text, when it is shorter than the summary.
            var b: Int?
            var p: [Parameter]?
            /// The return type, the returns entry, the throws clause, and the throws entry.
            var rt: String?
            var r: String?
            var tc: String?
            var td: String?
            /// `true` for an `async` callable.
            var y: Bool?
            /// A property's annotated type.
            var vt: String?
            /// Other callouts as `[keyword, text]` pairs.
            var co: [[String]]?
            var no: [String]?
            var ex: String?
            var f: [Finding]?
            /// The types it mentions: `[node, 1 when only in its body]` pairs.
            var u: [[Int]]?
            /// The index of its file, and its line.
            var fi: Int
            var ln: Int
            var ov: Bool?
            /// `true` when the harness requires a doc, and `true` when it has one.
            var rq: Bool?
            var dc: Bool?
        }

        var files: [String] = []
        var nodes: [Node] = []
        var contracts: [Contract] = []
    }

    /// The bit each role sets in an edge's role mask, in model order.
    ///
    /// - Parameter roles: The roles of one edge.
    /// - Returns: A mask with bit `n` set for the `n`th role of ``Mention/Role/allCases``.
    static func roleMask(_ roles: [Mention.Role]) -> Int {
        let all = Mention.Role.allCases
        return roles.reduce(0) { mask, role in mask | (1 << (all.firstIndex(of: role) ?? 0)) }
    }

    /// Builds the page data for every node.
    ///
    /// - Parameters:
    ///   - site: The arranged interface.
    ///   - scopesOf: The map levels that draw each root, widest first, keyed by root id.
    /// - Returns: The data, with nodes in sidebar order and contracts in node order.
    static func pageData(_ site: Site, scopesOf: [String: [String]]) -> PageData {
        var data = PageData()
        var fileIndex: [String: Int] = [:]
        var nodeIndex: [String: Int] = [:]
        for (index, node) in site.nodes.enumerated() { nodeIndex[node.id] = index }
        func file(_ path: String) -> Int {
            if let index = fileIndex[path] { return index }
            fileIndex[path] = data.files.count
            data.files.append(path)
            return data.files.count - 1
        }
        func contract(_ contract: Site.Reviewed, owner: String) -> Int {
            var uses: [[Int]] = []
            var position: [String: Int] = [:]
            for mention in contract.mentions {
                guard let target = mention.resolved, target != owner, let index = nodeIndex[target] else { continue }
                let bodyOnly = mention.role == .body ? 1 : 0
                if let at = position[target] {
                    uses[at][1] = uses[at][1] & bodyOnly
                } else {
                    position[target] = uses.count
                    uses.append([index, bodyOnly])
                }
            }
            let brief = contract.summary.map(firstSentence)
            data.contracts.append(PageData.Contract(
                n: contract.name, k: contract.keyword, x: contract.access, d: contract.declaration,
                s: contract.summary, b: brief.flatMap { $0.utf16.count < (contract.summary?.utf16.count ?? 0) ? $0.utf16.count : nil },
                p: contract.parameters.isEmpty ? nil : contract.parameters.map { parameter in
                    PageData.Parameter(l: parameter.label, n: parameter.name, t: parameter.type,
                                       v: parameter.hasDefault ? true : nil, d: parameter.doc)
                },
                rt: contract.returnType, r: contract.returns, tc: contract.throwsClause, td: contract.throwsDoc,
                y: contract.isAsync ? true : nil, vt: contract.valueType,
                co: contract.callouts.isEmpty ? nil : contract.callouts.map { [$0.keyword, $0.text] },
                no: contract.notes.isEmpty ? nil : contract.notes, ex: contract.exemption,
                f: contract.findings.isEmpty ? nil : contract.findings.map { PageData.Finding(r: $0.rule, l: $0.line, m: $0.message) },
                u: uses.isEmpty ? nil : uses, fi: file(contract.file), ln: contract.line,
                ov: contract.isOverride ? true : nil, rq: contract.requiresDoc ? true : nil, dc: contract.isDocumented ? true : nil
            ))
            return data.contracts.count - 1
        }
        for node in site.nodes {
            let group = site.groups[node.id] ?? Site.Group()
            let (incoming, outgoing, nested) = site.neighbors(of: node)
            let head = group.head.map { contract($0, owner: node.id) }
            let members = group.members.map { contract($0, owner: node.id) }
            let pairs = { (edges: [Graph.Edge], end: KeyPath<Graph.Edge, String>) -> [[Int]] in
                edges.compactMap { edge in nodeIndex[edge[keyPath: end]].map { [$0, roleMask(edge.roles)] } }
            }
            let into = pairs(incoming, \.from)
            let out = pairs(outgoing, \.to)
            let children = nested.compactMap { nodeIndex[$0.id] }
            let scopes = scopesOf[node.root] ?? []
            data.nodes.append(PageData.Node(
                id: node.id, a: site.anchor(node.id), l: site.label(node),
                k: node.keyword == "file" ? "file scope" : node.keyword, m: node.module,
                x: node.keyword == "file" ? "public" : node.access, r: node.root,
                rl: node.root == node.id ? nil : site.byID[node.root].map(site.label),
                sc: scopes.isEmpty ? nil : scopes, h: head, c: members.isEmpty ? nil : members,
                i: into.isEmpty ? nil : into, o: out.isEmpty ? nil : out, n: children.isEmpty ? nil : children,
                f: group.findingCount == 0 ? nil : group.findingCount
            ))
        }
        return data
    }

    /// Encodes the page data for a `<script type="application/json">` element.
    ///
    /// - Parameter data: The page data.
    /// - Returns: Compact JSON with sorted keys, so the page bytes are stable. Every `<` is written as
    ///   `\u003c`, so no string can close the script element that holds it or open a comment inside it.
    static func encode(_ data: PageData) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }
}
