import GlossCore

/// One level the dependency map can be read at: every type, every module, one module, or one folder.
///
/// A large codebase cannot be drawn as one graph a reader can follow, so the map opens at the most
/// detailed level that fits ``Atlas/mapBudget`` boxes, and each level draws what lies outside it as
/// boundary boxes a reader can step into.
public struct MapScope: Sendable {
    /// What a root type is drawn as at a level.
    public enum Unit: Hashable, Sendable {
        /// A type drawn as its own box, by node id.
        case type(String)
        /// A whole module drawn as one box, by name.
        case module(String)
        /// One folder of a module drawn as one box: the module name, then the folder name, empty for
        /// the module's own directory.
        case folder(String, String)

        /// The id a box carries, which views name to light it.
        public var id: String {
            switch self {
            case .type(let id): id
            case .module(let module): "module:" + module
            case .folder(let module, let folder): "folder:" + module + "/" + folder
            }
        }
    }

    /// Which level this is.
    public enum Kind: Hashable, Sendable {
        /// Every root type at once, offered only when they all fit ``Atlas/mapBudget``.
        case allTypes
        /// Each module as one box, offered only when there is more than one module.
        case modules
        /// One module's types, or its folders when it is over the budget and spread across several; the
        /// value is the module name.
        case module(String)
        /// One folder's types, for a module its level draws as folders: the module name, then the folder name.
        case folder(String, String)
    }

    /// A stable id: `s-types`, `s-modules`, `s-m-Module`, or `s-f-Module-Folder`.
    public var id: String
    /// What the level draws, and for a module or folder level, which one.
    public var kind: Kind
    /// The level's name in a breadcrumb.
    public var label: String
    /// The levels from the widest a reader starts at down to this one, by id; the last is this level.
    public var path: [String]
    /// The level zooming out leads to, or `nil` for the widest.
    public var parent: String?
    /// Folds a root type into the box this level draws for it.
    public var unit: @Sendable (Graph.Node) -> Unit
    /// Whether a box belongs to this level, rather than standing at its boundary.
    public var isInside: @Sendable (Unit) -> Bool
}

/// The boxes and edges one level draws in one variant, with whatever it leaves out.
public struct MapFigure: Sendable {
    /// The boxes to lay out: connected inside boxes within the budget first, then the boundary boxes
    /// their edges reach.
    public var items: [GraphLayout.Item] = []
    /// The edges between those boxes, one per ordered pair, each touching at least one inside box.
    public var links: [GraphLayout.Link] = []
    /// Inside boxes with no edge in this variant, listed under the figure.
    public var loose: [MapScope.Unit] = []
    /// Inside boxes past the budget, listed under the figure.
    public var overflow: [MapScope.Unit] = []
    /// The root types this level draws as themselves.
    public var shown: [String] = []
}

extension Atlas {
    /// The most boxes one level of the map draws; the rest are listed beneath it.
    public static let mapBudget = 30

