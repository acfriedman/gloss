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

/// One way a change since a base reaches a type that did not change itself, which is why the Changes
/// level draws the type.
public struct ChangeReason: Sendable, Equatable {
    /// How the change reaches the type.
    public enum Kind: Sendable, Equatable {
        /// The dependency between the two is new, or what it is or which declarations make it changed.
        case dependency(InterfaceDiff.EdgeChange)
        /// The type uses the changed type, whose own declaration changed.
        case declaration(InterfaceDiff.DeclarationChange)
        /// The type reaches a member of the changed type whose signature changed or that is gone.
        case member(InterfaceDiff.DeclarationChange)
    }

    /// The id of the changed type.
    public var changed: String
    /// How the change reaches the type.
    public var kind: Kind
    /// For a member, the type's declarations that reach it, by qualified name; empty otherwise.
    public var via: [String]
}

/// What changed since a base and the types it reaches, drawn as one figure: the blast radius of a
/// change at a glance.
public struct ChangesFigure: Sendable {
    /// The drawing: the changed types, the types they reach, and the dependencies between a change and
    /// the rest.
    public var layout: GraphLayout
    /// How many changed types are drawn.
    public var changed: Int
    /// How many types around them are drawn.
    public var around: Int
    /// The changed types and reached neighbors left out to stay within the budget, most connected first.
    public var overflow: [String]
    /// The neighbors a change does not reach, left out unless asked for: types that use a changed type
    /// but none of what changed in it, and types a changed type uses just as it did. Those touching the
    /// most changes come first.
    public var untouched: [String]
}

extension Atlas {
    /// Lays out what changed since a base, with the neighbors the change reaches.
    ///
    /// - Parameters:
    ///   - diff: How the interface differs from the base.
    ///   - minimumRank: The narrowest access, as ``GlossCore/Contract/rank(_:)``, a type needs to be drawn.
    ///   - budget: The most boxes to draw.
    ///   - includeUntouched: `true` to draw the neighbors the change does not reach as well, after those
    ///     it does.
    /// - Returns: The figure, every type its own box, nested ones included.
    ///
    /// A neighbor is reached when its dependency with a changed type is itself new or changed, either
    /// way, or when it uses a changed type and either the type's own declaration changed or the
    /// neighbor reaches a member of it whose signature changed or that is gone. A member added breaks
    /// no one, and a change to docs alone reaches no one. Members are matched by name as the bodies
    /// reach them, on a type named outright or through a property or parameter of known type, so a
    /// member reached through a local variable goes unseen; the untouched are listed for that reason.
    ///
    /// The changed types come first: when they alone are over the budget, the most connected of them
    /// are drawn and nothing around them. Otherwise the reached neighbors fill what is left, those
    /// touching the most changes first. Only dependencies with a change at one end or both are drawn,
    /// since those are the ones a change can break; removed types are gone from the interface, so they
    /// are not drawn.
    public func changesFigure(_ diff: InterfaceDiff, minimumRank: Int, budget: Int = mapBudget,
                              includeUntouched: Bool = false) -> ChangesFigure {
        let shown = { (id: String) in self.byID[id].map { self.rank(of: $0) >= minimumRank } ?? false }
        let position = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.from, default: 0] += 1
            degree[edge.to, default: 0] += 1
        }
        func ranked(_ ids: [String], by score: (String) -> Int) -> [String] {
            ids.sorted { (-score($0), position[$0] ?? 0) < (-score($1), position[$1] ?? 0) }
        }

        var changed = diff.nodes.filter { $0.change != .removed }.map(\.node.id).filter(shown)
        var overflow: [String] = []
        if changed.count > budget {
            let kept = Set(ranked(changed) { degree[$0] ?? 0 }.prefix(budget))
            overflow = ranked(changed.filter { !kept.contains($0) }) { degree[$0] ?? 0 }
            changed = changed.filter(kept.contains)
        }
        let changedSet = Set(changed)

        let breakable = Breakable(diff)
        var touches: [String: Int] = [:]
        var reached: Set<String> = []
        for edge in edges {
            let fromChanged = changedSet.contains(edge.from)
            let toChanged = changedSet.contains(edge.to)
            guard fromChanged != toChanged else { continue }
            let neighbor = fromChanged ? edge.to : edge.from
            guard shown(neighbor) else { continue }
            touches[neighbor, default: 0] += 1
            if !reasons(across: edge, changed: fromChanged ? edge.from : edge.to, in: diff, breakable: breakable).isEmpty {
                reached.insert(neighbor)
            }
        }
        let byTouch = ranked(Array(touches.keys)) { touches[$0] ?? 0 }
        let untouched = byTouch.filter { !reached.contains($0) }
        let candidates = byTouch.filter(reached.contains) + (includeUntouched ? untouched : [])
        let room = overflow.isEmpty ? max(budget - changed.count, 0) : 0
        let around = Array(candidates.prefix(room))
        overflow += candidates.dropFirst(room)

        let drawn = changed + around.sorted { (position[$0] ?? 0) < (position[$1] ?? 0) }
        let drawnSet = Set(drawn)
        let items = drawn.compactMap { id -> GraphLayout.Item? in
            guard let node = byID[id] else { return nil }
            var flags: GraphLayout.Flags = []
            if findings(under: id) > 0 { flags.insert(.dirty) }
            if rank(of: node) == 0 { flags.insert(.private) }
            return GraphLayout.Item(unit: .type(id), label: label(node), detail: Wording.kind(of: node), flags: flags, group: node.module)
        }
        let links = edges.filter { edge in
            drawnSet.contains(edge.from) && drawnSet.contains(edge.to) && (changedSet.contains(edge.from) || changedSet.contains(edge.to))
        }.map { edge in
            GraphLayout.Link(from: edge.from, to: edge.to, dashed: edge.roles == [.body],
                             title: "\(label(of: .type(edge.from))) \(Wording.words(edge.roles)) \(label(of: .type(edge.to)))")
        }
        return ChangesFigure(layout: GraphLayout.layered(items, links), changed: changed.count, around: around.count, overflow: overflow,
                             untouched: includeUntouched ? [] : untouched)
    }
}

