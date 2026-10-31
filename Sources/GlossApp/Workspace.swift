import AppKit
import GlossCore
import GlossMap
import Observation

/// One open package: its interface, what is selected, and which level of the map is drawn.
///
/// Every decision about what to show comes from ``GlossMap/Atlas``; the workspace only remembers the
/// reader's place in it, so the app and the page never disagree about the system.
@MainActor @Observable
final class Workspace {
    /// What the details pane shows and the map lights.
    enum Selection: Hashable {
        case start
        case modules
        case module(String)
        case folder(String, String)
        case type(String)
    }

    /// What the map pane draws for the current level.
    struct Drawing {
        var layout = GraphLayout()
        /// The path from the widest level to this one, each step with the level it returns to.
        var crumbs: [(scope: String, label: String)] = []
        var caption = ""
        var loose: [MapScope.Unit] = []
        var overflow: [MapScope.Unit] = []
    }

    /// The level id of the selected type's focus, beside the atlas's own levels.
    static let focus = "focus"

    private(set) var root: URL?
    private(set) var name = "gloss"
    private(set) var interface: Interface?
    private(set) var atlas: Atlas?
    private(set) var scopes: [MapScope] = []
    private(set) var levels: [String: [String]] = [:]
    private(set) var isLoading = false
    private(set) var problem: String?
    private(set) var selection = Selection.start
    private(set) var scopeID = ""
    private(set) var drawing = Drawing()
    private var focusFrom: String?

    var includeBody = false { didSet { redraw() } }
    /// The narrowest access shown, as ``GlossCore/Contract/rank(_:)``: 3 for public, 1 for internal, 0 for all.
    var minimumRank = 3 { didSet { redraw() } }
    var search = ""
    var findingsOnly = false
    /// The chip under the pointer, whose box the map lights instead of what the details pane shows.
    var hovered: String?
    /// What hovering a box or a list row shows in the details pane in place of the selection.
    private(set) var preview: Selection?
    private var showing: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// The defaults key of the last folder opened, which the next launch reopens.
    private static let lastFolderKey = "lastFolder"

    /// Opens the folder named by `--root <folder>`, or else the folder opened last, if either exists.
    ///
    /// - Parameter arguments: The process arguments, the executable first.
    init(arguments: [String]) {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let given = arguments.firstIndex(of: "--root").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        let candidates = [given, UserDefaults.standard.string(forKey: Self.lastFolderKey)].compactMap { $0 }
        let folder = candidates
            .map { URL(fileURLWithPath: $0, relativeTo: current).standardizedFileURL }
            .first { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        if let folder { open(folder) }
    }

    // MARK: Loading

    /// Everything read from one folder, built off the main thread.
    private struct Loaded: Sendable {
        var interface: Interface
        var atlas: Atlas
        var scopes: [MapScope]
        var levels: [String: [String]]

        /// Reads a package: its `Sources` directory when it has one, and otherwise the folder itself.
        ///
        /// - Parameter root: The folder.
        /// - Returns: The interface and its arrangement, with files named relative to `root`.
        /// - Throws: ``GlossCore/SourceFiles/Missing`` when the folder is gone.
        static func read(_ root: URL) throws -> Loaded {
            let sources = root.appendingPathComponent("Sources")
            let scanned = FileManager.default.fileExists(atPath: sources.path) ? sources : root
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            let files = try SourceFiles.swiftFiles(under: scanned.path, includeTests: false)
            let pairs = files.compactMap { file -> (file: String, source: String)? in
                guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
                return (file.hasPrefix(prefix) ? String(file.dropFirst(prefix.count)) : file, source)
            }
            let interface = Interface.build(sources: pairs)
            let atlas = Atlas(interface)
            let scopes = atlas.mapScopes()
            return Loaded(interface: interface, atlas: atlas, scopes: scopes, levels: atlas.levelsDrawing(scopes))
        }
    }

    /// Opens a folder and reads it.
    ///
    /// - Parameter url: The package folder.
    func open(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey)
        root = url
        name = url.lastPathComponent
        selection = .start
        scopeID = ""
        reload()
    }

