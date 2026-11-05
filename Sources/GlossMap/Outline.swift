import GlossRead
import GlossModel

/// One row of a module's outline: a source folder, or a type with the types nested in it.
public struct OutlineItem: Sendable, Identifiable {
    /// What a row stands for.
    public enum Kind: Sendable {
        /// A source folder, by its own name alone; the row's id carries its full path.
        case folder(String)
        /// A node of the module: a type, an extension of a type no scanned source declares, or the
        /// module's file scope.
        case type(Graph.Node)
    }

    /// From ``Atlas/folderID(_:_:)`` for a folder, and the node id for a type.
    public var id: String
    /// Whether the row is a folder or a node, and which.
    public var kind: Kind
    /// The rows under this one: for a folder, its subfolders sorted by name and then its types in graph
    /// order; for a type, the kept types nested directly in it.
    public var children: [OutlineItem]
    /// The types under the row at any depth, nested ones included, and the row itself for a type.
    public var typeCount: Int
}

extension Atlas {
    /// The id of a folder's row in an outline.
    ///
    /// - Parameters:
    ///   - module: The module the folder belongs to.
    ///   - path: The folder's directories under the module's own, outermost first.
    /// - Returns: `folder:Module/Path/To`.
    public static func folderID(_ module: String, _ path: [String]) -> String {
        "folder:" + module + "/" + path.joined(separator: "/")
    }

    /// A module's types arranged as its source folders hold them: subfolders first, sorted by name,
    /// then the types in graph order, each nested type under the type that encloses it.
    ///
    /// - Parameters:
    ///   - module: The module name.
    ///   - shows: Which types to keep; a type or folder that encloses a kept type stays too, so a match
    ///     is always seen in place.
    /// - Returns: The module's top rows, with no empty folders.
    public func outline(of module: String, showing shows: (Graph.Node) -> Bool) -> [OutlineItem] {
        let phase = Timing.begin("outline"); defer { Timing.end(phase, module) }
        let members = nodesByModule[module] ?? []
        var nestedIn: [String: [Graph.Node]] = [:]
        var placed: [Graph.Node] = []
        for node in members {
            if let parent = enclosingType(of: node) { nestedIn[parent.id, default: []].append(node) } else { placed.append(node) }
        }
        var kept: [String: Bool] = [:]
        func keeps(_ node: Graph.Node) -> Bool {
            if let known = kept[node.id] { return known }
            let result = shows(node) || (nestedIn[node.id] ?? []).contains(where: keeps)
            kept[node.id] = result
            return result
        }
        func item(_ node: Graph.Node) -> OutlineItem {
            let children = (nestedIn[node.id] ?? []).filter(keeps).map(item)
            return OutlineItem(id: node.id, kind: .type(node), children: children,
                               typeCount: 1 + children.reduce(0) { $0 + $1.typeCount })
        }

        /// The kept types of one folder, and its subfolders by name.
        struct Folder {
            var types: [Graph.Node] = []
            var folders: [String: Folder] = [:]

            /// Files a type into the folder at a path under this one.
            ///
            /// - Parameters:
            ///   - node: The type.
            ///   - path: The remaining directories, outermost first.
            mutating func add(_ node: Graph.Node, at path: ArraySlice<String>) {
                guard let next = path.first else { return types.append(node) }
                folders[next, default: Folder()].add(node, at: path.dropFirst())
            }
        }
        var root = Folder()
        for node in placed where keeps(node) { root.add(node, at: directories(of: node)[...]) }
        func rows(_ folder: Folder, path: [String]) -> [OutlineItem] {
            let subfolders = folder.folders.keys.sorted().compactMap { name -> OutlineItem? in
                guard let inner = folder.folders[name] else { return nil }
                let children = rows(inner, path: path + [name])
                return OutlineItem(id: Self.folderID(module, path + [name]), kind: .folder(name), children: children,
                                   typeCount: children.reduce(0) { $0 + $1.typeCount })
            }
            return subfolders + folder.types.map(item)
        }
        return rows(root, path: [])
    }

    /// The rows that enclose a node in its module's outline, which must be open for it to show.
    ///
    /// - Parameter node: A node.
    /// - Returns: Row ids, outermost first: its folders, then the types it is nested in.
    public func outlineAncestors(of node: Graph.Node) -> [String] {
        var enclosing: [Graph.Node] = []
        var current = node
        while let parent = enclosingType(of: current) {
            enclosing.insert(parent, at: 0)
            current = parent
        }
        let path = directories(of: current)
        let folders = path.indices.map { Self.folderID(node.module, Array(path[...$0])) }
        return folders + enclosing.map(\.id)
    }

