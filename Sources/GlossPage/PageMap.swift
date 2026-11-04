import Foundation
import GlossRead
import GlossModel
import GlossMap

/// The map on the page: one figure per level and variant, the level views in the details pane, and the
/// links between them. The levels themselves are decided in ``GlossMap/Atlas/mapScopes()``.
extension InterfacePage {
    /// The anchor of a module's view.
    ///
    /// - Parameter module: The module name.
    /// - Returns: `m-Module`, with characters a link fragment may drop replaced by `-`.
    static func moduleAnchor(_ module: String) -> String {
        "m-" + Atlas.safeID(module)
    }

    /// The anchor of a folder's view.
    ///
    /// - Parameters:
    ///   - module: The module the folder belongs to.
    ///   - folder: The folder name; empty for files directly in the module's directory.
    /// - Returns: `f-Module-Folder`, or `f-Module-` for the module's own directory.
    static func folderAnchor(_ module: String, _ folder: String) -> String {
        "f-" + Atlas.safeID(module) + "-" + Atlas.safeID(folder)
    }

    /// The details-pane view that selecting a level shows.
    ///
    /// - Parameters:
    ///   - scope: The level.
    ///   - scopes: Every level, the default first.
    /// - Returns: `overview` for the default level, unless it is a module's, and otherwise the level's own view.
    static func view(of scope: MapScope, in scopes: [MapScope]) -> String {
        switch scope.kind {
        case .allTypes: "overview"
        case .modules: scopes.first?.id == scope.id ? "overview" : "modules"
        case .module(let module): moduleAnchor(module)
        case .folder(let module, let folder): folderAnchor(module, folder)
        }
    }

    /// Where selecting a box leads.
    ///
    /// - Parameters:
    ///   - unit: The box.
    ///   - atlas: The arranged interface.
    /// - Returns: The anchor of the type's, module's, or folder's view.
    static func link(_ unit: MapScope.Unit, atlas: Atlas) -> String {
        switch unit {
        case .type(let id): anchor(id, in: atlas)
        case .module(let module): moduleAnchor(module)
        case .folder(let module, let folder): folderAnchor(module, folder)
        }
    }

    /// A link to a module's or folder's view, lighting its box on the map when hovered.
    ///
    /// - Parameters:
    ///   - unit: A module or folder box; a type falls back to its own chip.
    ///   - atlas: The arranged interface.
    /// - Returns: An `<a>` element.
    static func unitChip(_ unit: MapScope.Unit, atlas: Atlas) -> String {
        switch unit {
        case .type(let id):
            return atlas.byID[id].map { chip($0, atlas: atlas) } ?? ""
        case .module, .folder:
            return "<a class=\"chip scope\" href=\"#\(link(unit, atlas: atlas))\" data-root=\"\(escape(unit.id))\">\(escape(atlas.label(of: unit)))</a>"
        }
    }

    // MARK: Stage

