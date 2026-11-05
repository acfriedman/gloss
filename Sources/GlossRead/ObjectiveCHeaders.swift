/// The types an Objective-C header declares, by the names Swift imports them as, so a Swift doc's link
/// to one resolves in a project that mixes the two languages, though gloss reads no Objective-C.
///
/// Only names are read: a class, a protocol, an `NS_ENUM` or `NS_OPTIONS`, a typed enum, an
/// `NS_ERROR_ENUM`, which Swift imports as a type named for its domain with the codes nested as `Code`,
/// and any type an `NS_SWIFT_NAME` renames. Members are not, so a link names an Objective-C type's member
/// on trust.
public enum ObjectiveCHeaders {
    /// Reads the type names one header declares.
    ///
    /// - Parameter source: The header's text.
    /// - Returns: Each name once, in the order the header first declares it; comments and forward
    ///   declarations such as `@class Cart;` declare none.
    public static func typeNames(in source: String) -> [String] {
        let code = withoutComments(source)
        var names: [String] = []
        func add(_ name: Substring) {
            let name = String(name)
            if !names.contains(name) { names.append(name) }
        }
        for match in code.matches(of: /@interface\s+([A-Za-z_]\w*)/) { add(match.1) }
        for match in code.matches(of: /@protocol\s+([A-Za-z_]\w*)\b(?!\s*[;,])/) { add(match.1) }
        for match in code.matches(of: /NS_(?:ENUM|OPTIONS|CLOSED_ENUM)\s*\(\s*\w+\s*,\s*([A-Za-z_]\w*)\s*\)/) { add(match.1) }
        for match in code.matches(of: /NS_ERROR_ENUM\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)/) {
            // Swift names the error for its domain, `FulfillmentErrorDomain` becoming `FulfillmentError`.
            let domain = match.1
            add(domain.hasSuffix("Domain") ? domain.dropLast("Domain".count) : domain)
            add(match.2)
        }
        for match in code.matches(of: /([A-Za-z_]\w*)\s+NS_(?:TYPED_ENUM|TYPED_EXTENSIBLE_ENUM|STRING_ENUM|EXTENSIBLE_STRING_ENUM)/) {
            add(match.1)
        }
        // A renamed method's Swift name starts lowercase, and only a type's is wanted.
        for match in code.matches(of: /NS_SWIFT_NAME\s*\(\s*([A-Z]\w*)/) { add(match.1) }
        return names
    }

    /// Removes comments, so a declaration commented out declares nothing.
    ///
    /// - Parameter source: A header's text.
    /// - Returns: The text with each `/* */` and `//` comment replaced by a space.
    static func withoutComments(_ source: String) -> String {
        source.replacing(/\/\*[\s\S]*?\*\//, with: " ").replacing(/\/\/[^\n]*/, with: " ")
    }
}