extension Atlas {
    /// How the changes since a base reach a type that did not change itself: each new or changed
    /// dependency it has with a changed type, and each use it makes of a changed type that can break
    /// on the change, as ``changesFigure(_:minimumRank:budget:includeUntouched:)`` decides it.
    ///
    /// - Parameters:
    ///   - id: A node id.
    ///   - diff: How the interface differs from the base.
    /// - Returns: The reasons, in the order the dependencies are listed and, for each, the order the
    ///   changed type declares what changed; empty for a type that changed itself or that no change reaches.
    public func changeReasons(of id: String, in diff: InterfaceDiff) -> [ChangeReason] {
        let changed = Set(diff.nodes.filter { $0.change != .removed }.map(\.node.id))
        guard !changed.contains(id) else { return [] }
        let breakable = Breakable(diff)
        return edges.flatMap { edge -> [ChangeReason] in
            if edge.from == id, changed.contains(edge.to) { return reasons(across: edge, changed: edge.to, in: diff, breakable: breakable) }
            if edge.to == id, changed.contains(edge.from) { return reasons(across: edge, changed: edge.from, in: diff, breakable: breakable) }
            return []
        }
    }

    /// What a user can break on in each changed type: the type's own declaration, and the members
    /// whose signature changed or that are gone. A member added breaks no one, and a change to docs
    /// alone breaks no one.
    private struct Breakable {
        /// The changed types whose own declaration changed, by id.
        var declarations: [String: InterfaceDiff.DeclarationChange] = [:]
        /// The members of each changed type that changed signature or are gone, in source order.
        var members: [String: [InterfaceDiff.DeclarationChange]] = [:]

        /// Gathers what can break from a diff.
        ///
        /// - Parameter diff: How the interface differs from the base.
        init(_ diff: InterfaceDiff) {
            for node in diff.nodes where node.change == .changed {
                for declaration in node.declarations where declaration.change == .removed || declaration.signatureChanged {
                    if ["struct", "class", "enum", "protocol", "actor"].contains(declaration.keyword) {
                        declarations[node.node.id] = declaration
                    } else {
                        members[node.node.id, default: []].append(declaration)
                    }
                }
            }
        }
    }

    /// How a change reaches the other end of one dependency of a changed type: the dependency itself
    /// when it is new or changed, and when the other end uses the changed type, its declaration if that
    /// changed and each changed member the other end's declarations reach by name.
    ///
    /// - Parameters:
    ///   - edge: A dependency with the changed type at one end.
    ///   - changed: The id of the changed type at its end.
    ///   - diff: How the interface differs from the base.
    ///   - breakable: What can break in each changed type.
    /// - Returns: The reasons, the dependency's first.
    private func reasons(across edge: Graph.Edge, changed: String, in diff: InterfaceDiff, breakable: Breakable) -> [ChangeReason] {
        var reasons: [ChangeReason] = []
        if let change = diff.change(from: edge.from, to: edge.to), change.change != .removed {
            reasons.append(ChangeReason(changed: changed, kind: .dependency(change), via: []))
        }
        guard edge.to == changed else { return reasons }
        if let declaration = breakable.declarations[changed] {
            reasons.append(ChangeReason(changed: changed, kind: .declaration(declaration), via: []))
        }
        guard let members = breakable.members[changed] else { return reasons }
        let group = group(edge.from)
        var reachedBy: [String: [String]] = [:]
        for contract in ([group.head].compactMap { $0 } + group.members).map(\.contract) {
            for name in Set(contract.mentions.filter { $0.resolved == changed }.flatMap(\.members)) {
                reachedBy[name, default: []].append(contract.qualifiedName)
            }
        }
        for member in members {
            guard let via = reachedBy[String(member.name.prefix { $0 != "(" })] else { continue }
            reasons.append(ChangeReason(changed: changed, kind: .member(member), via: via))
        }
        return reasons
    }
}
