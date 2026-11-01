import AppKit
import GlossCore
import GlossMap
import Observation
import SwiftUI

/// One open package: its interface, what is selected, and which level of the map is drawn.
///
/// Every decision about what to show comes from ``GlossMap/Atlas``; the workspace only remembers the
/// reader's place in it, so the app and the page never disagree about the system.
@MainActor @Observable
final class Workspace {
    /// What the details pane shows and the map lights.
    enum Selection: Hashable {
        /// The overview of each module's entry points, drawn at the map's default level.
        case overview
        /// Every module with the modules it depends on, drawn at the modules level.
        case modules
        /// One module, by name, drawn at its own level.
        case module(String)
        /// One source folder, as the module name and the folder name, empty for the module's own directory.
        /// The map draws the folder's level when the module is drawn as folders, and the module's otherwise.
        case folder(String, String)
        /// One type by node id, nested or not, whose root's box the map lights, or its own box in the focus.
        case type(String)
    }

    /// What the map pane draws for the current level.
    struct Drawing {
        /// The placed boxes and curves of the level, or of the selected type and its neighbors in the focus.
        var layout = GraphLayout()
        /// The path from the widest level to this one, each step with the level it returns to.
        var crumbs: [(scope: String, label: String)] = []
        /// The line beside the breadcrumbs that counts the level's boxes and dependencies, or in the focus
        /// says what uses the type and what it depends on.
        var caption = ""
        /// The level's boxes with no edge, listed under the map as not connected; empty in the focus.
        var loose: [MapScope.Unit] = []
        /// The level's least connected boxes past ``GlossMap/Atlas/mapBudget``, listed under the map instead
        /// of drawn; in a reach, the first step's types left out; empty in the neighbors focus.
        var overflow: [MapScope.Unit] = []
        /// In a reach, the steps drawn and the steps there are in all, for the depth stepper; `nil` otherwise.
        var depth: (drawn: Int, total: Int)?
    }

    /// What the focus draws around the selected type.
    enum FocusMode: Hashable, CaseIterable {
        /// What uses the type above it and what it depends on below it, one step each way unless the
        /// depth stepper goes further.
        case neighbors
        /// Everything the type depends on, step by step, below it.
        case below
        /// Everything that uses the type, step by step, above it.
        case above

        /// The way the mode's reach follows dependencies.
        var direction: ReachDirection {
            switch self {
            case .neighbors: .both
            case .below: .dependencies
            case .above: .users
            }
        }
    }

    /// The level id of the selected type's focus, beside the atlas's own levels.
    static let focus = "focus"

    /// What the focus draws: the type's neighbors, or all it reaches one way.
    var focusMode = FocusMode.neighbors { didSet { redraw() } }
    /// The steps a reach draws, chosen with the depth stepper and kept across modes until another type is
    /// selected; `nil`, the default, draws 1 for Neighbors and as many whole steps as fit
    /// ``GlossMap/Atlas/mapBudget`` for the others.
    var reachDepth: Int? { didSet { redraw() } }

    /// The open folder, or `nil` before one is opened; file paths in the interface are relative to it.
    private(set) var root: URL?
    /// The open folder's name, which titles the window.
    private(set) var name = "gloss"
    /// What reading the folder produced, or `nil` until the first read finishes.
    private(set) var interface: Interface?
    /// The interface arranged for reading, which every pane draws from.
    private(set) var atlas: Atlas?
    /// The map's levels, the default first, as ``GlossMap/Atlas/mapScopes()`` orders them.
    private(set) var scopes: [MapScope] = []
    /// The levels that draw each root type as itself, keyed by root id, widest first.
    private(set) var levels: [String: [String]] = [:]
    /// Whether a read is under way, which disables Reload and shows progress before the first one lands.
    private(set) var isLoading = false
    /// Why the folder could not be read, shown where the panes would be, or `nil` when it could.
    private(set) var problem: String?
    /// What the details pane shows when nothing is previewed, and what the map lights.
    private(set) var selection = Selection.overview
    /// The level the map draws: an id from ``scopes``, or ``focus``.
    private(set) var scopeID = ""
    /// The map for ``scopeID``, laid out once per change rather than per frame.
    private(set) var drawing = Drawing()
    private var focusFrom: String?

    /// The narrowest access shown, as ``GlossCore/Contract/rank(_:)``: 3 for public, 1 for internal, 0 for all.
    var minimumRank = Atlas.defaultMinimumRank { didSet { redraw() } }
    /// The list's search text, which keeps types whose name or a member's name contains it, ignoring case.
    var search = ""
    /// Whether the list keeps only types with findings, their members' included, from the checkbox under it.
    var findingsOnly = false
    /// Whether Open Quickly is showing over the window.
    var isQuickOpenShown = false
    /// Which panes the window shows: all three, or the details and the map with the list hidden.
    var columns = NavigationSplitViewVisibility.all
    /// The chip under the pointer, whose box the map lights instead of what the details pane shows.
    var hovered: String?
    /// What hovering a box or a list row shows in the details pane in place of the selection.
    private(set) var preview: Selection?
    private var showing: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// The defaults key of the last folder opened, which the next launch reopens.
    private static let lastFolderKey = "lastFolder"

