import Foundation

/// Renders an ``Interface`` as one self-contained HTML page that discloses the system a level at a time.
///
/// The page opens on the front door, the types other code reaches first. From there a reader opens the
/// dependency map, one type and what flows in and out of it, one operation's full contract, and last
/// the types used only inside bodies. Each level shows sensible defaults and folds the rest behind a
/// visible count.
///
/// The page loads nothing and stamps no time, so the same sources always render the same bytes and a
/// CI artifact diffs cleanly. It shows only what the model holds; a gap on the page is a gap in the model.
public enum InterfacePage {
    /// Renders the whole page.
    ///
    /// - Parameters:
    ///   - interface: The contracts and graph to show.
    ///   - title: The project name for the heading and the browser tab.
    /// - Returns: A complete HTML document.
    public static func render(_ interface: Interface, title: String) -> String {
        let site = Site(interface)
        let scopes = mapScopes(site)
        var scopesOf: [String: [String]] = [:]
        for scope in scopes {
            for id in figure(scope, site: site, includeBody: true).shown { scopesOf[id, default: []].append(scope.id) }
        }
        let owed = interface.contracts.filter(\.requiresDoc)
        let findings = interface.contracts.reduce(0) { $0 + $1.findings.count }
        let hasPublic = interface.contracts.contains { Contract.rank($0.access) >= 3 }
        func pressed(_ min: Int) -> String { String(min == (hasPublic ? 3 : 1)) }
        var html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="claude:viewport-fit-sides" content="cover">
        <title>\(escape(title)) interface</title>
        <script>document.documentElement.classList.add("js");</script>
        <style>\(style)</style>
        </head>
        <body>
        <div class="app">
        <aside class="sidebar">
        <div class="brand"><div class="brand-top"><p class="eyebrow">Interface</p><button type="button" class="pane-toggle" id="collapse-left" aria-label="Hide the list">Hide</button></div><h1>\(escape(title))</h1></div>
        <dl class="stats">
        <div><dt>Declarations</dt><dd>\(interface.contracts.filter { Contract.rank($0.access) >= 1 }.count)</dd></div>
        <div><dt>Public</dt><dd>\(interface.contracts.filter { Contract.rank($0.access) >= 3 }.count)</dd></div>
        <div><dt>Documented</dt><dd>\(owed.filter(\.isDocumented).count)<span class="of">/\(owed.count)</span></dd></div>
        <div><dt>Findings</dt><dd class="\(findings == 0 ? "clean" : "dirty")">\(findings)</dd></div>
        </dl>
        <div class="controls">
        <div class="seg" role="group" aria-label="Access level">
        <button type="button" data-min="3" aria-pressed="\(pressed(3))">Public</button>
        <button type="button" data-min="1" aria-pressed="\(pressed(1))">Internal</button>
        <button type="button" data-min="0" aria-pressed="\(pressed(0))">All</button>
        </div>
        <input type="search" id="filter" placeholder="Find a type or member" aria-label="Find a type or member" autocomplete="off">
        <label class="check"><input type="checkbox" id="findings-only"> Only types with findings</label>
        </div>
        <details class="index" open><summary>Browse</summary><nav>
        <a class="top-link" href="#start" data-link="start">Start here</a>

        """
        for module in site.modules {
            html += "<h2><a href=\"#\(moduleAnchor(module))\" data-link=\"\(moduleAnchor(module))\">\(escape(module))</a></h2><ul>"
            for node in site.nodes where node.module == module {
                let group = site.groups[node.id] ?? Site.Group()
                let contracts = [group.head].compactMap { $0 } + group.members
                let rank = node.keyword == "file" ? 3 : contracts.map { Contract.rank($0.access) }.max() ?? Contract.rank(node.access)
                let search = ([node.name] + group.members.map(\.name)).joined(separator: " ").lowercased()
                let dot = group.findingCount > 0 ? "<span class=\"dot\" title=\"\(group.findingCount) findings\"></span>" : ""
                html += "<li class=\"depth-\(site.depth(node))\" data-group data-rank=\"\(rank)\" data-findings=\"\(group.findingCount)\" data-search=\"\(escape(search))\">"
                html += "<a href=\"#\(site.anchor(node.id))\" data-link=\"\(site.anchor(node.id))\">\(escape(site.shortLabel(node)))</a>\(dot)<span class=\"count\">\(group.members.count)</span></li>"
            }
            html += "</ul>\n"
        }
        html += "</nav></details>\n</aside>\n"
        html += "<div class=\"splitter split-left\" role=\"separator\" aria-orientation=\"vertical\" aria-label=\"Resize the list\" tabindex=\"0\" data-split=\"left\"></div>\n"
        html += stage(site, scopes: scopes)
        html += "<div class=\"splitter split-right\" role=\"separator\" aria-orientation=\"vertical\" aria-label=\"Resize the details\" tabindex=\"0\" data-split=\"right\"></div>\n"
        html += "<aside class=\"panel\" aria-label=\"Details\">\n<p class=\"preview-note\" id=\"preview-note\" hidden>Previewing. Click it to keep it here.</p>\n"
        html += startView(site, title: title, scope: scopes.first?.id ?? "")
        html += scopeViews(site, scopes: scopes)
        html += "<section class=\"view\" id=\"type\" data-view data-root=\"\" aria-live=\"polite\"></section>\n"
        html += "<script type=\"application/json\" id=\"page-data\">\(encode(pageData(site, scopesOf: scopesOf)))</script>\n"
        html += """
        <footer><p>Generated by gloss from \(interface.files.count) file\(interface.files.count == 1 ? "" : "s"). The same data is available as JSON with <code>gloss interface --json</code>.</p></footer>
        </aside>
        </div>
        <script>\(script)</script>
        </body>
        </html>

        """
        return html
    }

    // MARK: Site

    /// The interface arranged for the page: nodes, the contracts each one shows, and lookups between them.
    struct Site {
        /// The contracts one node shows: the type's own declaration, if scanned, and its members.
        struct Group {
            var head: Contract?
            var members: [Contract] = []
            var findingCount: Int { (head?.findings.count ?? 0) + members.reduce(0) { $0 + $1.findings.count } }
        }

        /// An edge between two root nodes, with nested types folded into their roots.
        struct Rolled {
            var from: String
            var to: String
            var roles: [Contract.Mention.Role]
        }

        var nodes: [Graph.Node]
        var edges: [Graph.Edge]
        var groups: [String: Group] = [:]
        var byID: [String: Graph.Node] = [:]
        var modules: [String] = []
        var rootIDs: [String] = []
        // Indexes built once, so a page for thousands of types never rescans every edge per type.
        private var edgesFrom: [String: [Graph.Edge]] = [:]
        private var edgesTo: [String: [Graph.Edge]] = [:]
        private var children: [String: [Graph.Node]] = [:]
        private var findingsUnder: [String: Int] = [:]
        private var folders: [String: String] = [:]
        private var rolledWithBody: [Rolled] = []
        private var rolledSignature: [Rolled] = []

        /// Indexes the interface by node.
        ///
        /// - Parameter interface: The interface to arrange.
        init(_ interface: Interface) {
            nodes = interface.graph.nodes
            edges = interface.graph.edges
            var seenModules = Set<String>()
            for node in nodes {
                byID[node.id] = node
                if seenModules.insert(node.module).inserted { modules.append(node.module) }
                if node.root == node.id { rootIDs.append(node.id) }
            }
            for contract in interface.contracts {
                let id = Graph.id(contract.module, Graph.key(of: contract))
                if contract.opensScope {
                    groups[id, default: Group()].head = contract
                } else {
                    groups[id, default: Group()].members.append(contract)
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
                if let index = parts.lastIndex(of: node.module), index + 2 < parts.count { folders[node.id] = parts[index + 1] }
            }
            rolledWithBody = Self.roll(edges, byID: byID, includeBody: true)
            rolledSignature = Self.roll(edges, byID: byID, includeBody: false)
        }

        /// The folder a type lives in, as the map's folder level groups it: the first directory under the
        /// module's own.
        ///
        /// - Parameter node: A node; its declaration's file decides, or its first member's.
        /// - Returns: The folder name, or empty for a file directly in the module's directory.
        func folder(of node: Graph.Node) -> String {
            folders[node.id] ?? ""
        }

        /// An element id made of characters every host keeps in a link fragment.
        ///
        /// - Parameter id: A node id.
        /// - Returns: `g-Module-Type-Nested`, or `g-Module-top` for file scope.
        func anchor(_ id: String) -> String {
            let safe = { (text: String) in String(text.map { $0.isLetter || $0.isNumber ? $0 : "-" }) }
            guard let node = byID[id] else { return "map" }
            return "g-" + safe(node.module) + "-" + (node.name.isEmpty ? "top" : safe(node.name))
        }

        /// How deep a node sits under its root type, for indenting the sidebar.
        ///
        /// - Parameter node: A node.
        /// - Returns: 0 for a root, one more per enclosing type.
        func depth(_ node: Graph.Node) -> Int {
            node.root == node.id ? 0 : node.name.split(separator: ".").count - 1
        }

        /// The node's full name as a reader says it.
        ///
        /// - Parameter node: A node.
        /// - Returns: The qualified name, `extension Name`, or `top level`.
        func label(_ node: Graph.Node) -> String {
            switch node.keyword {
            case "file": "\(node.module) top level"
            case "extension": "extension \(node.name)"
            default: node.name
            }
        }

        /// The node's name as the sidebar shows it under its parent: the last path component.
        ///
        /// - Parameter node: A node.
        /// - Returns: The label, shortened for nested types.
        func shortLabel(_ node: Graph.Node) -> String {
            if node.keyword == "file" { return "top level" }
            return depth(node) > 0 ? String(node.name.split(separator: ".").last ?? "") : label(node)
        }

        /// Whether one node is nested, at any depth, inside another.
        ///
        /// - Parameters:
        ///   - inner: The candidate nested node.
        ///   - outer: The candidate enclosing node.
        /// - Returns: `true` when both share a module and `inner`'s name extends `outer`'s with a dot.
        func isNested(_ inner: Graph.Node, in outer: Graph.Node) -> Bool {
            inner.module == outer.module && !outer.name.isEmpty && inner.name.hasPrefix(outer.name + ".")
        }

        /// A node's place in the graph: edges in from other nodes, edges out to other nodes, and the types
        /// nested directly in it. Edges to or from its own nested types are left out of both lists.
        ///
        /// - Parameter node: The node.
        /// - Returns: Incoming edges with signature edges first, outgoing edges, and direct children.
        func neighbors(of node: Graph.Node) -> (incoming: [Graph.Edge], outgoing: [Graph.Edge], nested: [Graph.Node]) {
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

        /// The finding count of a node together with every type nested in it.
        ///
        /// - Parameter root: A root node id.
        /// - Returns: The total.
        func findings(under root: String) -> Int {
            findingsUnder[root] ?? 0
        }

        /// Edges between root nodes, nested types folded into their roots.
        ///
        /// - Parameter includeBody: `false` drops the `body` role, and with it every edge made only of it.
        /// - Returns: One edge per ordered pair of roots, in order of first appearance.
        func rolled(includeBody: Bool) -> [Rolled] {
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
            let order = Contract.Mention.Role.allCases
            return result.map { edge in
                var edge = edge
                edge.roles.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
                return edge
            }
        }

        /// The front door of a module: root types used from another module, and root types nothing else
        /// in their own module uses but that do depend on something. A type that touches nothing is
        /// left out, since it is no way in, and so is an extension of another module's type unless
        /// another module uses it, since it adds to a door rather than being one.
        ///
        /// - Parameter module: The module name.
        /// - Returns: Root nodes in graph order.
        func entryPoints(in module: String) -> [Graph.Node] {
            var users: [String: [Graph.Node]] = [:]
            var dependents = Set<String>()
            for link in rolledWithBody {
                if let from = byID[link.from] { users[link.to, default: []].append(from) }
                dependents.insert(link.from)
            }
            return rootIDs.compactMap { byID[$0] }.filter { node in
                guard node.module == module else { return false }
                let incoming = users[node.id] ?? []
                if incoming.contains(where: { $0.module != module }) { return true }
                return node.keyword != "extension" && incoming.isEmpty && dependents.contains(node.id)
            }
        }
    }

    // MARK: Words

    /// Words for each role, read as "the source … the target".
    static let roleWords: [Contract.Mention.Role: String] = [
        .conformance: "conforms to", .property: "holds", .parameter: "takes",
        .returns: "returns", .throws: "throws", .body: "uses"
    ]

    /// Words for an edge's roles, in model order.
    ///
    /// - Parameter roles: The roles of one edge.
    /// - Returns: `holds · takes`, and the like.
    static func words(_ roles: [Contract.Mention.Role]) -> String {
        roles.compactMap { roleWords[$0] }.joined(separator: " · ")
    }

    /// The first sentence of a summary, for one-line listings; a period inside a code span does not end it.
    ///
    /// - Parameter text: A summary paragraph.
    /// - Returns: Text up to and including the first sentence-ending period, or all of it.
    static func firstSentence(_ text: String) -> String {
        var inCode = false
        var previous: Character = " "
        for (offset, character) in text.enumerated() {
            if character == "`" { inCode.toggle() }
            let next = text.dropFirst(offset + 1).first
            if !inCode, character == ".", next == nil || next == " ", previous != "." {
                return String(text.prefix(offset + 1))
            }
            previous = character
        }
        return text
    }

    // MARK: Start

    private static func startView(_ site: Site, title: String, scope: String) -> String {
        var html = """
        <section class="view" id="start" data-view data-root="" data-scope="\(scope)">
        <header class="view-head">
        <p class="eyebrow">Start here</p>
        <h2>The front door of \(escape(title))</h2>
        <p class="lede">These are the types other code reaches first: each one is used from another module, or is used by nothing else in its own. Open one to see what flows into and out of it, then follow those types inward.</p>
        </header>

        """
        let links = site.rolled(includeBody: true)
        for module in site.modules {
            let entries = site.entryPoints(in: module)
            guard !entries.isEmpty else { continue }
            html += "<section class=\"block\"><h3>\(escape(module))</h3><div class=\"cards\">"
            for node in entries {
                let group = site.groups[node.id] ?? Site.Group()
                let summary = group.head?.summary.map(firstSentence)
                    ?? (node.keyword == "file" ? "The module's file-scope code: for an executable, its entry point." : nil)
                let operations = group.members.filter { isCallable($0) && Contract.rank($0.access) >= 1 && !$0.isOverride }.count
                let users = links.filter { $0.to == node.id }.compactMap { site.byID[$0.from] }
                html += "<a class=\"card\" href=\"#\(site.anchor(node.id))\">"
                html += "<span class=\"card-kind\">\(escape(node.keyword == "file" ? "file scope" : node.keyword))</span>"
                html += "<code class=\"card-name\">\(escape(site.label(node)))</code>"
                html += summary.map { "<span class=\"card-summary\">\(inline($0))</span>" } ?? ""
                var facts: [String] = []
                if operations > 0 { facts.append("\(operations) operation\(operations == 1 ? "" : "s")") }
                if !users.isEmpty { facts.append("used by " + users.map(site.label).joined(separator: ", ")) }
                if !facts.isEmpty { html += "<span class=\"card-facts\">\(escape(facts.joined(separator: " · ")))</span>" }
                html += "</a>"
            }
            html += "</div></section>\n"
        }
        html += "<p class=\"caption\">Hover a box on the map to preview it here; select it to keep it.</p>\n</section>\n"
        return html
    }

    // MARK: Members

    /// A link to a node's view, filtered with the access level like everything else on the page.
    ///
    /// - Parameters:
    ///   - node: The node to link to.
    ///   - site: The arranged interface, for the label and anchor.
    /// - Returns: An `<a>` element; file scope counts as public so the filter never hides an entry point.
    static func chip(_ node: Graph.Node, site: Site) -> String {
        let dirty = (site.groups[node.id]?.findingCount ?? 0) > 0
        let access = node.keyword == "file" ? "public" : node.access
        return "<a class=\"chip\(dirty ? " dirty" : "")\" href=\"#\(site.anchor(node.id))\" data-id=\"\(escape(node.id))\" data-root=\"\(escape(node.root))\" data-access=\"\(access)\">\(escape(site.label(node)))</a>"
    }

    /// Whether a contract is something a caller invokes.
    ///
    /// - Parameter contract: Any contract.
    /// - Returns: `true` for functions, initializers, subscripts, and macros.
    static func isCallable(_ contract: Contract) -> Bool {
        ["func", "init", "subscript", "macro"].contains(contract.keyword)
    }

    // MARK: Figures

    /// Draws a placed figure as inline SVG: links to each node's view, a tooltip on each edge.
    ///
    /// - Parameters:
    ///   - layout: The placed figure.
    ///   - label: The accessible name of the figure.
    ///   - marker: A suffix that makes this figure's arrowhead id unique on the page.
    /// - Returns: An `<svg>` element.
    static func svg(_ layout: GraphLayout, label: String, marker: String) -> String {
        let format = GraphLayout.format
        let arrow = "arrow-" + marker
        var html = "<svg class=\"graph\" viewBox=\"0 0 \(format(layout.width)) \(format(layout.height))\" width=\"\(format(layout.width))\" height=\"\(format(layout.height))\" role=\"img\" aria-label=\"\(escape(label))\">"
        html += "<defs><marker id=\"\(arrow)\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path class=\"arrowhead\" d=\"M0,1 L9,5 L0,9 z\"/></marker></defs><g class=\"edges\">"
        for curve in layout.curves {
            let end = curve.reversed ? "marker-start" : "marker-end"
            html += "<path class=\"edge\(curve.link.dashed ? " body" : "")\" d=\"\(curve.path)\" data-from=\"\(escape(curve.link.from))\" data-to=\"\(escape(curve.link.to))\" \(end)=\"url(#\(arrow))\"><title>\(escape(curve.link.title))</title></path>"
        }
        html += "</g><g class=\"nodes\">"
        for box in layout.boxes {
            let item = box.item
            html += "<a class=\"node \(item.classes)\" href=\"#\(item.link)\" data-id=\"\(escape(item.id))\">"
            html += "<rect x=\"\(format(box.x))\" y=\"\(format(box.y))\" width=\"\(format(box.width))\" height=\"\(format(GraphLayout.boxHeight))\" rx=\"5\"/>"
            html += "<text class=\"label\" x=\"\(format(box.x + 12))\" y=\"\(format(box.y + 16))\">\(escape(item.label))</text>"
            html += "<text class=\"detail\" x=\"\(format(box.x + 12))\" y=\"\(format(box.y + 30))\">\(escape(item.detail))</text></a>"
        }
        return html + "</g></svg>"
    }

    // MARK: Text

    /// Renders doc text with its code spans: a backtick run opens a span that the next run of the same
    /// length closes, as in Markdown, and a double-backtick span is a DocC symbol link.
    ///
    /// - Parameter text: One paragraph of doc text.
    /// - Returns: Escaped HTML with `<code>` spans.
    static func inline(_ text: String) -> String {
        var html = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "`") {
            html += escape(String(rest[..<open]))
            let run = rest[open...].prefix { $0 == "`" }
            let afterOpen = rest[run.endIndex...]
            guard let close = afterOpen.range(of: String(run)) else {
                html += escape(String(rest[open...]))
                return html
            }
            let body = afterOpen[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            html += "<code\(run.count == 2 ? " class=\"link\"" : "")>\(escape(body))</code>"
            rest = afterOpen[close.upperBound...]
        }
        return html + escape(String(rest))
    }

    /// Escapes text for HTML content and double-quoted attributes.
    ///
    /// - Parameter text: Any text.
    /// - Returns: The text with `&`, `<`, `>`, `"`, and `'` replaced by entities.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }


    // MARK: Assets

    private static let style = """
    /* Layout: three panes on one screen. The list on the left, the map in the middle, and the text of
       one type on the right. Hover previews a type in the right pane; selecting keeps it there, so the
       map never moves and nothing covers it. */
    :root {
      --bg: #f6f7f9; --panel: #eef0f4; --surface: #ffffff; --ink: #1a1e26; --muted: #5d6573; --faint: #8a92a0;
      --rule: #dde1e7; --line: #b9c0cc; --edge: #7b8494; --accent: #2f4fbf; --accent-soft: #e6ebfa;
      --danger: #b4321c; --danger-soft: #fbe9e5; --exempt: #8a6100; --exempt-soft: #f6eed9; --ok: #2c7a4b;
      --font-code: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Consolas, monospace;
      --font-gloss: ui-serif, "New York", "Iowan Old Style", Georgia, serif;
      --font-ui: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    }
    @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
      --bg: #11141a; --panel: #151920; --surface: #1a1e26; --ink: #e5e8ee; --muted: #9aa2b0; --faint: #6f7786;
      --rule: #2a3039; --line: #3d4552; --edge: #7d8698; --accent: #94a9ff; --accent-soft: #1f2740;
      --danger: #ff8a73; --danger-soft: #34201c; --exempt: #e2b955; --exempt-soft: #2e2817; --ok: #6fcf97;
      color-scheme: dark;
    } }
    :root[data-theme="dark"] {
      --bg: #11141a; --panel: #151920; --surface: #1a1e26; --ink: #e5e8ee; --muted: #9aa2b0; --faint: #6f7786;
      --rule: #2a3039; --line: #3d4552; --edge: #7d8698; --accent: #94a9ff; --accent-soft: #1f2740;
      --danger: #ff8a73; --danger-soft: #34201c; --exempt: #e2b955; --exempt-soft: #2e2817; --ok: #6fcf97;
      color-scheme: dark;
    }
    * { box-sizing: border-box; }
    [hidden] { display: none !important; }
    html, body { height: 100%; }
    body { margin: 0; background: var(--bg); color: var(--ink); font: 14px/1.5 var(--font-ui); }
    a { color: var(--accent); }
    code { font-family: var(--font-code); font-size: 0.92em; }
    :focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
    summary { cursor: pointer; }
    .eyebrow { margin: 0; font: 600 11px/1.3 var(--font-ui); letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); }
    .term, .role { font: 600 10.5px/1.4 var(--font-ui); letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }

    .app { --left: 236px; --right: 420px; display: grid; grid-template-columns: var(--left) 7px minmax(0, 1fr) 7px var(--right); grid-template-rows: 100%; height: 100%; }
    .app.left-collapsed { grid-template-columns: 0 0 minmax(0, 1fr) 7px var(--right); }
    .left-collapsed .sidebar, .left-collapsed .split-left { display: none; }
    .sidebar { grid-column: 1; } .split-left { grid-column: 2; } .stage { grid-column: 3; } .split-right { grid-column: 4; } .panel { grid-column: 5; }
    .sidebar, .stage, .panel { grid-row: 1; height: 100%; overflow: auto; min-width: 0; }
    .splitter { grid-row: 1; position: relative; cursor: col-resize; touch-action: none; background: transparent; }
    .splitter::after { content: ""; position: absolute; top: 0; bottom: 0; left: 3px; width: 1px; background: var(--rule); transition: background 0.15s; }
    .splitter:hover::after, .splitter:focus-visible::after, .splitter.dragging::after { left: 2px; width: 3px; background: var(--accent); }
    .splitter:focus-visible { outline: none; }
    .app.resizing { cursor: col-resize; user-select: none; }
    .pane-toggle { font: 600 11.5px/1 var(--font-ui); color: var(--accent); background: var(--surface); border: 1px solid var(--rule); border-radius: 5px; padding: 5px 8px; cursor: pointer; }
    .pane-toggle:hover { border-color: var(--accent); }
    .brand-top, .stage-top { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
    .stage-top { justify-content: flex-start; }
    .sidebar { background: var(--panel); display: flex; flex-direction: column; gap: 18px;
      padding-block: 22px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: 14px; }
    .stage { display: grid; gap: 14px; align-content: start; padding-block: 22px 32px; padding-inline: 28px; }
    .panel { background: var(--surface); display: grid; gap: 24px; align-content: start;
      padding-block: 22px 40px; padding-left: 26px; padding-right: max(20px, env(safe-area-inset-right, 0px)); }

    .brand { display: grid; gap: 4px; }
    h1 { margin: 0; font: italic 400 2rem/1.1 var(--font-gloss); letter-spacing: -0.01em; }
    .stats { display: grid; grid-template-columns: 1fr 1fr; gap: 10px 12px; margin: 0; }
    .stats div { display: grid; gap: 1px; }
    .stats dt { font-size: 10.5px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
    .stats dd { margin: 0; font: 500 1.1rem/1.2 var(--font-code); font-variant-numeric: tabular-nums; }
    .stats .of { font-size: 0.75rem; color: var(--muted); }
    .stats .clean { color: var(--ok); } .stats .dirty { color: var(--danger); }
    .controls { display: grid; gap: 10px; }
    .seg { display: flex; border: 1px solid var(--rule); border-radius: 6px; overflow: hidden; background: var(--surface); }
    .seg button { flex: 1; font: 500 12px/1 var(--font-ui); color: var(--muted); background: none; border: 0; padding: 7px 6px; cursor: pointer; }
    .seg button + button { border-left: 1px solid var(--rule); }
    .seg button[aria-pressed="true"] { background: var(--accent-soft); color: var(--accent); }
    #filter { font: 13px var(--font-code); color: var(--ink); background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 6px 10px; width: 100%; }
    .check { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12.5px; cursor: pointer; }
    .index > summary { display: none; }
    .index nav { display: grid; gap: 2px; }
    .index h2 { margin: 14px 0 4px; font: 600 11px/1.4 var(--font-ui); letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); }
    .index h2 a { font: inherit; color: inherit; padding: 2px 6px; }
    .index ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 1px; }
    .index li { display: flex; align-items: center; gap: 6px; padding-right: 4px; }
    .index li.depth-1 { padding-left: 14px; } .index li.depth-2 { padding-left: 28px; } .index li.depth-3 { padding-left: 42px; }
    .index a { color: var(--ink); text-decoration: none; font-family: var(--font-code); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis;
      white-space: nowrap; flex: 1; min-width: 0; padding: 3px 6px; border-radius: 4px; }
    .index li.depth-1 a, .index li.depth-2 a, .index li.depth-3 a { color: var(--muted); }
    .index a:hover, .index a.previewed { color: var(--accent); background: var(--surface); }
    .index a[aria-current="true"] { background: var(--accent-soft); color: var(--accent); }
    .index .top-link { font: 600 13px/1.4 var(--font-ui); }
    .count { color: var(--faint); font: 400 11px var(--font-code); font-variant-numeric: tabular-nums; letter-spacing: 0; text-transform: none; }
    .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--danger); flex: none; display: inline-block; }

    .stage-head { display: grid; gap: 8px; }
    .stage-head h2 { margin: 0; font: 400 1.6rem/1.2 var(--font-gloss); }
    .stage .lede { font-size: 14.5px; }
    .map-variant { display: grid; gap: 10px; }
    .legend { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px 22px; font-size: 12.5px; color: var(--muted); }
    .legend li { display: flex; align-items: center; gap: 8px; }
    .swatch { width: 28px; border-top: 1.5px solid var(--edge); }
    .swatch.body { border-top-style: dashed; border-color: var(--faint); }
    .swatch.box { width: 18px; height: 11px; border: 1.5px dashed var(--line); border-radius: 3px; }
    .crumbs { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px; font: 600 15px/1.3 var(--font-gloss); }
    .crumbs a { text-decoration: none; }
    .crumbs .sep { color: var(--faint); }
    .crumbs [aria-current] { color: var(--ink); }
    .scope-map { display: grid; gap: 12px; }
    .overflow > summary { list-style: none; display: flex; gap: 8px; align-items: baseline; }
    .overflow > summary::-webkit-details-marker { display: none; }
    .overflow[open] .reveal::after { content: " ▾"; }
    .overflow .chips { margin-top: 8px; }
    .figure { overflow: auto; background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 14px; }
    .figure svg { display: block; max-width: 100%; height: auto; margin: 0 auto; }
    .graph .edge { fill: none; stroke: var(--edge); stroke-width: 1.3; transition: opacity 0.15s; }
    .graph .edge.body { stroke: var(--faint); stroke-dasharray: 4 3; }
    .graph .arrowhead { fill: var(--edge); }
    .graph .node { transition: opacity 0.15s; }
    .graph .node rect { fill: var(--surface); stroke: var(--line); stroke-width: 1; }
    .graph .node .label { font: 12px var(--font-code); fill: var(--ink); }
    .graph .node .detail { font: 10.5px var(--font-ui); fill: var(--muted); }
    .graph .node:hover rect, .graph .node:focus-visible rect { stroke: var(--accent); stroke-width: 1.5; }
    .graph .node.dirty rect { stroke: var(--danger); }
    .graph .node.scope rect { fill: var(--panel); stroke-width: 1.5; }
    .graph .node.boundary rect { fill: transparent; stroke-dasharray: 5 3; }
    .graph .node.boundary .label { fill: var(--muted); }
    .graph .node.private { opacity: 0.6; }
    .graph.focusing .edge { opacity: 0.1; }
    .graph.focusing .edge.lit { opacity: 1; stroke: var(--accent); }
    .graph.focusing .node { opacity: 0.32; }
    .graph.focusing .node.near, .graph.focusing .node.current { opacity: 1; }
    .graph .node.current rect { fill: var(--accent-soft); stroke: var(--accent); stroke-width: 2; }
    .caption { margin: 0; color: var(--muted); font-size: 13px; }
    .loose { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin: 0; }
    .loose .term { padding-right: 4px; }

    .preview-note { position: sticky; top: -22px; z-index: 2; margin: -22px -20px 0 -26px; padding: 8px 26px; background: var(--accent-soft);
      color: var(--accent); font-size: 12px; font-weight: 600; border-bottom: 1px solid var(--rule); }
    .js .view:not(.active) { display: none; }
    .view { display: grid; gap: 26px; min-width: 0; }
    .view-head { display: grid; gap: 10px; }
    .view-head h2 { margin: 0; font: 400 1.6rem/1.2 var(--font-gloss); text-wrap: balance; }
    .view-head h2.decl { font: 400 0.98rem/1.5 var(--font-code); color: var(--muted); }
    .view-head h2.decl code { white-space: pre-wrap; overflow-wrap: anywhere; font-size: 1em; }
    .lede { margin: 0; max-width: 64ch; color: var(--muted); font: 15.5px/1.55 var(--font-gloss); }
    .lede.ink { color: var(--ink); font-size: 17px; }
    .lede code, .card-summary code { font-size: 0.8em; background: var(--bg); border: 1px solid var(--rule); border-radius: 4px; padding: 0 4px; }
    .more > summary { color: var(--accent); font-size: 13px; }
    .more-body { display: grid; gap: 8px; padding: 10px 0 0 14px; border-left: 1px solid var(--rule); margin-top: 8px; font: 15px/1.55 var(--font-gloss); color: var(--muted); }
    .more-body p { margin: 0; }
    .block { display: grid; gap: 12px; min-width: 0; }
    .block h3 { margin: 0; font: 600 11px/1.4 var(--font-ui); letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); display: inline-flex; gap: 8px; align-items: baseline; }
    .loc { margin: 0; font: 11px var(--font-code); color: var(--faint); }

    .cards { display: grid; gap: 10px; }
    .loose.overflow { display: block; }
    .card { display: grid; gap: 6px; align-content: start; padding: 14px 16px; background: var(--bg); border: 1px solid var(--rule); border-radius: 8px; color: var(--ink); text-decoration: none; }
    .card:hover { border-color: var(--accent); }
    .card-kind { font: 600 10.5px/1 var(--font-ui); letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
    .card-name { font: 600 15px var(--font-code); }
    .card-summary { font: 15px/1.45 var(--font-gloss); }
    .card-facts { font-size: 12px; color: var(--muted); }

    .flow { display: grid; gap: 0; border-left: 2px solid var(--line); margin-left: 6px; }
    .flow .band { display: grid; grid-template-columns: 84px minmax(0, 1fr); gap: 4px 12px; align-items: baseline; padding: 7px 0 7px 18px; position: relative; }
    .flow .band::before { content: ""; position: absolute; left: -5px; top: 14px; width: 8px; height: 8px; border-radius: 50%; background: var(--surface); border: 2px solid var(--line); }
    .flow .core { padding: 10px 0 10px 18px; position: relative; }
    .flow .core::before { content: ""; position: absolute; left: -7px; top: 50%; margin-top: -6px; width: 12px; height: 12px; border-radius: 50%; background: var(--accent); }
    .flow .core code { font: 600 15px var(--font-code); color: var(--accent); background: var(--accent-soft); padding: 4px 10px; border-radius: 5px; }
    .flow .inside > summary { grid-column: 1 / -1; display: grid; grid-template-columns: 84px minmax(0, 1fr); gap: 4px 12px; align-items: baseline; list-style: none; }
    .flow .inside > summary::-webkit-details-marker { display: none; }
    .reveal { color: var(--accent); font-size: 13px; }
    .reveal::after { content: " ▸"; }
    .inside[open] .reveal::after { content: " ▾"; }
    .flow .inside > .chips { grid-column: 2; }
    .chips { display: flex; flex-wrap: wrap; gap: 6px; min-width: 0; }
    .more-chips { display: contents; }
    .more-chips > summary { list-style: none; font-size: 12px; align-self: center; }
    .more-chips > summary::-webkit-details-marker { display: none; }
    .more-chips[open] > summary { display: none; }
    .more-chips > .chips { display: contents; }
    .none { color: var(--faint); font-style: italic; font-size: 13px; }
    .chip { font: 12px var(--font-code); color: var(--ink); text-decoration: none; border: 1px solid var(--line); background: var(--surface); border-radius: 4px; padding: 2px 7px; }
    .chip.body { border-style: dashed; color: var(--muted); background: transparent; }
    .chip.dirty { border-color: var(--danger); }
    .chip.scope { background: var(--panel); font-weight: 600; }
    .chip:hover { border-color: var(--accent); color: var(--accent); }

    .members { display: grid; border-top: 1px solid var(--rule); }
    .member { border-bottom: 1px solid var(--rule); }
    .member > summary { display: grid; grid-template-columns: 14px minmax(0, 1fr) auto; align-items: baseline; gap: 2px 6px; padding: 9px 0; list-style: none; }
    .member > summary::-webkit-details-marker { display: none; }
    .member > summary::before { content: "▸"; color: var(--muted); font-size: 12px; grid-column: 1; }
    .member[open] > summary::before { content: "▾"; }
    .member.private { opacity: 0.62; }
    .sig { font: 12.5px/1.5 var(--font-code); min-width: 0; overflow-wrap: anywhere; }
    .sig b { color: var(--ink); }
    .flow-line { color: var(--muted); }
    .param { color: var(--faint); }
    .sig { grid-column: 2; }
    .member > summary > .dot { grid-column: 3; }
    .brief { grid-column: 2 / -1; min-width: 0; color: var(--muted); font: 14px/1.45 var(--font-gloss); }
    .member-body { display: grid; gap: 12px; padding: 4px 0 16px 20px; }
    .fold > summary { display: flex; align-items: baseline; gap: 12px; list-style: none; }
    .fold > summary::-webkit-details-marker { display: none; }
    .fold > summary::after { content: "Show ▸"; color: var(--accent); font-size: 12px; }
    .fold[open] > summary::after { content: "Hide ▾"; }
    .fold-note { color: var(--faint); font-size: 12px; }
    .fold > .members { margin-top: 12px; }
    .code { min-width: 0; display: flex; flex-direction: column; gap: 4px; }
    .code code { font-size: 12px; line-height: 1.55; white-space: pre-wrap; overflow-wrap: anywhere; color: var(--muted); }
    .kw { color: var(--accent); } .attr { color: var(--exempt); } .ty { color: var(--ink); } .name { font-weight: 700; color: var(--ink); }
    .gloss { min-width: 0; display: grid; gap: 8px; align-content: start; font-family: var(--font-gloss); font-size: 15px; line-height: 1.5; }
    .gloss p { margin: 0; }
    .gloss code { font-size: 12px; color: var(--ink); background: var(--bg); border: 1px solid var(--rule); border-radius: 4px; padding: 0 4px; }
    .gloss code.link, .lede code.link { color: var(--accent); border-color: transparent; background: var(--accent-soft); }
    .note { color: var(--muted); font-size: 14px; }
    .missing { color: var(--faint); font-style: italic; }
    .exempt { color: var(--exempt); font-size: 14px; }
    .tag { font: 600 10px/1 var(--font-ui); letter-spacing: 0.08em; text-transform: uppercase; background: var(--exempt-soft); color: var(--exempt); padding: 3px 6px; border-radius: 3px; vertical-align: 2px; }
    .terms { margin: 0; display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 4px 14px; font-size: 14px; }
    .terms dt { font-family: var(--font-ui); display: flex; flex-direction: column; min-width: 0; }
    .terms dt code { background: none !important; border: 0 !important; padding: 0 !important; font-weight: 600; }
    .terms .term { padding-top: 3px; }
    .terms .type { font: 11px var(--font-code); color: var(--faint); max-width: 18ch; overflow-wrap: anywhere; }
    .terms dd { margin: 0; min-width: 0; }
    .uses { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; font-family: var(--font-ui); margin: 0; }
    .uses .term { padding-right: 4px; }
    .findings { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; font: 13px/1.45 var(--font-ui); }
    .findings li { background: var(--danger-soft); color: var(--ink); border-left: 2px solid var(--danger); padding: 6px 10px; border-radius: 0 4px 4px 0; }
    .findings .rule { color: var(--danger); font-weight: 600; background: none !important; border: 0 !important; padding: 0 !important; }
    .findings .at { color: var(--muted); font-size: 11px; white-space: nowrap; }
    .findings-fold > summary { list-style: none; font-size: 13px; }
    .findings-fold > summary::-webkit-details-marker { display: none; }
    .findings-fold[open] .reveal::after { content: " ▾"; }
    .findings-fold > .findings { margin-top: 8px; }
    .bad { color: var(--danger); font-weight: 600; }
    footer p { margin: 0; color: var(--faint); font-size: 12px; }

    @media (max-width: 1180px) { .stage { padding-inline: 18px; } }
    @media (max-width: 900px) {
      html, body { height: auto; }
      .app { display: block; height: auto; }
      .sidebar, .stage, .panel { height: auto; overflow: visible; }
      .splitter, .pane-toggle { display: none !important; }
      .left-collapsed .sidebar { display: flex; }
      .sidebar { border-right: 0; border-bottom: 1px solid var(--rule); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .index > summary { display: list-item; font-weight: 600; color: var(--accent); }
      .stage { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .panel { border-top: 1px solid var(--rule); padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .preview-note { display: none !important; }
      .flow .band, .flow .inside > summary { grid-template-columns: minmax(0, 1fr); }
      .flow .inside > .chips { grid-column: 1; }
      .member-body { padding-left: 10px; }
    }
    @media (prefers-reduced-motion: reduce) { .graph .edge, .graph .node { transition: none; } }
    """

    private static let script = """
    (function () {
      var views = {};
      document.querySelectorAll("[data-view]").forEach(function (view) { views[view.id] = view; });
      var panel = document.querySelector(".panel");
      var stage = document.querySelector(".stage");
      var note = document.getElementById("preview-note");
      var narrow = window.matchMedia("(max-width: 900px)");
      var index = document.querySelector(".index");
      var selected = "start";
      var previewing = null;
      var scopeMaps = {};
      document.querySelectorAll("[data-scope-map]").forEach(function (map) { scopeMaps[map.dataset.scopeMap] = map; });
      var currentScope = Object.keys(scopeMaps)[0];
      var savedScroll = 0;
      var timers = { show: 0, hide: 0 };
      var rank = { open: 3, public: 3, package: 2, internal: 1, fileprivate: 0, private: 0 };
      var pressed = document.querySelector('.seg button[aria-pressed="true"]');
      var state = { min: pressed ? Number(pressed.dataset.min) : 1, query: "", findings: false };

      // Type views are built from the embedded data when a reader reaches them. Every decision was
      // made by gloss; these functions only fill templates.
      var data = JSON.parse(document.getElementById("page-data").textContent);
      var byAnchor = {};
      data.nodes.forEach(function (node, position) { byAnchor[node.a] = position; });
      var typeView = views.type;
      delete views.type;
      var rendered = {};
      var shownView = null;
      var ROLES = ["conformance", "property", "parameter", "returns", "throws", "body"];
      var WORDS = { conformance: "conforms to", property: "holds", parameter: "takes", returns: "returns", throws: "throws", body: "uses" };
      var BODY = 32;
      var CALLABLE = { func: 1, init: 1, subscript: 1, macro: 1 };
      var KEYWORDS = {};
      ("func init deinit subscript struct class enum protocol actor extension var let case typealias associatedtype macro "
        + "static open public package internal fileprivate private throws rethrows async mutating nonmutating override final "
        + "inout some any convenience required nonisolated consuming borrowing lazy weak unowned indirect where get set "
        + "dynamic optional isolated sending").split(" ").forEach(function (word) { KEYWORDS[word] = 1; });
      var entities = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
      function esc(text) { return String(text).replace(/[&<>"']/g, function (c) { return entities[c]; }); }
      function inline(text) {
        var html = "";
        var rest = text;
        for (;;) {
          var open = rest.indexOf("`");
          if (open < 0) break;
          html += esc(rest.slice(0, open));
          var length = 0;
          while (rest[open + length] === "`") length += 1;
          var after = rest.slice(open + length);
          var close = after.indexOf("`".repeat(length));
          if (close < 0) return html + esc(rest.slice(open));
          html += "<code" + (length === 2 ? ' class="link"' : "") + ">" + esc(after.slice(0, close).trim()) + "</code>";
          rest = after.slice(close + length);
        }
        return html + esc(rest);
      }
      function highlight(text, name) {
        var html = "";
        var word = "";
        var marked = false;
        function flush() {
          if (!word) return;
          var escaped = esc(word);
          if (!marked && (word === name || word === "`" + name + "`")) { html += '<b class="name">' + escaped + "</b>"; marked = true; }
          else if (KEYWORDS[word]) html += '<span class="kw">' + escaped + "</span>";
          else if (word[0] === "@") html += '<span class="attr">' + escaped + "</span>";
          else if (/\\p{Lu}/u.test(word[0])) html += '<span class="ty">' + escaped + "</span>";
          else html += escaped;
          word = "";
        }
        for (var character of text) {
          if (/[\\p{L}\\p{N}_`]/u.test(character) || (character === "@" && !word)) { word += character; }
          else { flush(); html += esc(character); }
        }
        flush();
        return html;
      }
      function words(mask) {
        return ROLES.filter(function (role, bit) { return mask & (1 << bit); }).map(function (role) { return WORDS[role]; }).join(" · ");
      }
      function chip(position, options) {
        var node = data.nodes[position];
        var label = options.short ? node.l.split(".").pop() : node.l;
        return '<a class="chip' + (options.dashed ? " body" : "") + (node.f ? " dirty" : "") + '" href="#' + node.a + '" data-id="' + esc(node.id)
          + '" data-root="' + esc(node.r) + '" data-access="' + node.x + '"' + (options.title ? ' title="' + esc(options.title) + '"' : "") + ">" + esc(label) + "</a>";
      }
      // Findings show in full when they are few; a long list folds behind its count.
      var totalFindings = data.contracts.reduce(function (sum, contract) { return sum + (contract.f ? contract.f.length : 0); }, 0);
      function findingsList(contract) {
        if (!contract.f) return "";
        var list = '<ul class="findings">' + contract.f.map(function (finding) {
          return '<li><code class="rule">' + esc(finding.r) + "</code> " + inline(finding.m) + ' <span class="at">line ' + finding.l + "</span></li>";
        }).join("") + "</ul>";
        if (contract.f.length <= 2) return list;
        return '<details class="findings-fold"><summary><span class="bad">' + contract.f.length + ' findings</span> <span class="reveal">Show</span></summary>' + list + "</details>";
      }
      function signature(contract) {
        if (CALLABLE[contract.k]) {
          var parameters = (contract.p || []).map(function (parameter) {
            return (parameter.l ? '<span class="param">' + esc(parameter.l) + ":</span> " : "") + '<span class="ty">' + esc(parameter.t) + "</span>";
          }).join(", ");
          var text = '<span class="flow-line">(' + parameters + ")";
          if (contract.y) text += ' <span class="kw">async</span>';
          if (contract.tc) text += ' <span class="kw">' + esc(contract.tc) + "</span>";
          if (contract.rt) text += ' → <span class="ty">' + esc(contract.rt) + "</span>";
          return text + "</span>";
        }
        return contract.vt ? '<span class="flow-line">: <span class="ty">' + esc(contract.vt) + "</span></span>" : "";
      }
      function entry(term, type, text) {
        return "<dt>" + term + (type ? '<span class="type">' + esc(type) + "</span>" : "") + "</dt>"
          + (text ? "<dd>" + inline(text) + "</dd>" : '<dd class="missing">Undocumented.</dd>');
      }
      function gloss(contract) {
        var html = contract.s ? '<p class="summary">' + inline(contract.s) + "</p>" : "";
        if (contract.ex) html += '<p class="exempt"><span class="tag">Exempt</span> ' + inline(contract.ex) + "</p>";
        var terms = (contract.p || []).map(function (parameter) {
          var label = parameter.l ? (parameter.l === parameter.n ? parameter.l : parameter.l + " " + parameter.n) : "_ " + parameter.n;
          return entry("<code>" + esc(label) + "</code>", parameter.t + (parameter.v ? " = default" : ""), parameter.d);
        }).join("");
        if (contract.rt) terms += entry('<span class="term">Returns</span>', contract.rt, contract.r);
        if (contract.tc) terms += entry('<span class="term">Throws</span>', contract.tc, contract.td);
        (contract.co || []).forEach(function (callout) {
          terms += '<dt><span class="term">' + esc(callout[0]) + "</span></dt><dd>" + inline(callout[1]) + "</dd>";
        });
        if (terms && (!contract.ex || contract.dc)) html += '<dl class="terms">' + terms + "</dl>";
        (contract.no || []).forEach(function (note) { html += '<p class="note">' + inline(note) + "</p>"; });
        if (contract.u) {
          html += '<p class="uses"><span class="term">Uses</span>' + contract.u.map(function (use) {
            return chip(use[0], { dashed: use[1] === 1, title: use[1] === 1 ? "Used inside the body" : "Part of the signature" });
          }).join("") + "</p>";
        }
        return html + findingsList(contract);
      }
      function member(position) {
        var contract = data.contracts[position];
        var count = contract.f ? contract.f.length : 0;
        var html = '<details class="member' + (rank[contract.x] === 0 ? " private" : "") + '" data-row data-access="' + contract.x
          + '" data-findings="' + count + '"' + (count && totalFindings <= 100 ? " open" : "") + '><summary><span class="sig"><b>' + esc(contract.n) + "</b>" + signature(contract) + "</span>";
        if (count) html += '<span class="dot" title="' + count + ' findings"></span>';
        if (contract.s) html += '<span class="brief">' + inline(contract.b ? contract.s.slice(0, contract.b) : contract.s) + "</span>";
        else if (contract.rq && !contract.ex) html += '<span class="brief missing">No doc comment.</span>';
        var file = data.files[contract.fi].split("/").pop();
        return html + '</summary><div class="member-body"><div class="code"><code>' + highlight(contract.d, contract.n) + '</code><span class="loc">'
          + esc(file) + ":" + contract.ln + '</span></div><div class="gloss">' + gloss(contract) + "</div></div></details>";
      }
      function members(node) {
        var list = node.c || [];
        var of = function (test) { return list.filter(function (position) { return test(data.contracts[position]); }); };
        var property = function (contract) { return contract.k === "var" || contract.k === "let"; };
        var sections = [
          ["Operations", of(function (contract) { return CALLABLE[contract.k] && !contract.ov; }), false],
          ["Properties", of(function (contract) { return property(contract) && !contract.ov; }), false],
          ["Cases", of(function (contract) { return contract.k === "case"; }), false],
          ["Other", of(function (contract) { return !CALLABLE[contract.k] && !property(contract) && contract.k !== "case"; }), false],
          ["Overrides", of(function (contract) { return contract.ov; }), true]
        ];
        return sections.filter(function (section) { return section[1].length; }).map(function (section) {
          var items = section[1].map(member).join("");
          var heading = section[0] + ' <span class="count" data-shown>' + section[1].length + "</span>";
          return section[2]
            ? '<section class="block"><details class="fold"><summary><h3>' + heading + '</h3><span class="fold-note">Inherited contracts, folded</span></summary><div class="members">' + items + "</div></details></section>"
            : '<section class="block"><h3>' + heading + '</h3><div class="members">' + items + "</div></section>";
        }).join("");
      }
      // A row of chips shows its first twelve and folds the rest behind a count.
      function capped(chips) {
        if (chips.length <= 12) return chips.join("");
        return chips.slice(0, 12).join("") + '<details class="more-chips"><summary class="reveal">' + (chips.length - 12) + " more</summary>"
          + '<div class="chips">' + chips.slice(12).join("") + "</div></details>";
      }
      function flow(node) {
        var name = node.k === "file scope" ? "top level" : node.rl ? node.l.split(".").pop() : node.l;
        var incoming = node.i || [];
        var outgoing = node.o || [];
        var html = '<section class="block"><h3>Flow</h3><div class="flow"><div class="band"><span class="role">Used by</span><div class="chips">';
        html += incoming.length ? capped(incoming.map(function (pair) {
          return chip(pair[0], { dashed: pair[1] === BODY, title: data.nodes[pair[0]].l + " " + words(pair[1]) + " " + name });
        })) : '<span class="none">Nothing in the scanned sources</span>';
        html += '</div></div><div class="core"><code>' + esc(name) + "</code></div>";
        var rows = "";
        ROLES.forEach(function (role, bit) {
          if (role === "body") return;
          var targets = outgoing.filter(function (pair) { return pair[1] & (1 << bit); });
          if (targets.length) rows += '<div class="band"><span class="role">' + WORDS[role] + '</span><div class="chips">' + capped(targets.map(function (pair) { return chip(pair[0], {}); })) + "</div></div>";
        });
        html += rows || '<div class="band"><span class="role">signature</span><div class="chips"><span class="none">No scanned types in its signatures</span></div></div>';
        if (node.n) html += '<div class="band"><span class="role">nests</span><div class="chips">' + node.n.map(function (child) { return chip(child, { short: true }); }).join("") + "</div></div>";
        var inside = outgoing.filter(function (pair) { return pair[1] === BODY; });
        if (inside.length) {
          html += '<details class="band inside"><summary><span class="role">inside</span><span class="reveal">Uses ' + inside.length + " more type" + (inside.length === 1 ? "" : "s")
            + ' inside its bodies</span></summary><div class="chips">' + capped(inside.map(function (pair) { return chip(pair[0], { dashed: true }); })) + "</div></details>";
        }
        return html + "</div></section>";
      }
      function renderType(position) {
        var node = data.nodes[position];
        var head = node.h != null ? data.contracts[node.h] : null;
        var html = '<header class="view-head"><p class="eyebrow">' + esc(node.m) + " · " + esc(node.k) + (node.rl ? " · in " + esc(node.rl) : "") + "</p>";
        if (head) {
          html += '<h2 class="decl"><code>' + highlight(head.d, head.n) + "</code></h2>";
          if (head.s) html += '<p class="lede ink">' + inline(head.s) + "</p>";
          else if (!head.ex) html += '<p class="lede missing">No doc comment.</p>';
          html += findingsList(head);
          var more = (head.no || []).map(function (note) { return "<p>" + inline(note) + "</p>"; }).join("")
            + (head.co || []).map(function (callout) { return '<p><span class="term">' + esc(callout[0]) + "</span> " + inline(callout[1]) + "</p>"; }).join("")
            + (head.ex ? '<p><span class="tag">Exempt</span> ' + inline(head.ex) + "</p>" : "");
          if (more) html += '<details class="more"><summary>More about ' + esc(head.n) + '</summary><div class="more-body">' + more + '<p class="loc">' + esc(data.files[head.fi]) + ":" + head.ln + "</p></div></details>";
        } else {
          html += "<h2>" + esc(node.l) + "</h2>" + (node.k === "extension"
            ? '<p class="lede">Members added to a type that no scanned source declares.</p>'
            : '<p class="lede">Declarations and statements at file scope in this module.</p>');
        }
        return html + "</header>" + flow(node) + members(node);
      }
      // Returns the section that shows a view id, building a type's view into the shared section.
      function mount(id) {
        if (views[id]) return views[id];
        var position = byAnchor[id];
        if (rendered.id !== id) {
          var node = data.nodes[position];
          typeView.innerHTML = renderType(position);
          typeView.dataset.root = node.r;
          typeView.dataset.scopes = (node.sc || []).join(" ");
          rendered.id = id;
          applyRows(typeView);
        }
        return typeView;
      }
      function known(id) { return !!views[id] || byAnchor[id] !== undefined; }

      // Lights a type on the map: its box, its edges, and its neighbors; everything else dims.
      function light(root) {
        document.querySelectorAll(".graph").forEach(function (graph) {
          var target = root && graph.querySelector('.node[data-id="' + CSS.escape(root) + '"]');
          graph.classList.toggle("focusing", !!target);
          var near = {};
          graph.querySelectorAll(".edge").forEach(function (edge) {
            var lit = !!target && (edge.dataset.from === root || edge.dataset.to === root);
            edge.classList.toggle("lit", lit);
            if (lit) { near[edge.dataset.from] = true; near[edge.dataset.to] = true; }
          });
          graph.querySelectorAll(".node").forEach(function (node) {
            node.classList.toggle("near", !!near[node.dataset.id]);
            node.classList.toggle("current", !!target && node.dataset.id === root);
          });
        });
      }
      function display(id) {
        shownView = mount(id);
        Object.keys(views).forEach(function (key) { views[key].classList.toggle("active", views[key] === shownView); });
        typeView.classList.toggle("active", typeView === shownView);
        light(shownView.dataset.root || null);
        document.querySelectorAll(".index a.previewed").forEach(function (link) { link.classList.remove("previewed"); });
      }
      // The selection decides the map level: a module or folder view draws its own level; a type keeps
      // the current level when that level draws it, and otherwise moves to the widest one that does.
      function showScope(id) {
        if (!scopeMaps[id]) return;
        currentScope = id;
        Object.keys(scopeMaps).forEach(function (key) { scopeMaps[key].hidden = key !== id; });
      }
      function scopeFor(view) {
        if (view.dataset.scope) return view.dataset.scope;
        var list = (view.dataset.scopes || "").split(" ").filter(Boolean);
        if (!list.length || list.indexOf(currentScope) >= 0) return currentScope;
        return list[0];
      }
      function select(id, reveal) {
        selected = known(id) ? id : "start";
        previewing = null;
        note.hidden = true;
        showScope(scopeFor(mount(selected)));
        display(selected);
        document.querySelectorAll("[data-link]").forEach(function (link) {
          link.setAttribute("aria-current", String(link.dataset.link === selected));
        });
        panel.scrollTop = 0;
        if (!reveal) return;
        var root = shownView.dataset.root;
        var node = root && stage.querySelector('[data-scope-map]:not([hidden]) .map-variant:not([hidden]) .node[data-id="' + CSS.escape(root) + '"]');
        if (node && !narrow.matches) node.scrollIntoView({ block: "nearest", inline: "nearest" });
        if (narrow.matches) { index.open = false; panel.scrollIntoView(); }
      }
      function preview(id) {
        if (!known(id) || narrow.matches) return;
        if (id === selected) { endPreview(); return; }
        if (!previewing) savedScroll = panel.scrollTop;
        previewing = id;
        display(id);
        note.hidden = false;
        panel.scrollTop = 0;
        var link = document.querySelector('.index a[data-link="' + id + '"]');
        if (link) link.classList.add("previewed");
      }
      function endPreview() {
        if (!previewing) return;
        previewing = null;
        note.hidden = true;
        display(selected);
        panel.scrollTop = savedScroll;
      }

      // Hover a box on the map or a name in the list to preview it; leave to return to the selection.
      function source(target) {
        return target && target.closest ? target.closest(".stage .node, .index a[data-link]") : null;
      }
      function previewID(element) {
        return element.classList.contains("node") ? element.getAttribute("href").slice(1) : element.dataset.link;
      }
      document.addEventListener("mouseover", function (event) {
        var element = source(event.target);
        if (element) {
          clearTimeout(timers.hide);
          clearTimeout(timers.show);
          timers.show = setTimeout(function () { preview(previewID(element)); }, previewing ? 40 : 140);
          return;
        }
        var chip = event.target.closest && event.target.closest(".panel .chip[data-root]");
        if (chip) light(chip.dataset.root);
      });
      document.addEventListener("mouseout", function (event) {
        var element = source(event.target);
        if (element && !element.contains(event.relatedTarget)) {
          clearTimeout(timers.show);
          timers.hide = setTimeout(endPreview, 180);
        }
        var chip = event.target.closest && event.target.closest(".panel .chip[data-root]");
        if (chip && !chip.contains(event.relatedTarget)) light(shownView ? shownView.dataset.root || null : null);
      });
      // Moving into the panel to read a preview keeps it until the pointer leaves the panel.
      panel.addEventListener("mouseenter", function () { clearTimeout(timers.hide); clearTimeout(timers.show); });
      panel.addEventListener("mouseleave", function () { if (previewing) timers.hide = setTimeout(endPreview, 180); });
      window.addEventListener("hashchange", function () { select(location.hash.slice(1), true); });
      if (narrow.matches) index.open = false;

      function apply() {
        document.querySelectorAll("[data-group]").forEach(function (item) {
          item.hidden = Number(item.dataset.rank) < state.min
            || (state.findings && Number(item.dataset.findings) === 0)
            || (state.query !== "" && item.dataset.search.indexOf(state.query) === -1);
        });
        document.querySelectorAll(".index ul").forEach(function (list) {
          list.previousElementSibling.hidden = !list.querySelector("[data-group]:not([hidden])");
        });
        applyRows(document);
      }
      // Hides what the access and findings filters exclude inside one part of the page.
      function applyRows(root) {
        root.querySelectorAll(".chip[data-access]").forEach(function (chip) {
          chip.hidden = rank[chip.dataset.access] < state.min;
        });
        root.querySelectorAll(".flow .band").forEach(function (band) {
          var chips = band.querySelectorAll(".chip");
          band.hidden = chips.length > 0 && !band.querySelector(".chip:not([hidden])");
        });
        root.querySelectorAll(".members").forEach(function (list) {
          var shown = 0;
          list.querySelectorAll("[data-row]").forEach(function (row) {
            row.hidden = rank[row.dataset.access] < state.min || (state.findings && Number(row.dataset.findings) === 0);
            if (!row.hidden) shown += 1;
          });
          var block = list.closest(".block");
          block.hidden = shown === 0;
          var count = block.querySelector("[data-shown]");
          if (count) count.textContent = shown;
        });
      }
      document.querySelectorAll(".seg button").forEach(function (button) {
        button.addEventListener("click", function () {
          state.min = Number(button.dataset.min);
          document.querySelectorAll(".seg button").forEach(function (other) {
            other.setAttribute("aria-pressed", String(other === button));
          });
          apply();
        });
      });
      document.getElementById("filter").addEventListener("input", function (event) {
        state.query = event.target.value.trim().toLowerCase();
        apply();
      });
      document.getElementById("findings-only").addEventListener("change", function (event) {
        state.findings = event.target.checked;
        apply();
      });
      apply();
      select(location.hash.slice(1), false);

      // Panes: the list collapses, and both dividers drag or step with the arrow keys. Sizes are kept
      // in this browser only; double-click a divider to restore its default.
      var app = document.querySelector(".app");
      var defaults = { left: 236, right: 420 };
      var panes = { left: defaults.left, right: defaults.right, collapsed: false };
      try {
        var saved = JSON.parse(localStorage.getItem("gloss.panes") || "null");
        if (saved) Object.keys(panes).forEach(function (key) { if (key in saved) panes[key] = saved[key]; });
      } catch (error) {}
      var expand = document.getElementById("expand-left");
      function clamp(side, value) {
        var width = app.clientWidth;
        return side === "left" ? Math.max(160, Math.min(value, Math.min(520, width * 0.4)))
          : Math.max(300, Math.min(value, Math.max(300, width * 0.62)));
      }
      function layoutPanes(persist) {
        panes.left = clamp("left", panes.left);
        panes.right = clamp("right", panes.right);
        app.style.setProperty("--left", panes.left + "px");
        app.style.setProperty("--right", panes.right + "px");
        app.classList.toggle("left-collapsed", panes.collapsed);
        expand.hidden = !panes.collapsed;
        if (persist) { try { localStorage.setItem("gloss.panes", JSON.stringify(panes)); } catch (error) {} }
      }
      layoutPanes(false);
      document.getElementById("collapse-left").addEventListener("click", function () { panes.collapsed = true; layoutPanes(true); expand.focus(); });
      expand.addEventListener("click", function () { panes.collapsed = false; layoutPanes(true); });
      document.querySelectorAll(".splitter").forEach(function (splitter) {
        var side = splitter.dataset.split;
        splitter.addEventListener("pointerdown", function (event) {
          event.preventDefault();
          splitter.setPointerCapture(event.pointerId);
          splitter.classList.add("dragging");
          app.classList.add("resizing");
        });
        splitter.addEventListener("pointermove", function (event) {
          if (!splitter.hasPointerCapture(event.pointerId)) return;
          var box = app.getBoundingClientRect();
          panes[side] = side === "left" ? event.clientX - box.left : box.right - event.clientX;
          layoutPanes(false);
        });
        function finish(event) {
          if (!splitter.hasPointerCapture(event.pointerId)) return;
          splitter.releasePointerCapture(event.pointerId);
          splitter.classList.remove("dragging");
          app.classList.remove("resizing");
          layoutPanes(true);
        }
        splitter.addEventListener("pointerup", finish);
        splitter.addEventListener("pointercancel", finish);
        splitter.addEventListener("dblclick", function () { panes[side] = defaults[side]; layoutPanes(true); });
        splitter.addEventListener("keydown", function (event) {
          var step = event.shiftKey ? 64 : 16;
          var grow = side === "left" ? "ArrowRight" : "ArrowLeft";
          var shrink = side === "left" ? "ArrowLeft" : "ArrowRight";
          if (event.key === grow) panes[side] += step;
          else if (event.key === shrink) panes[side] -= step;
          else return;
          event.preventDefault();
          layoutPanes(true);
        });
      });
      window.addEventListener("resize", function () { layoutPanes(false); });

      var mapBody = document.getElementById("map-body");
      mapBody.addEventListener("change", function () {
        document.querySelectorAll("[data-map]").forEach(function (variant) {
          variant.hidden = (variant.dataset.map === "all") !== mapBody.checked;
        });
        light(shownView ? shownView.dataset.root || null : null);
      });
    })();
    """
}