    /// An id made of letters, digits, and dashes, which every host keeps in a link fragment.
    ///
    /// - Parameter text: Any text.
    /// - Returns: The text with every other character replaced by `-`.
    public static func safeID(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Every level of the map, the default one first.
    ///
    /// - Returns: The levels, in order: the default, then the module overview, each module, and each folder.
    ///
    /// All types are drawn at once when they fit the budget. Otherwise the default is the module
    /// overview, or the only module when there is just one. A module that is over the budget and spread
    /// across several folders is drawn as folders, and each of those folders gets a level of its own.
    public func mapScopes() -> [MapScope] {
        let atlas = self
        let multiModule = modules.count > 1
        let fitsAll = roots.count <= Self.mapBudget
        var scopes: [MapScope] = []

        if fitsAll {
            scopes.append(MapScope(id: "s-types", kind: .allTypes, label: "All types", path: ["s-types"],
                                   parent: multiModule ? "s-modules" : nil,
                                   unit: { .type($0.id) }, isInside: { _ in true }))
        }
        if multiModule {
            scopes.append(MapScope(id: "s-modules", kind: .modules, label: fitsAll ? "Modules" : "All modules",
                                   path: (fitsAll ? ["s-types"] : []) + ["s-modules"], parent: nil,
                                   unit: { .module($0.module) }, isInside: { _ in true }))
        }
        guard multiModule || !fitsAll else { return scopes }
        let above = multiModule ? (fitsAll ? ["s-types", "s-modules"] : ["s-modules"]) : []
        for module in modules {
            let members = types(in: module)
            let folders = Set(members.map(folder(of:)))
            let byFolder = members.count > Self.mapBudget && folders.count > 1
            let id = "s-m-" + Self.safeID(module)
            let path = above + [id]
            scopes.append(MapScope(
                id: id, kind: .module(module), label: module, path: path, parent: multiModule ? "s-modules" : nil,
                unit: { node in
                    guard node.module == module else { return .module(node.module) }
                    return byFolder ? .folder(module, atlas.folder(of: node)) : .type(node.id)
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
                let folderID = "s-f-" + Self.safeID(module) + "-" + Self.safeID(folder)
                scopes.append(MapScope(
                    id: folderID, kind: .folder(module, folder), label: Wording.folderLabel(folder),
                    path: path + [folderID], parent: id,
                    unit: { node in
                        guard node.module == module else { return .module(node.module) }
                        let other = atlas.folder(of: node)
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

    /// The levels that draw each root type as itself, which is where selecting that type can show it.
    ///
    /// - Parameter scopes: The levels from ``mapScopes()``.
    /// - Returns: Level ids in level order, keyed by root id.
    public func levelsDrawing(_ scopes: [MapScope]) -> [String: [String]] {
        var levels: [String: [String]] = [:]
        for scope in scopes {
            for id in figure(scope, includeBody: true).shown { levels[id, default: []].append(scope.id) }
        }
        return levels
    }

    /// Folds the graph into one level's boxes and draws what fits the budget.
    ///
    /// - Parameters:
    ///   - scope: The level.
    ///   - includeBody: `true` to include dependencies used only inside bodies.
    /// - Returns: The figure's parts. Boxes past the budget are the least connected ones, ranked with
    ///   body dependencies included so both variants keep the same boxes.
    public func figure(_ scope: MapScope, includeBody: Bool) -> MapFigure {
        var units: [String: MapScope.Unit] = [:]
        var inside: [MapScope.Unit] = []
        var insideSet = Set<MapScope.Unit>()
        for node in roots {
            let unit = scope.unit(node)
            units[node.id] = unit
            if scope.isInside(unit), insideSet.insert(unit).inserted { inside.append(unit) }
        }
        func fold(_ links: [Rolled]) -> [(from: MapScope.Unit, to: MapScope.Unit, roles: [Mention.Role])] {
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
        for link in fold(rolled(includeBody: true)) {
            degree[link.from, default: 0] += 1
            degree[link.to, default: 0] += 1
        }
        let ranked = inside.enumerated().sorted { (-(degree[$0.element] ?? 0), $0.offset) < (-(degree[$1.element] ?? 0), $1.offset) }.map(\.element)
        let kept = Set(ranked.prefix(Self.mapBudget))
        var figure = MapFigure()
        figure.overflow = inside.filter { !kept.contains($0) }
        let dropped = Set(figure.overflow)
        let links = fold(rolled(includeBody: includeBody)).filter { link in
            !dropped.contains(link.from) && !dropped.contains(link.to)
        }
        let connected = Set(links.flatMap { [$0.from, $0.to] })
        figure.loose = inside.filter { kept.contains($0) && !connected.contains($0) }
        var drawn = inside.filter { kept.contains($0) && connected.contains($0) }
        var drawnSet = Set(drawn)
        for link in links {
            for unit in [link.from, link.to] where drawnSet.insert(unit).inserted { drawn.append(unit) }
        }
        figure.items = drawn.map { item($0, boundary: !scope.isInside($0)) }
        figure.links = links.map { link in
            GraphLayout.Link(from: link.from.id, to: link.to.id, dashed: link.roles == [.body],
                             title: "\(label(of: link.from)) \(Wording.words(link.roles)) \(label(of: link.to))")
        }
        figure.shown = inside.filter { kept.contains($0) }.compactMap { unit in
            if case .type(let id) = unit { return id }
            return nil
        }
        return figure
    }

    /// The name a box shows.
    ///
    /// - Parameter unit: The box.
    /// - Returns: The type's label, the module name, or the folder label.
    public func label(of unit: MapScope.Unit) -> String {
        switch unit {
        case .type(let id): byID[id].map(label) ?? id
        case .module(let module): module
        case .folder(_, let folder): Wording.folderLabel(folder)
        }
    }

    /// A box for the layout: its label, its detail line, and how it is drawn.
    ///
    /// - Parameters:
    ///   - unit: The box.
    ///   - boundary: `true` for a box outside the level, drawn dashed.
    /// - Returns: The layout item.
    public func item(_ unit: MapScope.Unit, boundary: Bool) -> GraphLayout.Item {
        switch unit {
        case .type(let id):
            let node = byID[id]
            let kind = node.map(Wording.kind(of:)) ?? ""
            let detail = ([kind] + (modules.count > 1 ? [node?.module ?? ""] : [])).joined(separator: " · ")
            var flags: GraphLayout.Flags = []
            if findings(under: id) > 0 { flags.insert(.dirty) }
            if let node, Contract.rank(node.access) == 0 { flags.insert(.private) }
            return GraphLayout.Item(unit: unit, label: label(of: unit), detail: detail, flags: flags)
        case .module(let module):
            let count = types(in: module).count
            return GraphLayout.Item(unit: unit, label: module, detail: "module · \(count) type\(count == 1 ? "" : "s")",
                                    flags: boundary ? [.scope, .boundary] : [.scope])
        case .folder(let module, let folder):
            let count = types(inFolder: folder, of: module).count
            return GraphLayout.Item(unit: unit, label: Wording.folderLabel(folder), detail: "folder · \(count) type\(count == 1 ? "" : "s")",
                                    flags: boundary ? [.scope, .boundary] : [.scope])
        }
    }
}
