import GlossCore
import GlossMap
import Foundation

/// What `gloss bench` times: the work the app does for a package, from reading it to drawing every map
/// level and the pages of its busiest types, each phase measured with ``GlossCore/Timing``, so a slow
/// phase shows at a glance and a change that slows one shows against an earlier run.
enum Bench {
    /// How many of the most connected types have their focus and page work timed.
    static let busiest = 20

    /// Runs the app's work on some sources and collects how long each phase took.
    ///
    /// - Parameters:
    ///   - sources: Each file's path and its text.
    ///   - base: A revision to compare with, as the Changes level does, or `nil` for no comparison.
    ///   - directory: A directory inside the repository the revision is read from.
    ///   - includeTests: Whether the base's test directories are read too, as the sources' were.
    /// - Returns: The phases in the order they finished.
    static func run(sources: [(file: String, source: String)], base: String?, in directory: String, includeTests: Bool) -> [Timing.Sample] {
        Timing.record {
            // The calls that can be slow time themselves; only the steps made of several calls are
            // measured here.
            let interface = Interface.build(sources: sources)
            let atlas = Atlas(interface)
            let scopes = atlas.mapScopes()
            _ = atlas.levelsDrawing(scopes)
            for scope in scopes {
                let figure = atlas.figure(scope, includeBody: true)
                _ = GraphLayout.layered(figure.items, figure.links)
            }
            for module in atlas.modules { _ = atlas.outline(of: module, showing: { _ in true }) }
            for query in ["a", "view", "syntax", "zz"] { _ = atlas.quickOpen(query) }
            var degree: [String: Int] = [:]
            for edge in atlas.edges {
                degree[edge.from, default: 0] += 1
                degree[edge.to, default: 0] += 1
            }
            let busiest = atlas.roots.sorted { (degree[$0.id] ?? 0, $1.id) > (degree[$1.id] ?? 0, $0.id) }.prefix(Self.busiest)
            for node in busiest {
                for direction in [ReachDirection.both, .dependencies, .users] {
                    let reach = atlas.reach(from: node.id, toward: direction, depth: direction == .both ? 1 : nil,
                                            minimumRank: Atlas.defaultMinimumRank)
                    if let reach, let far = reach.layout.boxes.last?.item.id {
                        _ = Timing.measure("trails", node.name) { reach.trails(to: far) }
                    }
                }
                let (incoming, outgoing, _) = Timing.measure("neighbors", node.name) { atlas.neighbors(of: node) }
                Timing.measure("why section", "\(node.name), \(incoming.count + outgoing.count) neighbors") {
                    for edge in incoming + outgoing { _ = atlas.reasons(from: edge.from, to: edge.to) }
                }
                let group = atlas.group(node.id)
                let contracts = ([group.head].compactMap { $0 } + group.members).map(\.contract)
                Timing.measure("highlight members", "\(node.name), \(contracts.count) declarations") {
                    for contract in contracts { _ = Highlight.runs(of: contract) }
                }
            }
            guard let base else { return }
            do {
                let read = try Revision.sources(at: base, under: directory, relativeTo: FileManager.default.currentDirectoryPath,
                                                includeTests: includeTests)
                let diff = InterfaceDiff(base: Interface.build(sources: read), head: interface)
                let changes = atlas.changesFigure(diff, minimumRank: Atlas.defaultMinimumRank)
                Timing.measure("marks") {
                    for scope in scopes {
                        for item in atlas.figure(scope, includeBody: true).items { _ = atlas.change(of: item.unit, in: diff) }
                    }
                }
                for box in changes.layout.boxes { _ = atlas.changeReasons(of: box.item.id, in: diff) }
            } catch {
                FileHandle.standardError.write(Data("gloss: cannot read \(base): \(error)\n".utf8))
            }
        }.samples
    }

    /// The phases as a table, one row per phase name in the order each first finished: how many times
    /// it ran, how long in all, and its slowest run with what it worked on.
    ///
    /// - Parameter samples: The phases.
    /// - Returns: The table, columns aligned.
    static func table(_ samples: [Timing.Sample]) -> String {
        var order: [String] = []
        var grouped: [String: [Timing.Sample]] = [:]
        for sample in samples {
            if grouped[sample.name] == nil { order.append(sample.name) }
            grouped[sample.name, default: []].append(sample)
        }
        let width = (order.map(\.count).max() ?? 5) + 2
        var lines = ["phase".padding(toLength: width, withPad: " ", startingAt: 0) + "   runs     total ms       max ms  slowest"]
        for name in order {
            let runs = grouped[name] ?? []
            let total = runs.reduce(0) { $0 + $1.duration.milliseconds }
            let slowest = runs.max { $0.duration < $1.duration }
            lines.append(name.padding(toLength: width, withPad: " ", startingAt: 0)
                         + String(format: "%7d %12.1f %12.1f  %@", runs.count, total, slowest?.duration.milliseconds ?? 0, slowest?.detail ?? ""))
        }
        return lines.joined(separator: "\n")
    }
}
