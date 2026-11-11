import LucidRead
import GlossModel

/// The interface's size and health at a glance: how much it declares and how much of that is public, how
/// much of what must be documented is, and what the linter found, across the interface and module by
/// module, with the types that hold the most findings.
public struct InterfaceSummary: Sendable, Equatable {
    /// One module's share of the interface.
    public struct Module: Sendable, Equatable {
        /// The module's name.
        public var name: String
        /// Its root types: structs, classes, enums, protocols, and actors, not extensions or file scope.
        public var types: Int
        /// Its declarations at internal access or wider.
        public var declarations: Int
        /// Its public and open declarations.
        public var publicDeclarations: Int
        /// Its declarations the rules require a doc on.
        public var owed: Int
        /// Of those, the ones that have a doc.
        public var documented: Int
        /// Its findings.
        public var findings: Int
    }

    /// A count by name, such as findings by rule or declarations by access.
    public struct Count: Sendable, Equatable {
        /// What is counted, such as `missing-doc` or `public`.
        public var name: String
        /// How many.
        public var count: Int
    }

    /// The declarations at internal access or wider.
    public var declarations = 0
    /// The public and open declarations.
    public var publicDeclarations = 0
    /// The root types.
    public var types = 0
    /// The declarations the rules require a doc on.
    public var owed = 0
    /// Of those, the ones that have a doc.
    public var documented = 0
    /// Every finding.
    public var findings = 0
    /// The findings by rule code, most first, ties in code order.
    public var findingsByRule: [Count] = []
    /// Every declaration by access, widest first, only the levels that have any.
    public var byAccess: [Count] = []
    /// Each module's share, in the order the atlas lists modules.
    public var modules: [Module] = []
    /// The root types with findings, by id, most first, at most ``mostFindingsLimit``.
    public var mostFindings: [Count] = []

    /// The most types ``mostFindings`` lists.
    public static let mostFindingsLimit = 10
}

extension Atlas {
    /// Sums up the interface: its size, its documentation, and its findings, overall and by module.
    ///
    /// - Returns: The summary.
    public func interfaceSummary() -> InterfaceSummary {
        let phase = Timing.begin("summary")
        defer { Timing.end(phase, "\(nodes.count) types") }
        var summary = InterfaceSummary()
        var modules: [String: InterfaceSummary.Module] = [:]
        var byRule: [String: Int] = [:]
        var byAccess: [String: Int] = [:]
        for node in nodes {
            var module = modules[node.module] ?? InterfaceSummary.Module(name: node.module, types: 0, declarations: 0, publicDeclarations: 0,
                                                                          owed: 0, documented: 0, findings: 0)
            if node.root == node.id, !["extension", "file"].contains(node.keyword) { module.types += 1 }
            let group = group(node.id)
            for reviewed in [group.head].compactMap({ $0 }) + group.members {
                let rank = Contract.rank(reviewed.access)
                byAccess[reviewed.access, default: 0] += 1
                if rank >= 1 { module.declarations += 1 }
                if rank >= 3 { module.publicDeclarations += 1 }
                if reviewed.requiresDoc {
                    module.owed += 1
                    if reviewed.contract.isDocumented { module.documented += 1 }
                }
                module.findings += reviewed.findings.count
                for finding in reviewed.findings { byRule[finding.rule, default: 0] += 1 }
            }
            modules[node.module] = module
        }
        summary.modules = self.modules.compactMap { modules[$0] }
        for module in summary.modules {
            summary.types += module.types
            summary.declarations += module.declarations
            summary.publicDeclarations += module.publicDeclarations
            summary.owed += module.owed
            summary.documented += module.documented
            summary.findings += module.findings
        }
        summary.findingsByRule = byRule.map { InterfaceSummary.Count(name: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.name) < ($0.count, $1.name) }
        summary.byAccess = ["open", "public", "package", "internal", "fileprivate", "private"].compactMap { access in
            byAccess[access].map { InterfaceSummary.Count(name: access, count: $0) }
        }
        summary.mostFindings = roots.map { InterfaceSummary.Count(name: $0.id, count: findings(under: $0.id)) }
            .filter { $0.count > 0 }
            .sorted { ($1.count, $0.name) < ($0.count, $1.name) }
            .prefix(InterfaceSummary.mostFindingsLimit).map { $0 }
        return summary
    }
}