    /// The scanned type a nested node is declared in, which the outline files it under.
    ///
    /// - Parameter node: A node.
    /// - Returns: The enclosing node, or `nil` for a root or for a type nested in one no scanned source declares.
    private func enclosingType(of node: Graph.Node) -> Graph.Node? {
        guard node.root != node.id, let dot = node.name.lastIndex(of: ".") else { return nil }
        return byID[Graph.id(node.module, String(node.name[..<dot]))]
    }
}

/// What narrows the list: a search, the findings filter, and the access filter.
public struct ListFilter: Sendable, Hashable {
    /// The search, trimmed and lowercased; empty searches for nothing.
    public var query: String
    /// `true` to keep only types with findings.
    public var findingsOnly: Bool
    /// The narrowest access a type needs to be listed, as ``Atlas/rank(of:)`` ranks it.
    public var minimumRank: Int

    /// The most matching types the list shows while it is narrowed, so a short search in a huge project
    /// still draws at once.
    public static let limit = 300

    /// Makes a filter from what the reader typed and chose.
    ///
    /// - Parameters:
    ///   - search: The search as typed.
    ///   - findingsOnly: `true` to keep only types with findings.
    ///   - minimumRank: The narrowest access a type needs.
    public init(search: String, findingsOnly: Bool, minimumRank: Int) {
        query = search.trimmingCharacters(in: .whitespaces).lowercased()
        self.findingsOnly = findingsOnly
        self.minimumRank = minimumRank
    }

    /// Whether the search or the findings filter narrows the list, which then opens every row that
    /// holds a match and leaves out every module that holds none.
    public var isNarrowing: Bool {
        findingsOnly || !query.isEmpty
    }
}

/// The whole list for one filter, worked out at once so drawing it only reads it.
public struct ListOutline: Sendable {
    /// One module's rows.
    public struct Module: Sendable, Identifiable {
        /// The module's name.
        public var name: String
        /// Its rows, as ``Atlas/outline(of:showing:)`` arranges them.
        public var rows: [OutlineItem]
        /// The module's name, which tells it apart from the others.
        public var id: String { name }
    }

    /// The modules in order: every one, or while narrowing only those that hold a match.
    public var modules: [Module]
    /// How many types match while narrowing; zero otherwise.
    public var matches: Int
    /// How many of them the rows show, at most ``ListFilter/limit``.
    public var shown: Int

    /// The list with nothing read yet.
    public static let empty = ListOutline(modules: [], matches: 0, shown: 0)
}

extension Atlas {
    /// Works out the list for a filter: each module's rows, the matches in graph order and at most
    /// ``ListFilter/limit`` of them while narrowing, so a search draws quickly however large the project.
    ///
    /// - Parameter filter: What narrows the list.
    /// - Returns: The modules and their rows, and how many types matched and are shown.
    public func listOutline(_ filter: ListFilter) -> ListOutline {
        let phase = Timing.begin("list"); defer { Timing.end(phase, filter.query) }
        guard filter.isNarrowing else {
            let modules = modules.map { module in
                ListOutline.Module(name: module, rows: outline(of: module) { self.rank(of: $0) >= filter.minimumRank })
            }
            return ListOutline(modules: modules, matches: 0, shown: 0)
        }
        // A type matches by its name or a member's, among those the access and findings filters keep.
        var kept = Set<String>()
        var matches = 0
        for node in nodes where rank(of: node) >= filter.minimumRank {
            if filter.findingsOnly, group(node.id).findingCount == 0 { continue }
            if !filter.query.isEmpty, !(searchNames[node.id] ?? []).contains(where: { $0.contains(filter.query) }) { continue }
            matches += 1
            if kept.count < ListFilter.limit { kept.insert(node.id) }
        }
        let modules = modules.compactMap { module -> ListOutline.Module? in
            let rows = outline(of: module) { kept.contains($0.id) }
            return rows.isEmpty ? nil : ListOutline.Module(name: module, rows: rows)
        }
        return ListOutline(modules: modules, matches: matches, shown: kept.count)
    }
}