    /// The folder to open once the window appears.
    private var launchFolder: URL?

    /// Chooses the folder named by `--root <folder>`, or else the folder opened last, if either exists.
    /// Reading waits for ``start()``, since SwiftUI may build the app, and with it a workspace, more
    /// than once, and only the workspace the window keeps should read anything.
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
        launchFolder = folder
    }

    /// Opens the launch folder, once.
    func start() {
        guard let folder = launchFolder else { return }
        launchFolder = nil
        open(folder)
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
        if !Self.isSnapshotting { UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey) }
        root = url
        name = url.lastPathComponent
        selection = .overview
        scopeID = ""
        back.removeAll()
        forward.removeAll()
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
        case .overview, .modules: stillThere = true
        case .module(let module): stillThere = atlas?.modules.contains(module) == true
        case .folder(let module, let folder): stillThere = scopes.contains { $0.kind == .folder(module, folder) }
        case .type(let id): stillThere = atlas?.byID[id] != nil
        }
        if !stillThere { selection = .overview }
        if scopeID != Self.focus || !stillThere, !scopes.contains(where: { $0.id == scopeID }) {
            scopeID = scope(for: selection)
        }
        redraw()
    }

    // MARK: Selection and levels

    /// Shows something in the details pane, and moves the map to a level that draws it.
    ///
    /// - Parameter target: The overview, a module, a folder, or a type.
    ///
    /// A module or folder draws its own level. A type keeps the current level when that level draws it,
    /// re-centers the focus when focused, and otherwise moves to the widest level that draws it.
    func select(_ target: Selection) {
        navigate {
            showing?.cancel()
            hiding?.cancel()
            preview = nil
            let rerooted = target != selection
            selection = target
            if case .type(let id) = target { reveal(id) }
            scopeID = scope(for: target)
            // A new type starts at the default depth; switching modes keeps the chosen one.
            if rerooted, reachDepth != nil { reachDepth = nil } else { redraw() }
        }
    }

    /// Selects a type and zooms the map to it and its neighbors, from whatever level was showing;
    /// zooming out returns to a level that draws the type.
    ///
    /// - Parameter id: A node id.
    func focus(on id: String) {
        navigate {
            select(.type(id))
            zoom(to: Self.focus)
        }
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

    // MARK: History

    /// A place the reader has been: what was selected, the level the map drew, and the depth chosen there.
    private struct Place: Equatable {
        var selection: Selection
        var scopeID: String
        var focusFrom: String?
        var reachDepth: Int?
    }

    /// Where the reader is now.
    private var here: Place {
        Place(selection: selection, scopeID: scopeID, focusFrom: focusFrom, reachDepth: reachDepth)
    }

    /// The places Back returns to, the most recent last.
    private var back: [Place] = []
    /// The places Forward returns to after going back, the nearest last.
    private var forward: [Place] = []
    /// How many navigations are under way, so one made of others records a single step.
    private var navigating = 0

    /// Whether there is a place to go back to.
    var canGoBack: Bool { !back.isEmpty }
    /// Whether there is a place to go forward to.
    var canGoForward: Bool { !forward.isEmpty }

    /// Returns to the place before the last navigation.
    func goBack() {
        guard let place = back.popLast() else { return }
        forward.append(here)
        go(to: place)
    }

    /// Returns to the place the last Back left.
    func goForward() {
        guard let place = forward.popLast() else { return }
        back.append(here)
        go(to: place)
    }

    /// Runs one navigation and, once it lands somewhere new, records where it left as the place to go
    /// back to; going somewhere new forgets the places ahead.
    ///
    /// - Parameter change: The navigation, which may itself be made of others.
    private func navigate(_ change: () -> Void) {
        let before = here
        navigating += 1
        change()
        navigating -= 1
        guard navigating == 0, here != before else { return }
        back.append(before)
        forward.removeAll()
    }

    private func go(to place: Place) {
        showing?.cancel()
        hiding?.cancel()
        preview = nil
        selection = place.selection
        if case .type(let id) = place.selection { reveal(id) }
        scopeID = place.scopeID
        focusFrom = place.focusFrom
        if reachDepth != place.reachDepth { reachDepth = place.reachDepth }
        // A place read before a reload may name what is gone; it falls back as a reload does.
        restore()
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
        navigate {
            if scopeID == Self.focus, scope == focusFrom {
                zoom(to: scope)
                return
            }
            switch level.kind {
            case .allTypes: select(.overview)
            case .modules: select(scopes.first?.id == level.id ? .overview : .modules)
            case .module(let module): select(.module(module))
            case .folder(let module, let folder): select(.folder(module, folder))
            }
        }
    }

    private func scope(for target: Selection) -> String {
        let first = scopes.first?.id ?? ""
        switch target {
        case .overview:
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

    // The focus zooms out to the level it was entered from, unless the focus has since moved to a
    // type that level does not draw; then to the narrowest level that draws it, one step back up the
    // ladder zooming in climbs.
    private func parent(of scope: String) -> String? {
        guard scope == Self.focus else { return scopes.first { $0.id == scope }?.parent }
        guard case .type(let id) = selection, let root = atlas?.byID[id]?.root,
              let drawing = levels[root], !drawing.isEmpty else { return focusFrom }
        if let from = focusFrom, drawing.contains(from) { return from }
        return drawing.last
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
        navigate {
            if target == Self.focus, scopeID != Self.focus { focusFrom = scopeID }
            scopeID = target
            redraw()
        }
    }

    /// The box the map lights: a hovered chip's, or else what the details pane shows, as the current
    /// level draws it.
    var litID: String? {
        if let hovered { return hovered }
        switch shown {
        case .overview, .modules: return nil
        case .module(let module): return MapScope.Unit.module(module).id
        case .folder(let module, let folder): return MapScope.Unit.folder(module, folder).id
        case .type(let id):
            guard scopeID == Self.focus else { return atlas?.byID[id]?.root }
            // A focus is about the whole reach, so its root is marked, not lit; a previewed box still lights.
            return preview == nil ? nil : id
        }
    }

    /// The box the focus grows from, drawn as the current one without dimming the rest; `nil` outside it.
    var anchorID: String? {
        guard scopeID == Self.focus, case .type(let id) = selection else { return nil }
        return id
    }

    private func redraw() {
        guard let atlas else {
            drawing = Drawing()
            return
        }
        // Every focus is a reach: Neighbors goes both ways from depth 1, and the other two fit the budget.
        if scopeID == Self.focus, case .type(let id) = selection, let node = atlas.byID[id],
           let reach = atlas.reach(from: id, toward: focusMode.direction,
                                   depth: reachDepth ?? (focusMode == .neighbors ? 1 : nil), minimumRank: minimumRank) {
            let from = scopes.first { $0.id == focusFrom } ?? scopes.first
            let what = switch focusMode {
            case .neighbors: "its neighbors"
            case .below: "all it depends on"
            case .above: "all that uses it"
            }
            let counted = focusMode == .neighbors ? "\(reach.above) above, \(reach.below) below" : "\(reach.drawn)"
            let cut = reach.drawn < reach.total ? " · dashed boxes continue" : ""
            drawing = Drawing(layout: reach.layout,
                              crumbs: [(from?.id ?? "", from?.label ?? "Map"), (Self.focus, "\(atlas.label(node)) and \(what)")],
                              caption: "Depth \(reach.depth) of \(reach.totalDepth) · \(counted) of \(reach.total) types" + cut,
                              overflow: reach.overflow.map { .type($0) },
                              depth: (reach.depth, reach.totalDepth))
            return
        }
        guard let scope = scopes.first(where: { $0.id == scopeID }) ?? scopes.first else {
            drawing = Drawing()
            return
        }
        let figure = atlas.figure(scope, includeBody: true)
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

    /// One module's rows in the list, after the access filter, the findings filter, and the search.
    ///
    /// - Parameter module: The module name.
    /// - Returns: Folders and types as ``GlossMap/Atlas/outline(of:showing:)`` arranges them.
    func outline(of module: String) -> [OutlineItem] {
        guard let atlas else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return atlas.outline(of: module) { node in
            guard isShown(node) else { return false }
            let group = atlas.group(node.id)
            if findingsOnly, group.findingCount == 0 { return false }
            guard !query.isEmpty else { return true }
            return ([node.name] + group.members.map(\.name)).contains { $0.lowercased().contains(query) }
        }
    }

    /// Whether the list is shown.
    var showsList: Bool {
        columns != .doubleColumn && columns != .detailOnly
    }

    /// Hides the list, or shows it again, keeping the details and the map.
    func toggleList() {
        columns = showsList ? .doubleColumn : .all
    }

    // MARK: Expanding

    /// The folders and types open in the list. Both start closed, so a large module opens as its
    /// top folders.
    private var expanded: Set<String> = []
    /// The modules closed in the list. Modules start open.
    private var closedModules: Set<String> = []

    /// Whether the search or the findings filter is narrowing the list, which then opens every row
    /// that holds a match.
    var isFiltering: Bool {
        findingsOnly || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether a folder or type row is open, for its disclosure triangle.
    ///
    /// - Parameter id: A row id from an outline.
    /// - Returns: A binding that reads open while filtering, and records the reader's choice otherwise.
    func expansion(of id: String) -> Binding<Bool> {
        Binding(
            get: { self.isFiltering || self.expanded.contains(id) },
            set: { open in
                if open { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        )
    }

    /// Whether a module's section is open.
    ///
    /// - Parameter module: The module name.
    /// - Returns: A binding over the closed modules.
    func expansion(ofModule module: String) -> Binding<Bool> {
        Binding(
            get: { !self.closedModules.contains(module) },
            set: { open in
                if open { self.closedModules.remove(module) } else { self.closedModules.insert(module) }
            }
        )
    }

    /// Opens the rows that hold a type, so selecting it from the map or a chip shows it in the list.
    ///
    /// - Parameter id: A node id.
    private func reveal(_ id: String) {
        guard let atlas, let node = atlas.byID[id] else { return }
        closedModules.remove(node.module)
        expanded.formUnion(atlas.outlineAncestors(of: node))
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
