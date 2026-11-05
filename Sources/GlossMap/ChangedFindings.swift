import GlossLint
import GlossModel

/// The findings that fall on what a change touched: the declarations it added or changed, bodies
/// included, so a commit hook or a pull request's check judges the change and not the code around it.
///
/// Code nobody touched keeps its old findings without failing the change, so a project can bring its
/// house style in as it goes, while a declaration that changed at all answers to the style in full. A
/// type that only moved, or a member that is gone, touches nothing.
public struct ChangedFindings: Sendable {
    /// The lines of each declaration the change added or changed, by file as the head names it.
    public private(set) var touched: [String: [ClosedRange<Int>]] = [:]
    /// How many declarations the change added or changed.
    public private(set) var count = 0

    /// Gathers where a change's new and changed declarations are.
    ///
    /// - Parameter diff: How the head differs from the base.
    public init(_ diff: InterfaceDiff) {
        for node in diff.nodes {
            for declaration in node.declarations where declaration.change != .removed {
                guard let place = declaration.place else { continue }
                touched[place.file, default: []].append(place.lines)
                count += 1
            }
        }
    }

    /// Keeps the diagnostics on a new or changed declaration: on its doc comment or on the declaration.
    ///
    /// - Parameter diagnostics: What the lint found in the head.
    /// - Returns: The ones on lines a touched declaration takes, in the same order.
    public func filter(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        diagnostics.filter { diagnostic in touched[diagnostic.file]?.contains { $0.contains(diagnostic.line) } ?? false }
    }
}
