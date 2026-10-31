import Foundation

/// The levels the dependency map can be read at: every type, every module, one module, or one folder.
///
/// A large codebase cannot be drawn as one graph a reader can follow, so the map opens at the most
/// detailed level that fits ``InterfacePage/mapBudget`` boxes, and each level draws what lies outside
/// it as dashed boundary boxes a reader can step into.
extension InterfacePage {
    /// The most boxes one level of the map draws; the rest are listed beneath it.
    static let mapBudget = 30

    /// One level of the map: which boxes it draws, and how every root type folds into them.
    struct MapScope {
        /// What a root type is drawn as at this level.
        enum Unit: Hashable {
            case type(String)
            case module(String)
            case folder(String, String)
        }

        /// The scope's id, used by panel views to name the map level they belong to.
        var id: String
        /// The panel view that selecting this level shows.
        var view: String
        /// The path from the widest level to this one, each step with the view it selects.
        var crumbs: [(label: String, view: String)]
        /// Folds a root type into the box this level draws for it.
        var unit: (Graph.Node) -> Unit
        /// Whether a box belongs to this level, rather than standing at its boundary.
        var isInside: (Unit) -> Bool
    }

    /// Every level of the map for an interface, the default one first.
    ///
    /// - Parameter site: The arranged interface.
    /// - Returns: The levels, in order: the default, then the module overview, each module, and each folder.
    ///
    /// All types are drawn at once when they fit the budget. Otherwise the default is the module
    /// overview, or the only module when there is just one. A module that is over the budget and spread
    /// across several folders is drawn as folders, and each of those folders gets a level of its own.
    static func mapScopes(_ site: Site) -> [MapScope] {
        let roots = site.rootIDs.compactMap { site.byID[$0] }
        let multiModule = site.modules.count > 1
        let fitsAll = roots.count <= mapBudget
        let rootView = "start"
        let rootCrumb = fitsAll ? "All types" : multiModule ? "All modules" : site.modules.first ?? "Module"
        var scopes: [MapScope] = []

        if fitsAll {
            scopes.append(MapScope(id: "s-types", view: rootView, crumbs: [(rootCrumb, rootView)],
                                   unit: { .type($0.id) }, isInside: { _ in true }))
        }
        if multiModule {
            let view = fitsAll ? "modules" : rootView
            let crumbs = fitsAll ? [(rootCrumb, rootView), ("Modules", "modules")] : [(rootCrumb, rootView)]
            scopes.append(MapScope(id: "s-modules", view: view, crumbs: crumbs,
                                   unit: { .module($0.module) }, isInside: { _ in true }))
        }
        guard multiModule || !fitsAll else { return scopes }
        let moduleCrumb = multiModule ? [(fitsAll ? "Modules" : rootCrumb, fitsAll ? "modules" : rootView)] : []
        for module in site.modules {
            let members = roots.filter { $0.module == module }
            let folders = Set(members.map(site.folder(of:)))
            let byFolder = members.count > mapBudget && folders.count > 1
            let view = moduleAnchor(module)
            let crumbs = (fitsAll ? [(rootCrumb, rootView)] : []) + moduleCrumb + [(module, view)]
            scopes.append(MapScope(
                id: "s-" + view, view: view, crumbs: multiModule ? crumbs : [(module, view)],
                unit: { node in
                    guard node.module == module else { return .module(node.module) }
                    return byFolder ? .folder(module, site.folder(of: node)) : .type(node.id)
                },
                isInside: { unit in
                    switch unit {
                    case .type: true
                    case .folder(let owner, _): owner == module
                    case .module(let other): other == module
                    }
                }))
            guard byFolder else { continue }
            for folder in folders.sorted() {
                let folderView = folderAnchor(module, folder)
                scopes.append(MapScope(
                    id: "s-" + folderView, view: folderView, crumbs: crumbs + [(folderLabel(folder), folderView)],
                    unit: { node in
                        guard node.module == module else { return .module(node.module) }
                        let other = site.folder(of: node)
                        return other == folder ? .type(node.id) : .folder(module, other)
                    },
                    isInside: { unit in
                        if case .type = unit { return true }
                        return false
                    }))
            }
        }
        return scopes
    }

