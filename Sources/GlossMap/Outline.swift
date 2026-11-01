import GlossCore

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
        let members = nodes.filter { $0.module == module }
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
