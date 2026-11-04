import Foundation
import GlossRead
import GlossModel
import GlossMap

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
            /// The module the node belongs to, which the view's eyebrow names.
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
            /// The external argument label, or `nil` for `_`.
            var l: String?
            /// The internal name, the same as the label when the signature gives only one.
            var n: String
            /// The type as written, with `...` for a variadic parameter.
            var t: String
            /// `true` when the parameter has a default value.
            var v: Bool?
            /// The text of the doc's entry for the parameter, or `nil` when the doc has none.
            var d: String?
        }

        /// One finding of a contract.
        struct Finding: Encodable {
            /// The rule's id, such as `missing-doc`.
            var r: String
            /// The source line the finding points at, which the page prints beside it.
            var l: Int
            /// The diagnostic's message, as doc text whose code spans the page renders.
            var m: String
        }

        /// One contract, every field omitted when it is empty or false.
        struct Contract: Encodable {
            /// The base name, as diagnostics report it: `init` for an initializer, `subscript` for a subscript.
            var n: String
            /// The introducing keyword as written, such as `func`, `var`, or `case`, which picks the section
            /// a member is listed in.
            var k: String
            /// The effective access level, from `open` down to `private`, which the access filter reads.
            var x: String
            /// The declaration as written, without its body.
            var d: String
            /// The doc's summary paragraph joined into one line, or `nil` when there is none.
            var s: String?
            /// The length of the summary's first sentence in UTF-16 units, as the page's script measures
            /// text, when it is shorter than the summary.
            var b: Int?
            /// The parameters of a callable, in signature order.
            var p: [Parameter]?
            /// The return type as written, for a callable that returns a value.
            var rt: String?
            /// The doc's `- Returns:` text.
            var r: String?
            /// The `throws`, `throws(E)`, or `rethrows` clause as written.
            var tc: String?
            /// The doc's `- Throws:` text.
            var td: String?
            /// `true` for an `async` callable.
            var y: Bool?
            /// A property's annotated type.
            var vt: String?
            /// Other callouts as `[keyword, text]` pairs.
            var co: [[String]]?
            /// The prose paragraphs below the markup block, one string each.
            var no: [String]?
            /// Why the harness excuses the declaration, in words; an excused declaration never shows as
            /// missing its doc.
            var ex: String?
            /// The rule findings, in source order.
            var f: [Finding]?
            /// The types it mentions: `[node, 1 when only in its body]` pairs.
            var u: [[Int]]?
            /// The index of its file in the page's file list.
            var fi: Int
            /// The declaration's line in that file, which the page shows after the file name.
            var ln: Int
            /// `true` for an `override`, which the page folds into its own section, since its contract is
            /// the inherited one.
            var ov: Bool?
            /// `true` when the harness requires a doc on the declaration.
            var rq: Bool?
            /// `true` when the declaration has a doc comment, whether or not it passes the rules.
            var dc: Bool?
        }

        /// The path of every file a contract comes from, each once, in order of first contract.
        var files: [String] = []
        /// Every node in sidebar order; edges, nesting, and uses name a node by its index here.
        var nodes: [Node] = []
        /// Every contract in node order, each node's own declaration before its members.
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
    ///   - atlas: The arranged interface.
    ///   - scopesOf: The map levels that draw each root, widest first, keyed by root id.
    /// - Returns: The data, with nodes in sidebar order and contracts in node order.
    static func pageData(_ atlas: Atlas, scopesOf: [String: [String]]) -> PageData {
        var data = PageData()
        var fileIndex: [String: Int] = [:]
        var nodeIndex: [String: Int] = [:]
        for (index, node) in atlas.nodes.enumerated() { nodeIndex[node.id] = index }
        func file(_ path: String) -> Int {
            if let index = fileIndex[path] { return index }
            fileIndex[path] = data.files.count
            data.files.append(path)
            return data.files.count - 1
        }
        func contract(_ contract: Atlas.Reviewed, owner: String) -> Int {
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
            let brief = contract.summary.map(Wording.firstSentence)
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
        for node in atlas.nodes {
            let group = atlas.group(node.id)
            let (incoming, outgoing, nested) = atlas.neighbors(of: node)
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
                id: node.id, a: anchor(node.id, in: atlas), l: atlas.label(node),
                k: Wording.kind(of: node), m: node.module,
                x: node.keyword == "file" ? "public" : node.access, r: node.root,
                rl: node.root == node.id ? nil : atlas.byID[node.root].map(atlas.label),
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