    /// The middle pane: one figure per level and variant, of which the page shows one at a time.
    ///
    /// - Parameters:
    ///   - atlas: The arranged interface.
    ///   - scopes: The levels from ``GlossMap/Atlas/mapScopes()``.
    /// - Returns: The stage element.
    static func stage(_ atlas: Atlas, scopes: [MapScope]) -> String {
        var html = """
        <section class="stage" id="map" aria-label="Dependency map">
        <header class="stage-head">
        <div class="stage-top"><p class="eyebrow">Dependency map</p>
        <div class="zoom" role="group" aria-label="Zoom"><button type="button" id="zoom-out" aria-label="Zoom out" title="Zoom out to the wider level (−)">−</button><button type="button" id="zoom-in" aria-label="Zoom in" title="Zoom in to a narrower level, down to the selected type and its neighbors (+)">+</button></div></div>
        <p class="lede">An arrow points from a box to one it depends on. Hover a box to preview its details; select it to keep it there. Zoom in to isolate the selected type with only its neighbors. Dashed boxes lie outside this level; select one to step into it.</p>
        </header>

        """
        for (index, scope) in scopes.enumerated() {
            let parent = scope.parent.map { " data-parent=\"\($0)\"" } ?? ""
            html += "<div class=\"scope-map\" data-scope-map=\"\(scope.id)\" data-label=\"\(escape(scope.label))\"\(parent)\(index == 0 ? "" : " hidden")>"
            html += "<nav class=\"crumbs\" aria-label=\"Map level\">"
            let crumbs = scope.path.compactMap { id in scopes.first { $0.id == id } }
            html += crumbs.enumerated().map { offset, crumb in
                offset == crumbs.count - 1
                    ? "<span aria-current=\"page\">\(escape(crumb.label))</span>"
                    : "<a href=\"#\(view(of: crumb, in: scopes))\">\(escape(crumb.label))</a>"
            }.joined(separator: "<span class=\"sep\">›</span>")
            html += "</nav>"
            do {
                let figure = atlas.figure(scope, includeBody: true)
                let layout = GraphLayout.layered(figure.items, figure.links)
                html += "<div class=\"map-variant\">"
                html += "<ul class=\"legend\"><li><span class=\"swatch\"></span>In a signature</li>"
                html += "<li><span class=\"swatch body\"></span>Only inside a body</li>"
                if figure.items.contains(where: { $0.flags.contains(.boundary) }) { html += "<li><span class=\"swatch box\"></span>Outside this level</li>" }
                html += "</ul>"
                html += "<div class=\"figure\">\(svg(layout, atlas: atlas, label: "Dependency map: \(scope.label)", marker: scope.id))</div>"
                html += "<p class=\"caption\">\(figure.items.count) boxes, \(figure.links.count) dependencies.</p>"
                if !figure.loose.isEmpty {
                    html += "<p class=\"loose\"><span class=\"term\">Not connected</span>" + figure.loose.map { unitChip($0, atlas: atlas) }.joined() + "</p>"
                }
                if !figure.overflow.isEmpty {
                    html += "<details class=\"loose overflow\"><summary><span class=\"term\">\(figure.overflow.count) more</span> <span class=\"reveal\">Least connected, not drawn</span></summary><div class=\"chips\">"
                    html += figure.overflow.map { unitChip($0, atlas: atlas) }.joined() + "</div></details>"
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

    // MARK: Scope views

    /// The details pane's views for the map's wider levels: the module overview, each module, and each
    /// folder drawn as its own level.
    ///
    /// - Parameters:
    ///   - atlas: The arranged interface.
    ///   - scopes: The levels from ``GlossMap/Atlas/mapScopes()``.
    /// - Returns: One view per level besides the default, plus one per module that has none.
    static func scopeViews(_ atlas: Atlas, scopes: [MapScope]) -> String {
        var html = ""
        if let modules = scopes.first(where: { $0.kind == .modules }), view(of: modules, in: scopes) != "overview" {
            html += "<section class=\"view\" id=\"modules\" data-view data-root=\"\" data-scope=\"s-modules\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">Modules</p><h2>\(atlas.modules.count) modules</h2>"
            html += "<p class=\"lede\">Each module with the modules it depends on. Select one to draw its types.</p></header><div class=\"cards\">"
            for module in atlas.modules { html += moduleCard(module, atlas: atlas) }
            html += "</div></section>\n"
        }
        for module in atlas.modules {
            let view = moduleAnchor(module)
            let scope = scopes.first { $0.kind == .module(module) }?.id ?? scopes.first?.id ?? ""
            let members = atlas.types(in: module)
            let (uses, usedBy) = atlas.dependencies(ofModule: module)
            let folders = atlas.folders(in: module)
            html += "<section class=\"view\" id=\"\(view)\" data-view data-root=\"\(escape(MapScope.Unit.module(module).id))\" data-scope=\"\(scope)\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">Module</p><h2>\(escape(module))</h2>"
            html += "<p class=\"lede\">\(atlas.summary(of: members))</p></header>"
            html += chipBlock("Entry points", atlas.entryPoints(in: module).map { MapScope.Unit.type($0.id) }, atlas: atlas)
            html += chipBlock("Depends on", uses.map { MapScope.Unit.module($0) }, atlas: atlas)
            html += chipBlock("Used by", usedBy.map { MapScope.Unit.module($0) }, atlas: atlas)
            if folders.count > 1 { html += chipBlock("Folders", folders.map { MapScope.Unit.folder(module, $0) }, atlas: atlas) }
            html += chipBlock("Types", members.map { MapScope.Unit.type($0.id) }, atlas: atlas)
            html += "</section>\n"
        }
        for scope in scopes {
            guard case .folder(let module, let folder) = scope.kind else { continue }
            let members = atlas.types(inFolder: folder, of: module)
            let (uses, usedBy) = atlas.dependencies(ofFolder: folder, in: module)
            html += "<section class=\"view\" id=\"\(view(of: scope, in: scopes))\" data-view data-root=\"\(escape(MapScope.Unit.folder(module, folder).id))\" data-scope=\"\(scope.id)\">"
            html += "<header class=\"view-head\"><p class=\"eyebrow\">\(escape(module)) · folder</p><h2>\(escape(Wording.folderLabel(folder)))</h2>"
            html += "<p class=\"lede\">\(atlas.summary(of: members))</p></header>"
            html += chipBlock("Depends on", uses, atlas: atlas)
            html += chipBlock("Used by", usedBy, atlas: atlas)
            html += chipBlock("Types", members.map { MapScope.Unit.type($0.id) }, atlas: atlas)
            html += "</section>\n"
        }
        return html
    }

    /// A card for one module in the overview: its size and the modules it depends on.
    ///
    /// - Parameters:
    ///   - module: The module name.
    ///   - atlas: The arranged interface.
    /// - Returns: An `<a>` card linking to the module's view.
    static func moduleCard(_ module: String, atlas: Atlas) -> String {
        let uses = atlas.dependencies(ofModule: module).uses
        var html = "<a class=\"card\" href=\"#\(moduleAnchor(module))\"><span class=\"card-kind\">module</span>"
        html += "<code class=\"card-name\">\(escape(module))</code><span class=\"card-facts\">\(atlas.summary(of: atlas.types(in: module)))</span>"
        if !uses.isEmpty { html += "<span class=\"card-facts\">depends on \(escape(uses.joined(separator: ", ")))</span>" }
        return html + "</a>"
    }

    /// A titled row of chips, or nothing when there are none.
    ///
    /// - Parameters:
    ///   - title: The row's heading.
    ///   - units: The boxes to link to.
    ///   - atlas: The arranged interface.
    /// - Returns: A block, or an empty string for no units.
    static func chipBlock(_ title: String, _ units: [MapScope.Unit], atlas: Atlas) -> String {
        guard !units.isEmpty else { return "" }
        return "<section class=\"block\"><h3>\(escape(title)) <span class=\"count\">\(units.count)</span></h3><div class=\"chips\">"
            + units.map { unitChip($0, atlas: atlas) }.joined() + "</div></section>"
    }
}