    /// The anchor of a module's view.
    ///
    /// - Parameter module: The module name.
    /// - Returns: `m-Module`, with characters a link fragment may drop replaced by `-`.
    static func moduleAnchor(_ module: String) -> String {
        "m-" + safeAnchor(module)
    }

    /// The anchor of a folder's view.
    ///
    /// - Parameters:
    ///   - module: The module the folder belongs to.
    ///   - folder: The folder name; empty for files directly in the module's directory.
    /// - Returns: `f-Module-Folder`, or `f-Module-` for the module's own directory.
    static func folderAnchor(_ module: String, _ folder: String) -> String {
        "f-" + safeAnchor(module) + "-" + safeAnchor(folder)
    }

    /// How a folder is named on the page.
    ///
    /// - Parameter folder: The folder name; empty for files directly in the module's directory.
    /// - Returns: `Name/`, or `(module root)` for the module's own directory.
    static func folderLabel(_ folder: String) -> String {
        folder.isEmpty ? "(module root)" : folder + "/"
    }

    /// Replaces every character but letters and digits with `-`, so the result survives as a link fragment.
    ///
    /// - Parameter text: Any text.
    /// - Returns: The text with only letters, digits, and dashes.
    static func safeAnchor(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// The boxes and edges one level draws in one variant, with whatever it leaves out.
    struct ScopeFigure {
        var items: [GraphLayout.Item] = []
        var links: [GraphLayout.Link] = []
        /// Inside boxes with no edge in this variant, listed under the figure.
        var loose: [MapScope.Unit] = []
        /// Inside boxes past the budget, listed under the figure.
        var overflow: [MapScope.Unit] = []
        /// The root types this level draws as themselves.
        var shown: [String] = []
    }

    /// Folds the graph into one level's boxes and draws what fits the budget.
    ///
    /// - Parameters:
    ///   - scope: The level.
    ///   - site: The arranged interface.
    ///   - includeBody: `true` to include dependencies used only inside bodies.
    /// - Returns: The figure's parts. Boxes past the budget are the least connected ones, ranked with
    ///   body dependencies included so both variants keep the same boxes.
    static func figure(_ scope: MapScope, site: Site, includeBody: Bool) -> ScopeFigure {
        var units: [String: MapScope.Unit] = [:]
        var inside: [MapScope.Unit] = []
        var insideSet = Set<MapScope.Unit>()
        for id in site.rootIDs {
            guard let node = site.byID[id] else { continue }
            let unit = scope.unit(node)
            units[id] = unit
            if scope.isInside(unit), insideSet.insert(unit).inserted { inside.append(unit) }
        }
        func fold(_ links: [Site.Rolled]) -> [(from: MapScope.Unit, to: MapScope.Unit, roles: [Mention.Role])] {
            var result: [(from: MapScope.Unit, to: MapScope.Unit, roles: [Mention.Role])] = []
            var index: [[MapScope.Unit]: Int] = [:]
            for link in links {
                guard let from = units[link.from], let to = units[link.to], from != to,
                      insideSet.contains(from) || insideSet.contains(to) else { continue }
                if let at = index[[from, to]] {
                    for role in link.roles where !result[at].roles.contains(role) { result[at].roles.append(role) }
                } else {
                    index[[from, to]] = result.count
                    result.append((from, to, link.roles))
                }
            }
            return result
        }
        var degree: [MapScope.Unit: Int] = [:]
        for link in fold(site.rolled(includeBody: true)) {
            degree[link.from, default: 0] += 1
            degree[link.to, default: 0] += 1
        }
        let ranked = inside.enumerated().sorted { (-(degree[$0.element] ?? 0), $0.offset) < (-(degree[$1.element] ?? 0), $1.offset) }.map(\.element)
        let kept = Set(ranked.prefix(mapBudget))
        var figure = ScopeFigure()
        figure.overflow = inside.filter { !kept.contains($0) }
        let dropped = Set(figure.overflow)
        let links = fold(site.rolled(includeBody: includeBody)).filter { link in
            !dropped.contains(link.from) && !dropped.contains(link.to)
        }
        let connected = Set(links.flatMap { [$0.from, $0.to] })
        figure.loose = inside.filter { kept.contains($0) && !connected.contains($0) }
        var drawn = inside.filter { kept.contains($0) && connected.contains($0) }
        var drawnSet = Set(drawn)
        for link in links {
            for unit in [link.from, link.to] where drawnSet.insert(unit).inserted { drawn.append(unit) }
        }
        figure.items = drawn.map { item($0, site: site, boundary: !scope.isInside($0)) }
        figure.links = links.map { link in
            GraphLayout.Link(from: unitID(link.from), to: unitID(link.to), dashed: link.roles == [.body],
                             title: "\(unitLabel(link.from, site: site)) \(words(link.roles)) \(unitLabel(link.to, site: site))")
        }
        figure.shown = inside.filter { kept.contains($0) }.compactMap { unit in
            if case .type(let id) = unit { return id }
            return nil
        }
        return figure
    }

    /// The id a box carries on the map, which panel views name to light it.
    ///
    /// - Parameter unit: The box.
    /// - Returns: The node id for a type, `module:Name` for a module, and `folder:Module/Name` for a folder.
    static func unitID(_ unit: MapScope.Unit) -> String {
        switch unit {
        case .type(let id): id
        case .module(let module): "module:" + module
        case .folder(let module, let folder): "folder:" + module + "/" + folder
        }
    }

    /// The name a box shows.
    ///
    /// - Parameters:
    ///   - unit: The box.
    ///   - site: The arranged interface, for type labels.
    /// - Returns: The type's label, the module name, or the folder label.
    static func unitLabel(_ unit: MapScope.Unit, site: Site) -> String {
        switch unit {
        case .type(let id): site.byID[id].map(site.label) ?? id
        case .module(let module): module
        case .folder(_, let folder): folderLabel(folder)
        }
    }

    /// A box for the layout: label, detail line, link, and classes.
    ///
    /// - Parameters:
    ///   - unit: The box.
    ///   - site: The arranged interface.
    ///   - boundary: `true` for a box outside the level, drawn dashed.
    /// - Returns: The layout item; a module or folder box links to its own level.
    static func item(_ unit: MapScope.Unit, site: Site, boundary: Bool) -> GraphLayout.Item {
        let roots = site.rootIDs.compactMap { site.byID[$0] }
        switch unit {
        case .type(let id):
            let node = site.byID[id]
            let kind = node.map { $0.keyword == "file" ? "file scope" : $0.keyword } ?? ""
            let detail = ([kind] + (site.modules.count > 1 ? [node?.module ?? ""] : [])).joined(separator: " · ")
            let classes = [site.findings(under: id) > 0 ? "dirty" : nil, node.map { Contract.rank($0.access) == 0 } == true ? "private" : nil]
            return GraphLayout.Item(id: id, label: unitLabel(unit, site: site), detail: detail, link: site.anchor(id),
                                    classes: classes.compactMap { $0 }.joined(separator: " "))
        case .module(let module):
            let count = roots.filter { $0.module == module }.count
            return GraphLayout.Item(id: unitID(unit), label: module, detail: "module · \(count) type\(count == 1 ? "" : "s")",
                                    link: moduleAnchor(module), classes: boundary ? "scope boundary" : "scope")
        case .folder(let module, let folder):
            let count = roots.filter { $0.module == module && site.folder(of: $0) == folder }.count
            return GraphLayout.Item(id: unitID(unit), label: folderLabel(folder), detail: "folder · \(count) type\(count == 1 ? "" : "s")",
                                    link: folderAnchor(module, folder), classes: boundary ? "scope boundary" : "scope")
        }
    }

    /// A link to a module's or folder's view, lighting its box on the map when hovered.
    ///
    /// - Parameters:
    ///   - unit: A module or folder box; a type falls back to its own chip.
    ///   - site: The arranged interface.
    /// - Returns: An `<a>` element.
    static func unitChip(_ unit: MapScope.Unit, site: Site) -> String {
        switch unit {
        case .type(let id):
            return site.byID[id].map { chip($0, site: site) } ?? ""
        case .module(let module):
            return "<a class=\"chip scope\" href=\"#\(moduleAnchor(module))\" data-root=\"\(escape(unitID(unit)))\">\(escape(module))</a>"
        case .folder(let module, let folder):
            return "<a class=\"chip scope\" href=\"#\(folderAnchor(module, folder))\" data-root=\"\(escape(unitID(unit)))\">\(escape(folderLabel(folder)))</a>"
        }
    }

    // MARK: Stage

    /// The middle pane: one figure per level and variant, of which the page shows one at a time.
    ///
    /// - Parameters:
    ///   - site: The arranged interface.
    ///   - scopes: The levels from ``mapScopes(_:)``.
    /// - Returns: The stage element.
    static func stage(_ site: Site, scopes: [MapScope]) -> String {
        var html = """
        <section class="stage" id="map" aria-label="Dependency map">
        <header class="stage-head">
        <div class="stage-top"><button type="button" class="pane-toggle" id="expand-left" hidden>Show list</button><p class="eyebrow">Dependency map</p>
        <div class="zoom" role="group" aria-label="Zoom"><button type="button" id="zoom-out" aria-label="Zoom out" title="Zoom out to the wider level (−)">−</button><button type="button" id="zoom-in" aria-label="Zoom in" title="Zoom in to a narrower level, down to the selected type and its neighbors (+)">+</button></div></div>
        <p class="lede">An arrow points from a box to one it depends on. Hover a box to preview it on the right; select it to keep it there. Zoom in to isolate the selected type with only its neighbors. Dashed boxes lie outside this level; select one to step into it.</p>
        <label class="check"><input type="checkbox" id="map-body"> Include dependencies used only inside bodies</label>
        </header>

        """
        for (index, scope) in scopes.enumerated() {
            let parent = parentScope(scope, in: scopes).map { " data-parent=\"\($0)\"" } ?? ""
            html += "<div class=\"scope-map\" data-scope-map=\"\(scope.id)\" data-label=\"\(escape(scope.crumbs.last?.label ?? ""))\"\(parent)\(index == 0 ? "" : " hidden")>"
            html += "<nav class=\"crumbs\" aria-label=\"Map level\">"
            html += scope.crumbs.enumerated().map { offset, crumb in
                offset == scope.crumbs.count - 1
                    ? "<span aria-current=\"page\">\(escape(crumb.label))</span>"
                    : "<a href=\"#\(crumb.view)\">\(escape(crumb.label))</a>"
            }.joined(separator: "<span class=\"sep\">›</span>")
            html += "</nav>"
            for includeBody in [false, true] {
                let figure = Self.figure(scope, site: site, includeBody: includeBody)
                let layout = GraphLayout.layered(figure.items, figure.links)
                html += "<div class=\"map-variant\" data-map=\"\(includeBody ? "all" : "interface")\"\(includeBody ? " hidden" : "")>"
                html += "<ul class=\"legend\"><li><span class=\"swatch\"></span>In a signature</li>"
                if includeBody { html += "<li><span class=\"swatch body\"></span>Only inside a body</li>" }
                if figure.items.contains(where: { $0.classes.contains("boundary") }) { html += "<li><span class=\"swatch box\"></span>Outside this level</li>" }
                html += "</ul>"
                let marker = scope.id + (includeBody ? "-all" : "")
                html += "<div class=\"figure\">\(svg(layout, label: "Dependency map: \(scope.crumbs.last?.label ?? "")", marker: marker))</div>"
                html += "<p class=\"caption\">\(figure.items.count) boxes, \(figure.links.count) dependencies.</p>"
                if !figure.loose.isEmpty {
                    html += "<p class=\"loose\"><span class=\"term\">Not connected</span>" + figure.loose.map { unitChip($0, site: site) }.joined() + "</p>"
                }
                if !figure.overflow.isEmpty {
                    html += "<details class=\"loose overflow\"><summary><span class=\"term\">\(figure.overflow.count) more</span> <span class=\"reveal\">Least connected, not drawn</span></summary><div class=\"chips\">"
                    html += figure.overflow.map { unitChip($0, site: site) }.joined() + "</div></details>"
                }
                html += "</div>"
            }
            html += "</div>\n"
        }
        html += "<div class=\"scope-map\" data-scope-map=\"focus\" hidden><nav class=\"crumbs\" aria-label=\"Map level\"></nav>"
        html += "<ul class=\"legend\"><li><span class=\"swatch\"></span>Uses it, above; it depends on, below</li></ul>"
        html += "<div class=\"figure\"></div><p class=\"caption\"></p></div>\n"
        return html + "</section>\n"
    }

    /// The level a level zooms out to: the module overview for all types and for each module, and the
    /// module for each of its folders.
    ///
    /// - Parameters:
    ///   - scope: The level.
    ///   - scopes: Every level.
    /// - Returns: The parent level's id, or `nil` for the widest level.
    static func parentScope(_ scope: MapScope, in scopes: [MapScope]) -> String? {
        let ids = Set(scopes.map(\.id))
        if scope.id == "s-types" || scope.id.hasPrefix("s-m-") { return ids.contains("s-modules") ? "s-modules" : nil }
        if scope.id.hasPrefix("s-f-"), let module = scopes.last(where: { $0.id.hasPrefix("s-m-") && scope.crumbs.map(\.view).contains($0.view) }) {
            return module.id
        }
        return nil
    }

    // MARK: Scope views

    /// The right pane's views for the map's wider levels: the module overview, each module, and each
    /// folder drawn as its own level.
    ///
    /// - Parameters:
    ///   - site: The arranged interface.
    ///   - scopes: The levels from ``mapScopes(_:)``.
    /// - Returns: One view per level besides the default, plus one per module that has none.
    static func scopeViews(_ site: Site, scopes: [MapScope]) -> String {
        let roots = site.rootIDs.compactMap { site.byID[$0] }
        let links = site.rolled(includeBody: true)
        let moduleOf = { (id: String) in site.byID[id]?.module ?? "" }
        var html = ""
        if let overview = scopes.first(where: { $0.id == "s-modules" }), overview.view != "start" {
            html += "<section class=\"view\" id=\"modules\" data-view data-root=\"\" data-scope=\"s-modules\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">Modules</p><h2>\(site.modules.count) modules</h2>"
            html += "<p class=\"lede\">Each module with the modules it depends on. Select one to draw its types.</p></header><div class=\"cards\">"
            for module in site.modules { html += moduleCard(module, site: site, links: links) }
            html += "</div></section>\n"
        }
        for module in site.modules {
            let view = moduleAnchor(module)
            let scope = scopes.first { $0.view == view }?.id ?? scopes.first?.id ?? ""
            let members = roots.filter { $0.module == module }
            let uses = orderedUnique(links.filter { moduleOf($0.from) == module && moduleOf($0.to) != module }.map { moduleOf($0.to) })
            let usedBy = orderedUnique(links.filter { moduleOf($0.to) == module && moduleOf($0.from) != module }.map { moduleOf($0.from) })
            let folders = orderedUnique(members.map(site.folder(of:)))
            html += "<section class=\"view\" id=\"\(view)\" data-view data-root=\"\(escape(unitID(.module(module))))\" data-scope=\"\(scope)\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">Module</p><h2>\(escape(module))</h2>"
            html += "<p class=\"lede\">\(summaryLine(members, site: site))</p></header>"
            html += chipBlock("Front door", site.entryPoints(in: module).map { MapScope.Unit.type($0.id) }, site: site)
            html += chipBlock("Depends on", uses.map { MapScope.Unit.module($0) }, site: site)
            html += chipBlock("Used by", usedBy.map { MapScope.Unit.module($0) }, site: site)
            if folders.count > 1 { html += chipBlock("Folders", folders.map { MapScope.Unit.folder(module, $0) }, site: site) }
            html += chipBlock("Types", members.map { MapScope.Unit.type($0.id) }, site: site)
            html += "</section>\n"
        }
        for scope in scopes where scope.view.hasPrefix("f-") {
            guard let sample = roots.first(where: { node in
                if case .type = scope.unit(node) { return true }
                return false
            }) else { continue }
            let module = sample.module
            let folder = site.folder(of: sample)
            let members = roots.filter { $0.module == module && site.folder(of: $0) == folder }
            let ids = Set(members.map(\.id))
            let outside = { (id: String) -> MapScope.Unit? in
                guard let node = site.byID[id], !ids.contains(id) else { return nil }
                return node.module == module ? .folder(module, site.folder(of: node)) : .module(node.module)
            }
            let uses = orderedUnique(links.filter { ids.contains($0.from) }.compactMap { outside($0.to) })
            let usedBy = orderedUnique(links.filter { ids.contains($0.to) }.compactMap { outside($0.from) })
            html += "<section class=\"view\" id=\"\(scope.view)\" data-view data-root=\"\(escape(unitID(.folder(module, folder))))\" data-scope=\"\(scope.id)\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">\(escape(module)) · folder</p><h2>\(escape(folderLabel(folder)))</h2>"
            html += "<p class=\"lede\">\(summaryLine(members, site: site))</p></header>"
            html += chipBlock("Depends on", uses, site: site)
            html += chipBlock("Used by", usedBy, site: site)
            html += chipBlock("Types", members.map { MapScope.Unit.type($0.id) }, site: site)
            html += "</section>\n"
        }
        return html
    }

    /// A card for one module in the overview: its size and the modules it depends on.
    ///
    /// - Parameters:
    ///   - module: The module name.
    ///   - site: The arranged interface.
    ///   - links: Root-level edges with body dependencies included.
    /// - Returns: An `<a>` card linking to the module's view.
    static func moduleCard(_ module: String, site: Site, links: [Site.Rolled]) -> String {
        let members = site.rootIDs.compactMap { site.byID[$0] }.filter { $0.module == module }
        let uses = orderedUnique(links.compactMap { link -> String? in
            guard site.byID[link.from]?.module == module, let other = site.byID[link.to]?.module, other != module else { return nil }
            return other
        })
        var html = "<a class=\"card\" href=\"#\(moduleAnchor(module))\"><span class=\"card-kind\">module</span>"
        html += "<code class=\"card-name\">\(escape(module))</code><span class=\"card-facts\">\(summaryLine(members, site: site))</span>"
        if !uses.isEmpty { html += "<span class=\"card-facts\">depends on \(escape(uses.joined(separator: ", ")))</span>" }
        return html + "</a>"
    }

    /// One line sizing a set of root types: how many, how many public, and how many findings.
    ///
    /// - Parameters:
    ///   - members: The root types.
    ///   - site: The arranged interface.
    /// - Returns: Plain text such as `12 types · 8 public · 2 findings`.
    static func summaryLine(_ members: [Graph.Node], site: Site) -> String {
        let publicCount = members.filter { Contract.rank($0.access) >= 3 }.count
        let findings = members.reduce(0) { $0 + site.findings(under: $1.id) }
        var parts = ["\(members.count) type\(members.count == 1 ? "" : "s")", "\(publicCount) public"]
        if findings > 0 { parts.append("\(findings) finding\(findings == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// A titled row of chips, or nothing when there are none.
    ///
    /// - Parameters:
    ///   - title: The row's heading.
    ///   - units: The boxes to link to.
    ///   - site: The arranged interface.
    /// - Returns: A block, or an empty string for no units.
    static func chipBlock(_ title: String, _ units: [MapScope.Unit], site: Site) -> String {
        guard !units.isEmpty else { return "" }
        return "<section class=\"block\"><h3>\(escape(title)) <span class=\"count\">\(units.count)</span></h3><div class=\"chips\">"
            + units.map { unitChip($0, site: site) }.joined() + "</div></section>"
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
