import Foundation
import GlossCore
import GlossMap

/// Renders an ``Interface`` as one self-contained HTML page that discloses the system a level at a time.
///
/// The page opens on the overview, the types other code reaches first. From there a reader opens the
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
        let atlas = Atlas(interface)
        let scopes = atlas.mapScopes()
        let scopesOf = atlas.levelsDrawing(scopes)
        let owed = zip(interface.contracts, interface.assessments).filter { $0.1.requiresDoc }.map(\.0)
        let findings = interface.assessments.reduce(0) { $0 + $1.findings.count }
        func pressed(_ min: Int) -> String { String(min == Atlas.defaultMinimumRank) }
        var html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="claude:viewport-fit-sides" content="cover">
        <title>\(escape(title)) interface</title>
        <script>document.documentElement.classList.add("js");</script>
        <style>\(style)\(moduleStyle)</style>
        </head>
        <body>
        <header class="toolbar">
        <button type="button" class="tool-button" id="toggle-list" aria-controls="list" aria-expanded="true" aria-label="List" title="Hide the list"><svg viewBox="0 0 18 14" width="18" height="14" aria-hidden="true"><rect x="0.75" y="0.75" width="16.5" height="12.5" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6.5 1v12" stroke="currentColor" stroke-width="1.5"/><path class="fill" d="M1.5 3a1.5 1.5 0 0 1 1.5-1.5h3v11h-3a1.5 1.5 0 0 1-1.5-1.5z"/></svg></button>
        <h1><span class="name">\(escape(title))</span><span class="eyebrow">Interface</span></h1>
        <div class="seg" role="group" aria-label="Access level">
        <button type="button" data-min="3" aria-pressed="\(pressed(3))">Public</button>
        <button type="button" data-min="1" aria-pressed="\(pressed(1))">Internal</button>
        <button type="button" data-min="0" aria-pressed="\(pressed(0))">All</button>
        </div>
        </header>
        <div class="app">
        <aside class="sidebar" id="list" aria-label="Types">
        <dl class="stats">
        <div><dt>Declarations</dt><dd>\(interface.contracts.filter { Contract.rank($0.access) >= 1 }.count)</dd></div>
        <div><dt>Public</dt><dd>\(interface.contracts.filter { Contract.rank($0.access) >= 3 }.count)</dd></div>
        <div><dt>Documented</dt><dd>\(owed.filter(\.isDocumented).count)<span class="of">/\(owed.count)</span></dd></div>
        <div><dt>Findings</dt><dd class="\(findings == 0 ? "clean" : "dirty")">\(findings)</dd></div>
        </dl>
        <div class="controls">
        <input type="search" id="filter" placeholder="Find a type or member" aria-label="Find a type or member" autocomplete="off">
        <label class="check"><input type="checkbox" id="findings-only"> Only types with findings</label>
        </div>
        <details class="index" open><summary>Browse</summary><nav>
        <a class="top-link" href="#overview" data-link="overview">Overview</a>

        """
        for module in atlas.modules {
            let dot = atlas.moduleColors[module].map { "<span class=\"mdot m\($0)\"></span>" } ?? ""
            html += "<h2><a href=\"#\(moduleAnchor(module))\" data-link=\"\(moduleAnchor(module))\">\(dot)\(escape(module))</a></h2><ul>"
            for node in atlas.nodes where node.module == module {
                let group = atlas.group(node.id)
                let rank = atlas.rank(of: node)
                let search = ([node.name] + group.members.map(\.name)).joined(separator: " ").lowercased()
                let dot = group.findingCount > 0 ? "<span class=\"dot\" title=\"\(group.findingCount) findings\"></span>" : ""
                html += "<li class=\"depth-\(atlas.depth(node))\" data-group data-rank=\"\(rank)\" data-findings=\"\(group.findingCount)\" data-search=\"\(escape(search))\">"
                html += "<a href=\"#\(anchor(node.id, in: atlas))\" data-link=\"\(anchor(node.id, in: atlas))\">\(escape(atlas.shortLabel(node)))</a>\(dot)<span class=\"count\">\(group.members.count)</span></li>"
            }
            html += "</ul>\n"
        }
        html += "</nav></details>\n</aside>\n"
        html += "<div class=\"splitter split-left\" role=\"separator\" aria-orientation=\"vertical\" aria-label=\"Resize the list\" tabindex=\"0\" data-split=\"left\"></div>\n"
        html += "<aside class=\"panel\" aria-label=\"Details\">\n<p class=\"preview-note\" id=\"preview-note\" hidden>Previewing. Click it to keep it here.</p>\n"
        html += overview(atlas, scope: scopes.first?.id ?? "")
        html += scopeViews(atlas, scopes: scopes)
        html += "<section class=\"view\" id=\"type\" data-view data-root=\"\" aria-live=\"polite\"></section>\n"
        html += "<script type=\"application/json\" id=\"page-data\">\(encode(pageData(atlas, scopesOf: scopesOf)))</script>\n"
        html += """
        <footer><p>Generated by gloss from \(interface.files.count) file\(interface.files.count == 1 ? "" : "s"). The same data is available as JSON with <code>gloss interface --json</code>.</p></footer>
        </aside>

        """
        html += "<div class=\"splitter split-detail\" role=\"separator\" aria-orientation=\"vertical\" aria-label=\"Resize the details\" tabindex=\"0\" data-split=\"detail\"></div>\n"
        html += stage(atlas, scopes: scopes)
        html += """
        </div>
        <script>\(script)</script>
        </body>
        </html>

        """
        return html
    }

    // MARK: Anchors

    /// The anchor of a node's view, made of characters every host keeps in a link fragment.
    ///
    /// - Parameters:
    ///   - id: A node id.
    ///   - atlas: The arranged interface.
    /// - Returns: `g-Module-Type-Nested`, `g-Module-top` for file scope, or `map` for an unknown id.
    static func anchor(_ id: String, in atlas: Atlas) -> String {
        guard let node = atlas.byID[id] else { return "map" }
        return "g-" + Atlas.safeID(node.module) + "-" + (node.name.isEmpty ? "top" : Atlas.safeID(node.name))
    }

    // MARK: Overview

    private static func overview(_ atlas: Atlas, scope: String) -> String {
        var html = """
        <section class="view" id="overview" data-view data-root="" data-scope="\(scope)">
        <header class="view-head"><h2>Overview</h2></header>

        """
        for module in atlas.modules {
            let entries = atlas.entryPoints(in: module)
            guard !entries.isEmpty else { continue }
            html += "<section class=\"block\"><h3>\(escape(module))</h3><div class=\"cards\">"
            for node in entries {
                let group = atlas.group(node.id)
                let summary = group.head?.summary.map(Wording.firstSentence)
                let operations = group.members.filter { Wording.isCallable($0.keyword) && Contract.rank($0.access) >= 1 && !$0.isOverride }.count
                let users = atlas.users(of: node.id)
                html += "<a class=\"card\" href=\"#\(anchor(node.id, in: atlas))\">"
                html += "<span class=\"card-kind\">\(escape(Wording.kind(of: node)))</span>"
                html += "<code class=\"card-name\">\(escape(atlas.label(node)))</code>"
                html += summary.map { "<span class=\"card-summary\">\(inline($0))</span>" } ?? ""
                var facts: [String] = []
                if operations > 0 { facts.append("\(operations) operation\(operations == 1 ? "" : "s")") }
                if !users.isEmpty { facts.append("used by " + users.map(atlas.label).joined(separator: ", ")) }
                if !facts.isEmpty { html += "<span class=\"card-facts\">\(escape(facts.joined(separator: " · ")))</span>" }
                html += "</a>"
            }
            html += "</div></section>\n"
        }
        return html + "</section>\n"
    }

    // MARK: Members

    /// A link to a node's view, filtered with the access level like everything else on the page.
    ///
    /// - Parameters:
    ///   - node: The node to link to.
    ///   - atlas: The arranged interface, for the label and anchor.
    /// - Returns: An `<a>` element; file scope counts as public so the filter never hides an entry point.
    static func chip(_ node: Graph.Node, atlas: Atlas) -> String {
        let dirty = atlas.group(node.id).findingCount > 0
        let access = node.keyword == "file" ? "public" : node.access
        return "<a class=\"chip\(dirty ? " dirty" : "")\" href=\"#\(anchor(node.id, in: atlas))\" data-id=\"\(escape(node.id))\" data-root=\"\(escape(node.root))\" data-access=\"\(access)\">\(escape(atlas.label(node)))</a>"
    }

    // MARK: Figures

    /// Draws a placed figure as inline SVG: links to each node's view, a tooltip on each edge.
    ///
    /// - Parameters:
    ///   - layout: The placed figure.
    ///   - atlas: The arranged interface, for each box's link.
    ///   - label: The accessible name of the figure.
    ///   - marker: A suffix that makes this figure's arrowhead id unique on the page.
    /// - Returns: An `<svg>` element.
    static func svg(_ layout: GraphLayout, atlas: Atlas, label: String, marker: String) -> String {
        let format = GraphLayout.format
        let arrow = "arrow-" + marker
        var html = "<svg class=\"graph\" viewBox=\"0 0 \(format(layout.width)) \(format(layout.height))\" width=\"\(format(layout.width))\" height=\"\(format(layout.height))\" role=\"img\" aria-label=\"\(escape(label))\">"
        html += "<defs><marker id=\"\(arrow)\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path class=\"arrowhead\" d=\"M0,1 L9,5 L0,9 z\"/></marker></defs>"
        if !layout.lanes.isEmpty {
            html += "<g class=\"lanes\">"
            for lane in layout.lanes {
                let color = atlas.moduleColors[lane.name].map { " m\($0)" } ?? ""
                html += "<g class=\"lane\(color)\(lane.isEmphasized ? " current" : "")\"><rect x=\"\(format(lane.x))\" y=\"\(format(lane.y))\" width=\"\(format(lane.width))\" height=\"\(format(lane.height))\" rx=\"10\"/>"
                html += "<text class=\"lane-label\" x=\"\(format(lane.x + 12))\" y=\"\(format(lane.y + 19))\">\(escape(lane.name.uppercased()))</text></g>"
            }
            html += "</g>"
        }
        html += "<g class=\"edges\">"
        for curve in layout.curves {
            let end = curve.reversed ? "marker-start" : "marker-end"
            html += "<path class=\"edge\(curve.link.dashed ? " body" : "")\" d=\"\(curve.path)\" data-from=\"\(escape(curve.link.from))\" data-to=\"\(escape(curve.link.to))\" \(end)=\"url(#\(arrow))\"><title>\(escape(curve.link.title))</title></path>"
        }
        html += "</g><g class=\"nodes\">"
        for box in layout.boxes {
            let item = box.item
            let color: String = switch item.unit {
            case .module(let module), .folder(let module, _): atlas.moduleColors[module].map { " m\($0)" } ?? ""
            case .type: ""
            }
            html += "<a class=\"node \(classes(item.flags))\(color)\" href=\"#\(link(item.unit, atlas: atlas))\" data-id=\"\(escape(item.id))\">"
            html += "<rect x=\"\(format(box.x))\" y=\"\(format(box.y))\" width=\"\(format(box.width))\" height=\"\(format(GraphLayout.boxHeight))\" rx=\"5\"/>"
            html += "<text class=\"label\" x=\"\(format(box.x + 12))\" y=\"\(format(box.y + 16))\">\(escape(item.label))</text>"
            html += "<text class=\"detail\" x=\"\(format(box.x + 12))\" y=\"\(format(box.y + 30))\">\(escape(item.detail))</text></a>"
        }
        return html + "</g></svg>"
    }

    /// The CSS classes that draw a box's flags.
    ///
    /// - Parameter flags: The box's flags.
    /// - Returns: Space-separated class names, in a fixed order.
    static func classes(_ flags: GraphLayout.Flags) -> String {
        let names: [(GraphLayout.Flags, String)] = [(.dirty, "dirty"), (.private, "private"), (.scope, "scope"), (.boundary, "boundary")]
        return names.filter { flags.contains($0.0) }.map(\.1).joined(separator: " ")
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

    /// Each module color as CSS variables for both themes, and the classes that apply them: a lane's
    /// tint and name, the focused lane's outline, module and folder boxes, and the sidebar's dots.
    /// Generated from ``GlossMap/ModulePalette`` so the page and the app color a module alike.
    static let moduleStyle: String = {
        let hex = { (value: Int) in "#" + String(value, radix: 16, uppercase: true).leftPadded(to: 6) }
        let colors = ModulePalette.colors.enumerated()
        let light = colors.map { "--m\($0.offset)-tint: \(hex($0.element.tintLight)); --m\($0.offset)-ink: \(hex($0.element.inkLight));" }.joined(separator: " ")
        let dark = colors.map { "--m\($0.offset)-tint: \(hex($0.element.tintDark)); --m\($0.offset)-ink: \(hex($0.element.inkDark));" }.joined(separator: " ")
        var css = "\n    :root { \(light) }"
        css += "\n    @media (prefers-color-scheme: dark) { :root:not([data-theme=\"light\"]) { \(dark) } }"
        css += "\n    :root[data-theme=\"dark\"] { \(dark) }"
        for (slot, _) in colors {
            css += "\n    .graph .lane.m\(slot) rect, .graph .node.scope.m\(slot) rect { fill: var(--m\(slot)-tint); }"
            css += "\n    .graph .lane.m\(slot) .lane-label, .mdot.m\(slot) { fill: var(--m\(slot)-ink); background: var(--m\(slot)-ink); }"
            css += "\n    .graph .lane.current.m\(slot) rect { stroke: var(--m\(slot)-ink); stroke-width: 1.5; }"
        }
        return css + "\n"
    }()

    private static let style = """
    /* Layout: three panes on one screen. The list on the left, the text of one type in the middle, and
       the map on the right, taking whatever width is left. Hover previews a type in the details pane;
       selecting keeps it there, so the map never moves and nothing covers it. */
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
    body { margin: 0; background: var(--bg); color: var(--ink); font: 14px/1.5 var(--font-ui);
      display: grid; grid-template-rows: auto minmax(0, 1fr); }
    a { color: var(--accent); }
    code { font-family: var(--font-code); font-size: 0.92em; }
    :focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
    summary { cursor: pointer; }
    .eyebrow { margin: 0; font: 600 11px/1.3 var(--font-ui); letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); }
    .term, .role { font: 600 10.5px/1.4 var(--font-ui); letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }

    /* The toolbar holds what applies to every pane, and the list's toggle, which never moves. */
    .toolbar { display: flex; align-items: center; gap: 12px; min-height: 46px; padding-block: 7px; background: var(--panel); border-bottom: 1px solid var(--rule);
      padding-left: max(10px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
    .tool-button { display: inline-grid; place-items: center; width: 34px; height: 30px; padding: 0; color: var(--muted); background: none; border: 1px solid transparent; border-radius: 6px; cursor: pointer; }
    .tool-button:hover { color: var(--accent); background: var(--surface); border-color: var(--rule); }
    .tool-button .fill { fill: none; }
    .tool-button[aria-expanded="true"] { color: var(--accent); }
    .tool-button[aria-expanded="true"] .fill { fill: currentColor; opacity: 0.35; }
    .toolbar h1 { margin: 0; display: flex; align-items: baseline; gap: 10px; min-width: 0; }
    .toolbar h1 .name { font: italic 400 1.4rem/1 var(--font-gloss); letter-spacing: -0.01em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .toolbar .seg { margin-left: auto; flex: none; }
    .toolbar .seg button { flex: none; padding: 7px 12px; }

    .app { --left: 236px; --detail: 420px; display: grid; grid-template-columns: var(--left) 7px var(--detail) 7px minmax(0, 1fr); grid-template-rows: 100%; min-height: 0; }
    .app.left-collapsed { grid-template-columns: 0 0 var(--detail) 7px minmax(0, 1fr); }
    .left-collapsed .sidebar, .left-collapsed .split-left { display: none; }
    .sidebar { grid-column: 1; } .split-left { grid-column: 2; } .panel { grid-column: 3; } .split-detail { grid-column: 4; } .stage { grid-column: 5; }
    .sidebar, .stage, .panel { grid-row: 1; height: 100%; overflow: auto; min-width: 0; }
    .splitter { grid-row: 1; position: relative; cursor: col-resize; touch-action: none; background: transparent; }
    .splitter::after { content: ""; position: absolute; top: 0; bottom: 0; left: 3px; width: 1px; background: var(--rule); transition: background 0.15s; }
    .splitter:hover::after, .splitter:focus-visible::after, .splitter.dragging::after { left: 2px; width: 3px; background: var(--accent); }
    .splitter:focus-visible { outline: none; }
    .app.resizing { cursor: col-resize; user-select: none; }
    .stage-top { display: flex; align-items: center; gap: 10px; }
    .zoom { margin-left: auto; display: inline-flex; border: 1px solid var(--rule); border-radius: 6px; overflow: hidden; background: var(--surface); }
    .zoom button { font: 600 16px/1 var(--font-ui); width: 34px; height: 30px; color: var(--accent); background: none; border: 0; cursor: pointer; }
    .zoom button + button { border-left: 1px solid var(--rule); }
    .zoom button:hover:not(:disabled) { background: var(--accent-soft); }
    .zoom button:disabled { color: var(--faint); cursor: default; }
    .crumb-button { font: inherit; color: var(--accent); background: none; border: 0; padding: 0; cursor: pointer; }
    .sidebar { background: var(--panel); display: flex; flex-direction: column; gap: 18px;
      padding-block: 22px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: 14px; }
    .stage { display: grid; gap: 14px; align-content: start; padding-block: 22px 32px;
      padding-left: 28px; padding-right: max(28px, env(safe-area-inset-right, 0px)); }
    .panel { background: var(--surface); display: grid; gap: 24px; align-content: start; padding-block: 22px 40px; padding-inline: 26px; }

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
    .graph .lane rect { fill: var(--panel); stroke: var(--rule); }
    .graph .lane-label { font: 600 10px var(--font-ui); letter-spacing: 0.08em; fill: var(--muted); }
    .mdot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; margin-right: 6px; vertical-align: 1px; }
    .graph .node { transition: opacity 0.15s; }
    .graph .node rect { fill: var(--surface); stroke: var(--line); stroke-width: 1; }
    .graph .node .label { font: 12px var(--font-code); fill: var(--ink); }
    .graph .node .detail { font: 10.5px var(--font-ui); fill: var(--muted); }
    .graph .node:hover rect, .graph .node:focus-visible rect { stroke: var(--accent); stroke-width: 1.5; }
    .graph .node.dirty rect { stroke: var(--danger); }
    .graph .node.scope rect { fill: var(--panel); stroke-width: 1.5; }
    .graph .node.boundary rect { stroke-dasharray: 5 3; }
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
    .reveal { color: var(--accent); font-size: 13px; }
    .reveal::after { content: " ▸"; }
    details[open] > summary .reveal::after { content: " ▾"; }
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
    pre.code { margin: 0; padding: 10px 12px; overflow-x: auto; background: var(--panel); border: 1px solid var(--rule); border-radius: 6px;
      font: 12.5px/1.5 var(--font-code); color: var(--ink); }
    pre.code code { font: inherit; }
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

    @media (max-width: 1180px) { .stage { padding-left: 18px; padding-right: max(18px, env(safe-area-inset-right, 0px)); } }
    @media (max-width: 900px) {
      html, body { height: auto; }
      body { display: block; }
      .app { display: block; height: auto; }
      .sidebar, .stage, .panel { height: auto; overflow: visible; }
      .splitter, .tool-button { display: none !important; }
      .toolbar { padding-left: max(16px, env(safe-area-inset-left, 0px)); }
      .left-collapsed .sidebar { display: flex; }
      .sidebar { border-right: 0; border-bottom: 1px solid var(--rule); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .index > summary { display: list-item; font-weight: 600; color: var(--accent); }
      .stage { border-top: 1px solid var(--rule); padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .panel { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
      .preview-note { display: none !important; }
      .flow .band { grid-template-columns: minmax(0, 1fr); }
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
      var selected = "overview";
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
      // A note is prose, or fenced code kept whole by the model, drawn as a block with its fences dropped.
      function paragraph(text, kind) {
        if (text.indexOf("```") === 0) {
          var lines = text.split("\\n");
          var closed = lines.length > 1 && lines[lines.length - 1].trim().indexOf("```") === 0;
          return '<pre class="code"><code>' + esc(lines.slice(1, closed ? -1 : lines.length).join("\\n")) + "</code></pre>";
        }
        return "<p" + (kind ? ' class="' + kind + '"' : "") + ">" + inline(text) + "</p>";
      }
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
        var list = ROLES.filter(function (role, bit) { return mask & (1 << bit); }).map(function (role) { return WORDS[role]; });
        if (list.length < 3) return list.join(" and ");
        return list.slice(0, -1).join(", ") + ", and " + list[list.length - 1];
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
        (contract.no || []).forEach(function (text) { html += paragraph(text, "note"); });
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
          html += '<div class="band"><span class="role">inside</span><div class="chips">' + capped(inside.map(function (pair) { return chip(pair[0], { dashed: true }); })) + "</div></div>";
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
          var more = (head.no || []).map(function (text) { return paragraph(text); }).join("")
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
          typeView.dataset.node = node.id;
          typeView.dataset.scopes = (node.sc || []).join(" ");
          rendered.id = id;
          applyRows(typeView);
        }
        return typeView;
      }
      function known(id) { return !!views[id] || byAnchor[id] !== undefined; }

      // Focus: the selected type with only what uses it, above, and what it depends on, below. It is
      // laid out here because it follows the selection; selecting a neighbor re-centers it.
      var focusFrom = null;
      var focusIndex = null;
      function boxWidth(label, detail) { return Math.max(label.length * 7.3, detail.length * 6) + 24; }
      function rowsOf(items, limit) {
        var rows = [[]];
        var used = 0;
        items.forEach(function (item) {
          var needed = item.w + (rows[rows.length - 1].length ? 18 : 0);
          if (used + needed > limit && rows[rows.length - 1].length) { rows.push([]); used = 0; needed = item.w; }
          used += needed;
          rows[rows.length - 1].push(item);
        });
        return rows[0].length ? rows : [];
      }
      function renderFocus(position) {
        focusIndex = position;
        var node = data.nodes[position];
        var keep = function (pair) { return rank[data.nodes[pair[0]].x] >= state.min; };
        var signatureFirst = function (a, b) { return (a[1] === BODY) - (b[1] === BODY); };
        var incoming = (node.i || []).filter(keep).sort(signatureFirst);
        var outgoing = (node.o || []).filter(keep).sort(signatureFirst);
        var cap = 24;
        var hidden = Math.max(0, incoming.length - cap) + Math.max(0, outgoing.length - cap);
        var item = function (pair) {
          var other = data.nodes[pair[0]];
          var detail = words(pair[1]) + (other.m !== node.m ? " · " + other.m : "");
          return { node: other, detail: detail, body: pair[1] === BODY, w: boxWidth(other.l, detail) };
        };
        var above = rowsOf(incoming.slice(0, cap).map(item), 900);
        var below = rowsOf(outgoing.slice(0, cap).map(item), 900);
        var center = { node: node, detail: node.k, w: boxWidth(node.l, node.k) };
        var rowWidth = function (row) { return row.reduce(function (sum, box) { return sum + box.w; }, 0) + 18 * Math.max(row.length - 1, 0); };
        var width = Math.max(center.w, Math.max.apply(null, above.concat(below).map(rowWidth).concat([0]))) + 12;
        var y = 6;
        var place = function (row) {
          var x = 6 + (width - 12 - rowWidth(row)) / 2;
          row.forEach(function (box) { box.x = x; box.y = y; x += box.w + 18; });
          y += 38 + 14;
        };
        above.forEach(place);
        if (above.length) y += 40;
        place([center]);
        if (below.length) y += 40;
        below.forEach(place);
        var height = y - 14 + 6;
        var f = function (value) { return Math.round(value * 10) / 10; };
        var curve = function (x1, y1, x2, y2) { var mid = (y1 + y2) / 2; return "M" + f(x1) + "," + f(y1) + " C" + f(x1) + "," + f(mid) + " " + f(x2) + "," + f(mid) + " " + f(x2) + "," + f(y2); };
        var flatAbove = [].concat.apply([], above);
        var flatBelow = [].concat.apply([], below);
        var spread = function (index, count) { return center.x + (index + 1) * center.w / (count + 1); };
        var edges = flatAbove.map(function (box, index) {
          return '<path class="edge' + (box.body ? " body" : "") + '" d="' + curve(box.x + box.w / 2, box.y + 38, spread(index, flatAbove.length), center.y)
            + '" data-from="' + esc(box.node.id) + '" data-to="' + esc(node.id) + '" marker-end="url(#arrow-focus)"><title>' + esc(box.node.l + " " + box.detail + " " + node.l) + "</title></path>";
        }).concat(flatBelow.map(function (box, index) {
          return '<path class="edge' + (box.body ? " body" : "") + '" d="' + curve(spread(index, flatBelow.length), center.y + 38, box.x + box.w / 2, box.y)
            + '" data-from="' + esc(node.id) + '" data-to="' + esc(box.node.id) + '" marker-end="url(#arrow-focus)"><title>' + esc(node.l + " " + box.detail + " " + box.node.l) + "</title></path>";
        }));
        var boxes = flatAbove.concat([center], flatBelow).map(function (box) {
          var classes = (box === center ? " current" : "") + (box.node.f ? " dirty" : "") + (rank[box.node.x] === 0 ? " private" : "");
          return '<a class="node' + classes + '" href="#' + box.node.a + '" data-id="' + esc(box.node.id) + '"><rect x="' + f(box.x) + '" y="' + f(box.y)
            + '" width="' + f(box.w) + '" height="38" rx="5"/><text class="label" x="' + f(box.x + 12) + '" y="' + f(box.y + 16) + '">' + esc(box.node.l)
            + '</text><text class="detail" x="' + f(box.x + 12) + '" y="' + f(box.y + 30) + '">' + esc(box.detail) + "</text></a>";
        });
        var map = scopeMaps.focus;
        map.querySelector(".figure").innerHTML = '<svg class="graph" viewBox="0 0 ' + f(width) + " " + f(height) + '" width="' + f(width) + '" height="' + f(height)
          + '" role="img" aria-label="' + esc(node.l) + ' and its neighbors"><defs><marker id="arrow-focus" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="arrowhead" d="M0,1 L9,5 L0,9 z"/></marker></defs><g class="edges">'
          + edges.join("") + '</g><g class="nodes">' + boxes.join("") + "</g></svg>";
        var from = focusFrom && scopeMaps[focusFrom] ? scopeMaps[focusFrom].dataset.label : "Map";
        map.querySelector(".crumbs").innerHTML = '<button type="button" class="crumb-button" data-zoom-out>' + esc(from) + '</button><span class="sep">›</span><span aria-current="page">' + esc(node.l) + " and its neighbors</span>";
        var users = incoming.length ? (incoming.length === 1 ? "1 type uses it" : incoming.length + " types use it") : "Nothing uses it";
        var needs = outgoing.length ? "it depends on " + outgoing.length : "it depends on nothing scanned";
        map.querySelector(".caption").textContent = users + "; " + needs + (hidden ? ". " + hidden + " more are not drawn; the panel lists them all." : ".");
      }

      // Zoom steps one level at a time: in from the module overview to a module, a folder, and the
      // selected type's focus; out the same way back.
      var zoomIn = document.getElementById("zoom-in");
      var zoomOut = document.getElementById("zoom-out");
      // The focus zooms out to the level it was entered from, unless walking its neighbors has moved
      // it to a type that level does not draw; then to the narrowest level that draws it.
      function parentOf(id) {
        if (id === "focus") {
          var drawing = (typeView.dataset.scopes || "").split(" ").filter(Boolean);
          if (!focusFrom || !drawing.length || drawing.indexOf(focusFrom) >= 0) return focusFrom;
          return drawing[drawing.length - 1];
        }
        return scopeMaps[id] && scopeMaps[id].dataset.parent || null;
      }
      function isAncestor(wider, narrower) {
        for (var step = parentOf(narrower); step; step = parentOf(step)) { if (step === wider) return true; }
        return false;
      }
      function zoomInTarget() {
        var view = mount(selected);
        if (view === typeView) {
          if (currentScope === "focus") return null;
          var ladder = (view.dataset.scopes || "").split(" ").filter(Boolean).concat(["focus"]);
          var at = ladder.indexOf(currentScope);
          if (at >= 0) return ladder[at + 1];
          for (var index = 0; index < ladder.length - 1; index++) { if (isAncestor(currentScope, ladder[index])) return ladder[index]; }
          return "focus";
        }
        var own = view.dataset.scope;
        return own && own !== currentScope && isAncestor(currentScope, own) ? own : null;
      }
      function zoomOutTarget() { return parentOf(currentScope); }
      function updateZoom() {
        zoomIn.disabled = !zoomInTarget();
        zoomOut.disabled = !zoomOutTarget();
        zoomIn.title = zoomIn.disabled ? "Select a type to zoom in on it" : "Zoom in to a narrower level, down to the selected type and its neighbors (+)";
      }
      function zoom(target) {
        if (!target) return;
        showScope(target);
        light(shownView.dataset.root || null, shownView.dataset.node);
      }
      zoomIn.addEventListener("click", function () { zoom(zoomInTarget()); });
      zoomOut.addEventListener("click", function () { zoom(zoomOutTarget()); });
      stage.addEventListener("click", function (event) {
        if (event.target.closest("[data-zoom-out]")) zoom(zoomOutTarget());
      });
      document.addEventListener("keydown", function (event) {
        if (event.metaKey || event.ctrlKey || event.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)) return;
        if (event.key === "+" || event.key === "=") { zoom(zoomInTarget()); event.preventDefault(); }
        else if (event.key === "-" || event.key === "_") { zoom(zoomOutTarget()); event.preventDefault(); }
      });

      // Lights a type on the map: its box, its edges, and its neighbors; everything else dims.
      function light(root, exact) {
        document.querySelectorAll(".graph").forEach(function (graph) {
          var target = exact && graph.querySelector('.node[data-id="' + CSS.escape(exact) + '"]');
          if (target) root = exact;
          else target = root && graph.querySelector('.node[data-id="' + CSS.escape(root) + '"]');
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
        light(shownView.dataset.root || null, shownView.dataset.node);
        document.querySelectorAll(".index a.previewed").forEach(function (link) { link.classList.remove("previewed"); });
      }
      // The selection decides the map level: a module or folder view draws its own level; a type keeps
      // the current level when that level draws it, and otherwise moves to the widest one that does.
      function showScope(id) {
        if (id === "focus") {
          var position = byAnchor[selected];
          if (position === undefined) return;
          if (currentScope !== "focus") focusFrom = currentScope;
          renderFocus(position);
        }
        if (!scopeMaps[id]) return;
        currentScope = id;
        Object.keys(scopeMaps).forEach(function (key) { scopeMaps[key].hidden = key !== id; });
        updateZoom();
      }
      function scopeFor(view) {
        if (view.dataset.scope) return view.dataset.scope;
        if (currentScope === "focus" && view === typeView) return "focus";
        var list = (view.dataset.scopes || "").split(" ").filter(Boolean);
        if (!list.length || list.indexOf(currentScope) >= 0) return currentScope;
        return list[0];
      }
      function select(id, reveal) {
        selected = known(id) ? id : "overview";
        previewing = null;
        note.hidden = true;
        showScope(scopeFor(mount(selected)));
        display(selected);
        document.querySelectorAll("[data-link]").forEach(function (link) {
          link.setAttribute("aria-current", String(link.dataset.link === selected));
        });
        updateZoom();
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
        if (currentScope === "focus" && focusIndex !== null) renderFocus(focusIndex);
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
      var defaults = { left: 236, detail: 420 };
      var panes = { left: defaults.left, detail: defaults.detail, collapsed: false };
      try {
        var saved = JSON.parse(localStorage.getItem("gloss.panes") || "null");
        if (saved) Object.keys(panes).forEach(function (key) { if (key in saved) panes[key] = saved[key]; });
      } catch (error) {}
      var toggle = document.getElementById("toggle-list");
      // The map takes what the list and the details leave, and always keeps at least 320px.
      function clamp(side, value) {
        var width = app.clientWidth;
        if (side === "left") return Math.max(160, Math.min(value, Math.min(520, width * 0.4)));
        var list = panes.collapsed ? 0 : panes.left + 7;
        return Math.max(300, Math.min(value, width * 0.6, width - list - 7 - 320));
      }
      function layoutPanes(persist) {
        panes.left = clamp("left", panes.left);
        panes.detail = clamp("detail", panes.detail);
        app.style.setProperty("--left", panes.left + "px");
        app.style.setProperty("--detail", panes.detail + "px");
        app.classList.toggle("left-collapsed", panes.collapsed);
        toggle.setAttribute("aria-expanded", String(!panes.collapsed));
        toggle.title = panes.collapsed ? "Show the list" : "Hide the list";
        if (persist) { try { localStorage.setItem("gloss.panes", JSON.stringify(panes)); } catch (error) {} }
      }
      layoutPanes(false);
      toggle.addEventListener("click", function () { panes.collapsed = !panes.collapsed; layoutPanes(true); });
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
          var start = (side === "left" ? app : panel).getBoundingClientRect().left;
          panes[side] = event.clientX - start;
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
          if (event.key === "ArrowRight") panes[side] += step;
          else if (event.key === "ArrowLeft") panes[side] -= step;
          else return;
          event.preventDefault();
          layoutPanes(true);
        });
      });
      window.addEventListener("resize", function () { layoutPanes(false); });

    })();
    """
}

extension String {
    /// The string with zeros in front until it is a given length, for fixed-width hex.
    ///
    /// - Parameter length: The length to pad to; a longer string is returned whole.
    /// - Returns: The padded string.
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