    /// Asks for a folder to open.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        panel.message = "Choose a Swift package. gloss reads its Sources folder when it has one."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// Reads the open folder again, keeping the selection and the map level when they still exist.
    func reload() {
        guard let root else { return }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try Loaded.read(root) } }.value
            guard root == self.root else { return }
            isLoading = false
            switch result {
            case .success(let loaded):
                problem = nil
                interface = loaded.interface
                atlas = loaded.atlas
                scopes = loaded.scopes
                levels = loaded.levels
                restore()
                snapshotIfAsked()
            case .failure:
                problem = "There is nothing at \(root.path)."
            }
        }
    }

    private func restore() {
        let stillThere: Bool
        switch selection {
        case .start, .modules: stillThere = true
        case .module(let module): stillThere = atlas?.modules.contains(module) == true
        case .folder(let module, let folder): stillThere = scopes.contains { $0.kind == .folder(module, folder) }
        case .type(let id): stillThere = atlas?.byID[id] != nil
        }
        if !stillThere { selection = .start }
        if scopeID != Self.focus || !stillThere, !scopes.contains(where: { $0.id == scopeID }) {
            scopeID = scope(for: selection)
        }
        redraw()
    }

    // MARK: Selection and levels

    /// Shows something in the details pane, and moves the map to a level that draws it.
    ///
    /// - Parameter target: The start page, a module, a folder, or a type.
    ///
    /// A module or folder draws its own level. A type keeps the current level when that level draws it,
    /// re-centers the focus when focused, and otherwise moves to the widest level that draws it.
    func select(_ target: Selection) {
        showing?.cancel()
        hiding?.cancel()
        preview = nil
        selection = target
        scopeID = scope(for: target)
        redraw()
    }

    /// Selects what a box on the map stands for.
    ///
    /// - Parameter unit: A type, module, or folder box.
    func select(unit: MapScope.Unit) {
        select(Self.selection(of: unit))
    }

    /// What selecting a box shows.
    ///
    /// - Parameter unit: A type, module, or folder box.
    /// - Returns: The matching selection.
    static func selection(of unit: MapScope.Unit) -> Selection {
        switch unit {
        case .type(let id): .type(id)
        case .module(let module): .module(module)
        case .folder(let module, let folder): .folder(module, folder)
        }
    }

    // MARK: Previewing

    /// What the details pane shows: the preview while there is one, and otherwise the selection.
    var shown: Selection {
        preview ?? selection
    }

    /// Starts previewing something once the pointer has rested on it, so passing over boxes on the way
    /// elsewhere does not flicker the details pane. While a preview shows, the next one follows faster.
    ///
    /// - Parameter target: What a hovered box or list row stands for.
    func hoverBegan(_ target: Selection) {
        hiding?.cancel()
        showing?.cancel()
        let delay = preview == nil ? 140 : 40
        showing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            preview = target == selection ? nil : target
        }
    }

    /// Returns the details pane to the selection shortly after the pointer leaves a box or list row,
    /// unless it moves into the details pane first.
    func hoverEnded() {
        showing?.cancel()
        endPreviewSoon()
    }

    /// Keeps a preview while the pointer is in the details pane, so it can be read, and ends it when
    /// the pointer leaves.
    ///
    /// - Parameter inside: `true` when the pointer entered the pane, `false` when it left.
    func detailsHovered(_ inside: Bool) {
        if inside {
            showing?.cancel()
            hiding?.cancel()
        } else if preview != nil {
            endPreviewSoon()
        }
    }

    private func endPreviewSoon() {
        hiding?.cancel()
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            preview = nil
        }
    }

    /// Returns to a level named in the map's breadcrumbs.
    ///
    /// - Parameter scope: A level id from ``Drawing/crumbs``.
    func step(to scope: String) {
        guard let level = scopes.first(where: { $0.id == scope }) else { return }
        if scopeID == Self.focus, scope == focusFrom {
            zoom(to: scope)
            return
        }
        switch level.kind {
        case .allTypes: select(.start)
        case .modules: select(scopes.first?.id == level.id ? .start : .modules)
        case .module(let module): select(.module(module))
        case .folder(let module, let folder): select(.folder(module, folder))
        }
    }

    private func scope(for target: Selection) -> String {
        let first = scopes.first?.id ?? ""
        switch target {
        case .start:
            return first
        case .modules:
            return scopes.first { $0.kind == .modules }?.id ?? first
        case .module(let module):
            return scopes.first { $0.kind == .module(module) }?.id ?? first
        case .folder(let module, let folder):
            return scopes.first { $0.kind == .folder(module, folder) }?.id ?? scope(for: .module(module))
        case .type(let id):
            if scopeID == Self.focus { return Self.focus }
            guard let root = atlas?.byID[id]?.root, let drawing = levels[root], !drawing.isEmpty else { return scopeID.isEmpty ? first : scopeID }
            return drawing.contains(scopeID) ? scopeID : drawing[0]
        }
    }

    private func parent(of scope: String) -> String? {
        scope == Self.focus ? focusFrom : scopes.first { $0.id == scope }?.parent
    }

    private func isAncestor(_ wider: String, of narrower: String) -> Bool {
        var step = parent(of: narrower)
        while let current = step {
            if current == wider { return true }
            step = parent(of: current)
        }
        return false
    }

    /// The next narrower level toward the selection: a module, a folder, and last the selected type's focus.
    var zoomInTarget: String? {
        guard case .type(let id) = selection else {
            let own = scope(for: selection)
            return own != scopeID && isAncestor(scopeID, of: own) ? own : nil
        }
        if scopeID == Self.focus { return nil }
        guard let root = atlas?.byID[id]?.root else { return nil }
        let ladder = (levels[root] ?? []) + [Self.focus]
        if let at = ladder.firstIndex(of: scopeID) { return ladder[at + 1] }
        return ladder.dropLast().first { isAncestor(scopeID, of: $0) } ?? Self.focus
    }

    /// The level the current one zooms out to.
    var zoomOutTarget: String? {
        parent(of: scopeID)
    }

    /// Moves the map to a level without changing the selection.
    ///
    /// - Parameter target: A level id, or ``focus``; `nil` does nothing.
    func zoom(to target: String?) {
        guard let target else { return }
        if target == Self.focus, scopeID != Self.focus { focusFrom = scopeID }
        scopeID = target
        redraw()
    }

    /// The box the map lights: a hovered chip's, or else what the details pane shows, as the current
    /// level draws it.
    var litID: String? {
        if let hovered { return hovered }
        switch shown {
        case .start, .modules: return nil
        case .module(let module): return MapScope.Unit.module(module).id
        case .folder(let module, let folder): return MapScope.Unit.folder(module, folder).id
        case .type(let id): return scopeID == Self.focus ? id : atlas?.byID[id]?.root
        }
    }

    private func redraw() {
        guard let atlas else {
            drawing = Drawing()
            return
        }
        if scopeID == Self.focus, case .type(let id) = selection, let node = atlas.byID[id],
           let focus = atlas.focus(on: id, includeBody: includeBody, minimumRank: minimumRank) {
            let from = scopes.first { $0.id == focusFrom } ?? scopes.first
            let through = includeBody ? "" : " through a signature"
            let users = focus.incoming == 0 ? "Nothing uses it" + through
                : (focus.incoming == 1 ? "1 type uses it" : "\(focus.incoming) types use it") + through
            let needs = focus.outgoing == 0 ? "it depends on nothing scanned" : "it depends on \(focus.outgoing)"
            let hidden = focus.hidden > 0 ? ". \(focus.hidden) more are not drawn; the details list them all." : "."
            drawing = Drawing(layout: focus.layout,
                              crumbs: [(from?.id ?? "", from?.label ?? "Map"), (Self.focus, "\(atlas.label(node)) and its neighbors")],
                              caption: users + "; " + needs + hidden)
            return
        }
        guard let scope = scopes.first(where: { $0.id == scopeID }) ?? scopes.first else {
            drawing = Drawing()
            return
        }
        let figure = atlas.figure(scope, includeBody: includeBody)
        drawing = Drawing(layout: GraphLayout.layered(figure.items, figure.links),
                          crumbs: scope.path.compactMap { id in scopes.first { $0.id == id }.map { ($0.id, $0.label) } },
                          caption: "\(figure.items.count) boxes, \(figure.links.count) dependencies.",
                          loose: figure.loose, overflow: figure.overflow)
    }

    // MARK: Reading

    /// The window's subtitle: the size of the interface and how many findings it has.
    var subtitle: String {
        guard let interface else { return isLoading ? "Reading…" : "" }
        let findings = interface.assessments.reduce(0) { $0 + $1.findings.count }
        return "\(interface.contracts.count) declarations · \(findings) finding\(findings == 1 ? "" : "s")"
    }

    /// Whether the access filter shows a node.
    ///
    /// - Parameter node: A node.
    /// - Returns: `true` when the node or one of its members is at least as wide as ``minimumRank``.
    func isShown(_ node: Graph.Node) -> Bool {
        (atlas?.rank(of: node) ?? 0) >= minimumRank
    }

    /// The nodes the list shows for one module, after the access filter, the findings filter, and the search.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Nodes in graph order.
    func listed(in module: String) -> [Graph.Node] {
        guard let atlas else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return atlas.nodes.filter { node in
            guard node.module == module, isShown(node) else { return false }
            let group = atlas.group(node.id)
            if findingsOnly, group.findingCount == 0 { return false }
            guard !query.isEmpty else { return true }
            return ([node.name] + group.members.map(\.name)).contains { $0.lowercased().contains(query) }
        }
    }

    /// Opens a declaration's file at its line in Xcode, or in the default editor without Xcode.
    ///
    /// - Parameters:
    ///   - file: The file path as the interface names it, relative to the open folder.
    ///   - line: The 1-based line.
    func reveal(_ file: String, line: Int) {
        guard let root else { return }
        let url = root.appendingPathComponent(file)
        let xed = Process()
        xed.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
        xed.arguments = ["--line", String(line), url.path]
        do {
            try xed.run()
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}
