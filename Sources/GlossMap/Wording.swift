import GlossRead
import GlossModel

/// The words every front end uses for the model: roles, kinds, folders, and one-line summaries.
public enum Wording {
    /// Words for each role, read as "the source … the target".
    public static let roleWords: [Mention.Role: String] = [
        .conformance: "conforms to", .property: "holds", .parameter: "takes",
        .returns: "returns", .throws: "throws", .body: "uses"
    ]

    /// Words for an edge's roles, in model order, read as one English verb phrase sharing its object.
    ///
    /// - Parameter roles: The roles of one edge.
    /// - Returns: `holds`, `takes and uses`, `holds, takes, and returns`, and the like.
    public static func words(_ roles: [Mention.Role]) -> String {
        list(roles.compactMap { roleWords[$0] })
    }

    /// Joins words the way English lists them, with a serial comma.
    ///
    /// - Parameter words: The words in order.
    /// - Returns: `a`, `a and b`, or `a, b, and c`; empty for none.
    public static func list(_ words: [String]) -> String {
        guard let last = words.last else { return "" }
        switch words.count {
        case 1: return last
        case 2: return words[0] + " and " + last
        default: return words.dropLast().joined(separator: ", ") + ", and " + last
        }
    }

    /// The kind word a node is shown with.
    ///
    /// - Parameter node: A node.
    /// - Returns: Its keyword, or `file scope` for a module's file-scope declarations.
    public static func kind(of node: Graph.Node) -> String {
        node.keyword == "file" ? "file scope" : node.keyword
    }

    /// How a folder is named.
    ///
    /// - Parameter folder: The folder name; empty for files directly in the module's directory.
    /// - Returns: `Name/`, or `(module root)` for the module's own directory.
    public static func folderLabel(_ folder: String) -> String {
        folder.isEmpty ? "(module root)" : folder + "/"
    }

    /// The first sentence of a summary, for one-line listings; a period inside a code span does not end it.
    ///
    /// - Parameter text: A summary paragraph.
    /// - Returns: Text up to and including the first sentence-ending period, or all of it.
    public static func firstSentence(_ text: String) -> String {
        var inCode = false
        var previous: Character = " "
        for (offset, character) in text.enumerated() {
            if character == "`" { inCode.toggle() }
            let next = text.dropFirst(offset + 1).first
            if !inCode, character == ".", next == nil || next == " ", previous != "." {
                return String(text.prefix(offset + 1))
            }
            previous = character
        }
        return text
    }

    /// Whether a declaration is something a caller invokes.
    ///
    /// - Parameter keyword: The declaration's introducing keyword.
    /// - Returns: `true` for functions, initializers, subscripts, and macros.
    public static func isCallable(_ keyword: String) -> Bool {
        ["func", "init", "subscript", "macro"].contains(keyword)
    }
}
