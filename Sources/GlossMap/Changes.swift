import GlossCore

extension Atlas {
    /// How a box on the map differs from a base, folding what lies inside it into the box: a type new
    /// since the base, or a module or folder whose every type is new, is added; one holding anything
    /// added, removed, or changed, nested types included, is changed.
    ///
    /// - Parameters:
    ///   - unit: What a box stands for.
    ///   - diff: How the interface differs from the base.
    /// - Returns: The box's change, or `nil` when nothing in it differs.
    public func change(of unit: MapScope.Unit, in diff: InterfaceDiff) -> InterfaceDiff.Change? {
        let inside: [InterfaceDiff.NodeChange]
        let all: Int
        switch unit {
        case .type(let id):
            if diff.change(ofNode: id)?.change == .added { return .added }
            return diff.nodes.contains { $0.node.id == id || $0.node.id.hasPrefix(id + ".") } ? .changed : nil
        case .module(let module):
            inside = diff.nodes.filter { $0.node.module == module }
            all = nodes.filter { $0.module == module }.count
        case .folder(let module, let folder):
            let held = { (node: Graph.Node) in node.module == module && self.folder(of: node) == folder }
            inside = diff.nodes.filter { change in byID[change.node.id].map(held) ?? false }
            all = nodes.filter(held).count
        }
        guard !inside.isEmpty else { return nil }
        return inside.count == all && inside.allSatisfy { $0.change == .added } ? .added : .changed
    }
}
