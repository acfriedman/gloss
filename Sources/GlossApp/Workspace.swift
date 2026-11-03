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
    enum Selection: Hashable, Sendable {
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
        /// What changed since the comparison's base, drawn as the changes level.
        case changes
    }

    /// What the map pane draws for the current level.
    struct Drawing: Sendable {
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
        /// The reach the focus draws, which says how each drawn type leads back to the root; `nil` at the
        /// other levels.
        var reach: Reach?
        /// At the changes level, the neighbors no change reaches, left undrawn and listed under the map;
        /// empty elsewhere and while they are drawn.
        var untouched: [MapScope.Unit] = []
        /// How each box differs from the base, by box id; empty with no comparison.
        var boxMarks: [String: InterfaceDiff.Change] = [:]
        /// In a focus and at the changes level, how each drawn dependency differs from the base, keyed by
        /// its ends joined with a tab; empty at the other levels, whose edges stand for many at once.
        var edgeMarks: [String: InterfaceDiff.Change] = [:]
    }

    /// What a drawing is made from, read on the main thread so the drawing can be made off it.
    struct DrawingRequest: Sendable {
        /// The arranged interface.
        var atlas: Atlas
        /// The map's levels.
        var scopes: [MapScope]
        /// The level to draw.
        var scopeID: String
        /// What is selected, which a focus grows from.
        var selection: Selection
        /// What a focus draws.
        var focusMode: FocusMode
        /// The steps a reach draws, or `nil` for the default.
        var reachDepth: Int?
        /// The narrowest access a type needs to be drawn.
        var minimumRank: Int
        /// The level a focus was entered from.
        var focusFrom: String?
        /// The comparison's diff, or `nil` with none or before it is read.
        var diff: InterfaceDiff?
        /// The comparison.
        var comparison: Comparison
        /// The comparison as the end of a sentence.
        var comparisonPhrase: String
        /// Why the base could not be read, or `nil`.
        var comparisonProblem: String?
        /// Whether the changes level draws the untouched neighbors too.
        var showsUntouched: Bool
    }

    /// What the focus draws around the selected type.
    enum FocusMode: Hashable, CaseIterable, Sendable {
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

    /// What the map's marks compare the interface with.
    enum Comparison: Hashable, Sendable {
        /// Nothing: no marks.
        case off
        /// Where the branch left the named one, as a pull request into it compares, uncommitted edits
        /// included.
        case branch(String)
        /// The last commit, so only what is not committed yet shows.
        case lastCommit
        /// A commit, tag, or branch as it is, without finding where the branch left it.
        case revision(String)

        /// The comparison as the defaults keep it: `off`, `lastCommit`, `branch:` and a name, or
        /// `revision:` and a name.
        var stored: String {
            switch self {
            case .off: "off"
            case .lastCommit: "lastCommit"
            case .branch(let branch): "branch:" + branch
            case .revision(let revision): "revision:" + revision
            }
        }

        /// Reads a comparison the defaults kept.
        ///
        /// - Parameter stored: A value ``stored`` wrote.
        init?(stored: String) {
            switch stored {
            case "off": self = .off
            case "lastCommit": self = .lastCommit
            case _ where stored.hasPrefix("branch:"): self = .branch(String(stored.dropFirst("branch:".count)))
            case _ where stored.hasPrefix("revision:"): self = .revision(String(stored.dropFirst("revision:".count)))
            default: return nil
            }
        }
    }

    /// The level id of the selected type's focus, beside the atlas's own levels.
    nonisolated static let focus = "focus"
    /// The level id of what changed since the comparison's base and the types one step around it.
    nonisolated static let changes = "changes"

    /// One tab over the details and the map: a place in the interface with its own way back and forth, so
    /// a reader can keep several open beside the one list.
    struct Tab: Identifiable {
        /// What tells the tab apart, kept when it moves.
        let id = UUID()
        /// What the details pane shows when nothing is previewed, and what the map lights.
        var selection = Selection.overview
        /// The level the map draws: an id from ``Workspace/scopes``, or ``Workspace/focus``.
        var scopeID = ""
        /// The level the focus was entered from, which zooming out returns to while it draws the type.
        var focusFrom: String?
        /// What the focus draws: the type's neighbors, or all it reaches one way.
        var focusMode = FocusMode.neighbors
        /// The steps a reach draws, or `nil` for the default.
        var reachDepth: Int?
        /// The drawn type whose tie to the focused type the details pin, or `nil` for the focused type's page.
        var inspected: String?
        /// On the changes level, whether the details show the selected type's whole page rather than only
        /// what changed in it, or how a change reaches it.
        var showsFullPage = false
        /// The places Back returns to, the most recent last.
        var back: [Place] = []
        /// The places Forward returns to after going back, the nearest last.
        var forward: [Place] = []

        /// A tab at the start: the overview, at the default level.
        init() {}

        /// A new tab at another tab's place, with no way back of its own.
        ///
        /// - Parameter other: The tab whose place to open.
        init(at other: Tab) {
            selection = other.selection
            scopeID = other.scopeID
            focusFrom = other.focusFrom
            focusMode = other.focusMode
            reachDepth = other.reachDepth
            inspected = other.inspected
            showsFullPage = other.showsFullPage
        }
    }

    /// The open tabs, left to right; never empty. On the blank page the one tab is hidden and fresh.
    private(set) var tabs = [Tab()]
    /// Whether the editor shows the blank page, as Xcode does with no editor open: no tab, only a hint to
    /// find a type with Open Quickly. A folder opens on it, closing the last tab returns to it, and
    /// going anywhere leaves it.
    private(set) var isBlank = true
    /// The tab the details and the map show.
    private(set) var currentTabID: Tab.ID
    private var current: Int { tabs.firstIndex { $0.id == currentTabID } ?? 0 }

    /// On the changes level, whether the current tab's details show the selected type's whole page rather
    /// than only what changed in it, or how a change reaches it; each selection starts with only that.
    var showsFullPage: Bool {
        get { tabs[current].showsFullPage }
        set { tabs[current].showsFullPage = newValue }
    }

    /// The comparison a type's page shows only the changes of: the current one on the changes level,
    /// unless the reader asked for the selected type's whole page.
    ///
    /// - Parameter target: What a page shows, the selection or a preview.
    /// - Returns: The diff, or `nil` for the whole page.
    func changesOnly(for target: Selection) -> InterfaceDiff? {
        guard scopeID == Self.changes, case .type = target else { return nil }
        return target == selection && showsFullPage ? nil : diff
    }

    /// What the focus draws in the current tab: the type's neighbors, or all it reaches one way.
    var focusMode: FocusMode {
        get { tabs[current].focusMode }
        set {
            tabs[current].focusMode = newValue
            redraw()
        }
    }
    /// The steps a reach draws in the current tab, chosen with the depth stepper and kept across modes until
    /// another type is selected; `nil`, the default, draws 1 for Neighbors and as many whole steps as fit
    /// ``GlossMap/Atlas/mapBudget`` for the others.
    var reachDepth: Int? {
        get { tabs[current].reachDepth }
        set {
            tabs[current].reachDepth = newValue
            redraw()
        }
    }

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
    /// What the details pane shows in the current tab when nothing is previewed, and what the map lights.
    private(set) var selection: Selection {
        get { tabs[current].selection }
        set { tabs[current].selection = newValue }
    }
    /// The level the map draws in the current tab: an id from ``scopes``, or ``focus``.
    private(set) var scopeID: String {
        get { tabs[current].scopeID }
        set { tabs[current].scopeID = newValue }
    }
    /// The map for ``scopeID``, laid out once per change rather than per frame, and again when another
    /// tab comes forward.
    private(set) var drawing = Drawing()
    private var focusFrom: String? {
        get { tabs[current].focusFrom }
        set { tabs[current].focusFrom = newValue }
    }
    /// The drawn type whose tie to the focused type the details pin in the current tab, or `nil` for the
    /// focused type's own page; always `nil` outside a focus.
    private(set) var inspected: String? {
        get { tabs[current].inspected }
        set { tabs[current].inspected = newValue }
    }

    /// What the marks compare with; changing it reads the base, or reuses it when read before.
    var comparison = Comparison.off {
        didSet {
            comparisonChosen = true
            if comparison != oldValue { compare() }
        }
    }
    /// How the interface differs from the base, or `nil` with no comparison, before the base is read, or
    /// when it cannot be.
    private(set) var diff: InterfaceDiff?
    /// Why the base could not be read, such as a folder outside git, or `nil` when it could.
    private(set) var comparisonProblem: String?
    /// The branch a pull request from here would go into, `main` or else `master`, or `nil` outside git.
    private(set) var defaultBranch: String?
    /// The revision read in place of the files on disk, so the whole window shows it, or `nil` for the
    /// working tree.
    private(set) var head: String?
    /// The repository's branches, remotes' branches, and tags, most recently committed to first; empty
    /// outside git.
    private(set) var refs: [Revision.Ref] = []
    /// The branch checked out, or `nil` outside git or with a detached head.
    private(set) var currentBranch: String?
    /// Whether the sheet that picks a base and a head is up.
    var isCompareShown = false
    /// The bases read so far, by commit, so a reload compares again without reading git again.
    private var bases: [String: Interface] = [:]
    /// Whether the reader picked a comparison, which the default then leaves alone.
    private var comparisonChosen = false
    /// The defaults key of the comparison the reader last picked for each folder, by path, as
    /// ``Comparison/stored`` writes it.
    private static let comparisonsKey = "comparisons"

    /// Whether the changes level draws the neighbors no change reaches as well as those it does.
    var showsUntouched = false { didSet { if scopeID == Self.changes { redraw() } } }
    /// Whether a drawing is being made off the main thread, while the map shows the one before.
    private(set) var isDrawing = false
    /// How many drawings were asked for, so only the latest one asked for is shown.
    private var drawingsAsked = 0

    /// The narrowest access shown, as ``GlossCore/Contract/rank(_:)``: 3 for public, 1 for internal, 0 for all.
    var minimumRank = Atlas.defaultMinimumRank { didSet { redraw() } }
    /// The list's search text, which keeps types whose name or a member's name contains it, ignoring case.
    var search = ""
    /// Whether the list keeps only types with findings, their members' included, from the checkbox under it.
    var findingsOnly = false
    /// Whether Open Quickly is showing over the window.
    var isQuickOpenShown = false
    /// Which panes the window shows: the list beside the tabs, or the tabs alone with the list hidden.
    var columns = NavigationSplitViewVisibility.all
    /// The chip under the pointer, whose box the map lights instead of what the details pane shows.
    var hovered: String?
    /// What hovering a box or a list row shows in the details pane in place of the selection.
    private(set) var preview: Selection?
    private var showing: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// The folders opened most recently, newest first, which the welcome window and Open Recent list.
    private(set) var recentFolders: [URL]
    /// How many folders have been opened, which the welcome window watches to hand over to the main
    /// window whatever opened one: its list, a drop, or the File menu.
    private(set) var opens = 0
    /// Whether the main window is up, so the welcome window can close at once on handing over.
    var isMainWindowShown = false
    /// The main window, so Command-W can tell it from the welcome window.
    @ObservationIgnored weak var mainWindow: NSWindow?

    /// The defaults key of the folders opened most recently.
    private static let recentFoldersKey = "recentFolders"
    /// The defaults key of the one folder gloss remembered before it kept a list, read to start the list.
    private static let lastFolderKey = "lastFolder"
    /// The defaults key of whether a launch opens on the welcome window rather than the last folder.
    static let showsWelcomeKey = "showsWelcome"
    /// The most folders the recent list keeps.
    private static let recentLimit = 10

    /// The folder to open once the main window appears, set when the launch skips the welcome window.
    private(set) var launchFolder: URL?

    /// Reads the folders opened most recently and chooses the folder a launch opens: the one
    /// `--root <folder>` names, or else, with the welcome window turned off, the one opened last.
    /// Reading waits for ``start()``, since SwiftUI may build the app, and with it a workspace, more
    /// than once, and only the workspace the window keeps should read anything.
    ///
    /// - Parameter arguments: The process arguments, the executable first.
    init(arguments: [String]) {
        let defaults = UserDefaults.standard
        let remembered = defaults.stringArray(forKey: Self.recentFoldersKey) ?? defaults.string(forKey: Self.lastFolderKey).map { [$0] } ?? []
        let recents = remembered.map { URL(fileURLWithPath: $0) }.filter(Self.isFolder)
        recentFolders = recents
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let given = arguments.firstIndex(of: "--root").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            .map { URL(fileURLWithPath: $0, relativeTo: current).standardizedFileURL }
        // A snapshot without a folder is of the welcome window, whatever the reader turned off.
        let showsWelcome = Self.isSnapshotting || (defaults.object(forKey: Self.showsWelcomeKey) as? Bool ?? true)
        launchFolder = [given, showsWelcome ? nil : recents.first].compactMap { $0 }.first(where: Self.isFolder)
        let first = Tab()
        tabs = [first]
        currentTabID = first.id
    }

    /// Whether a folder exists at a URL.
    ///
    /// - Parameter url: A file URL.
    /// - Returns: `true` when it names a directory.
    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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
        var defaultBranch: String?
        var refs: [Revision.Ref]
        var currentBranch: String?

        /// The folder read for a package: its `Sources` directory when it has one, else the folder itself.
        ///
        /// - Parameter root: The package folder.
        /// - Returns: The folder to scan.
        static func scanned(_ root: URL) -> URL {
            let sources = root.appendingPathComponent("Sources")
            return FileManager.default.fileExists(atPath: sources.path) ? sources : root
        }

        /// Reads a package: its `Sources` directory when it has one, and otherwise the folder itself, from
        /// disk or as a revision holds it.
        ///
        /// - Parameters:
        ///   - root: The folder.
        ///   - head: The revision to read, or `nil` for the files on disk.
        /// - Returns: The interface and its arrangement, with files named relative to `root`.
        /// - Throws: ``GlossCore/SourceFiles/Missing`` when the folder is gone, or
        ///   ``GlossCore/Revision/Failure`` when git cannot read the revision.
        static func read(_ root: URL, head: String?) throws -> Loaded {
            let scanned = scanned(root)
            let pairs: [(file: String, source: String)] = try Timing.measure("read files", head ?? "working tree") {
                if let head {
                    return try Revision.sources(at: head, under: scanned.path, relativeTo: root.path, includeTests: false)
                }
                let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                return try SourceFiles.swiftFiles(under: scanned.path, includeTests: false).compactMap { file in
                    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
                    return (file.hasPrefix(prefix) ? String(file.dropFirst(prefix.count)) : file, source)
                }
            }
            let interface = Interface.build(sources: pairs)
            let atlas = Atlas(interface)
            let scopes = atlas.mapScopes()
            let levels = atlas.levelsDrawing(scopes)
            let (branch, refs, current) = Timing.measure("read branches") {
                (["main", "master"].first { (try? Revision.commit($0, in: scanned.path)) != nil },
                 (try? Revision.refs(in: scanned.path)) ?? [],
                 (try? Revision.currentBranch(in: scanned.path)) ?? nil)
            }
            return Loaded(interface: interface, atlas: atlas, scopes: scopes, levels: levels, defaultBranch: branch,
                          refs: refs, currentBranch: current)
        }
    }

    /// Opens a folder and reads it.
    ///
    /// - Parameter url: The package folder.
    func open(_ url: URL) {
        Timing.event("open folder", url.path)
        recentFolders = [url] + recentFolders.filter { $0.path != url.path }.prefix(Self.recentLimit - 1)
        saveRecentFolders()
        opens += 1
        root = url
        name = url.lastPathComponent
        tabs = [Tab()]
        currentTabID = tabs[0].id
        isBlank = true
        expanded = []
        openModules = []
        bases = [:]
        diff = nil
        comparisonProblem = nil
        head = nil
        comparison = .off
        comparisonChosen = false
        // The base picked for this folder before, such as `develop` where branches merge there first.
        if let stored = UserDefaults.standard.dictionary(forKey: Self.comparisonsKey)?[url.path] as? String,
           let saved = Comparison(stored: stored) {
            comparison = saved
        }
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

    /// Takes a folder off the recent list.
    ///
    /// - Parameter url: A folder the list holds.
    func forget(_ url: URL) {
        recentFolders.removeAll { $0.path == url.path }
        saveRecentFolders()
    }

    /// Empties the recent list.
    func clearRecentFolders() {
        recentFolders = []
        saveRecentFolders()
    }

    /// Writes the recent list for the next launch, unless this run only takes a snapshot.
    private func saveRecentFolders() {
        guard !Self.isSnapshotting else { return }
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: Self.recentFoldersKey)
        UserDefaults.standard.removeObject(forKey: Self.lastFolderKey)
    }

    /// Reads the open folder again, keeping the selection and the map level when they still exist.
    func reload() {
        guard let root else { return }
        let head = self.head
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Timing.measure("read folder", root.lastPathComponent) { try Loaded.read(root, head: head) } }
            }.value
            guard root == self.root, head == self.head else { return }
            isLoading = false
            switch result {
            case .success(let loaded):
                problem = nil
                interface = loaded.interface
                atlas = loaded.atlas
                // Pages color declarations as they show; working them all out now, in the background,
                // keeps a type of hundreds of members from parsing them while the reader waits.
                let contracts = loaded.interface.contracts
                Task.detached(priority: .utility) { Highlight.warm(contracts) }
                scopes = loaded.scopes
                levels = loaded.levels
                defaultBranch = loaded.defaultBranch
                refs = loaded.refs
                currentBranch = loaded.currentBranch
                restore()
                // A branch is compared with where it left the default branch until the reader picks.
                if !comparisonChosen, let branch = loaded.defaultBranch, comparison == .off {
                    comparison = .branch(branch)
                    comparisonChosen = false
                } else {
                    compare()
                }
                snapshotIfAsked()
            case .failure(let error):
                problem = (error as? Revision.Failure).map { "git could not read \(head ?? "HEAD"): \($0.message)" }
                    ?? "There is nothing at \(root.path)."
            }
        }
    }

    /// Compares the interface with the base ``comparison`` names, reading the base from git unless it
    /// was read before, off the main thread.
    private func compare() {
        guard comparison != .off, let root, let head = interface else {
            diff = nil
            comparisonProblem = nil
            redraw()
            return
        }
        let comparison = self.comparison
        let headRevision = self.head
        let known = bases
        Task {
            let result = await Task.detached(priority: .utility) { () -> Result<(commit: String, base: Interface, diff: InterfaceDiff), Error> in
                Result {
                    let scanned = Loaded.scanned(root).path
                    let commit = switch comparison {
                    case .off, .lastCommit: try Revision.commit(headRevision ?? "HEAD", in: scanned)
                    case .branch(let branch): try Revision.mergeBase(of: headRevision ?? "HEAD", and: branch, in: scanned)
                    case .revision(let revision): try Revision.commit(revision, in: scanned)
                    }
                    let base = try known[commit]
                        ?? Interface.build(sources: Revision.sources(at: commit, under: scanned, relativeTo: root.path, includeTests: false))
                    return (commit, base, InterfaceDiff(base: base, head: head))
                }
            }.value
            guard root == self.root, comparison == self.comparison, head == self.interface else { return }
            switch result {
            case .success(let compared):
                bases[compared.commit] = compared.base
                diff = compared.diff
                comparisonProblem = nil
            case .failure(let error):
                diff = nil
                comparisonProblem = (error as? Revision.Failure)?.message ?? error.localizedDescription
            }
            // Every level's boxes carry marks, so every level draws again.
            redraw()
        }
    }

    /// The marks on the map's boxes: how each box differs from the base, by box id; empty with no
    /// comparison.
    var boxMarks: [String: InterfaceDiff.Change] {
        drawing.boxMarks
    }

    /// The marks on the edges of a focus and of the changes level: how each drawn dependency differs from
    /// the base, keyed by its ends joined with a tab; empty at the other levels, whose edges stand for
    /// many dependencies at once.
    var edgeMarks: [String: InterfaceDiff.Change] {
        drawing.edgeMarks
    }

    /// Compares with a base the reader picked, and keeps it as the folder's base for next time.
    ///
    /// - Parameter comparison: The base.
    func choose(_ comparison: Comparison) {
        self.comparison = comparison
        guard !Self.isSnapshotting, let root else { return }
        var stored = UserDefaults.standard.dictionary(forKey: Self.comparisonsKey) ?? [:]
        stored[root.path] = comparison.stored
        UserDefaults.standard.set(stored, forKey: Self.comparisonsKey)
    }

    /// Compares a head with a base, each anything git names a commit by, once git knows them both. A
    /// head other than the working tree is read from git, and the whole window shows it.
    ///
    /// - Parameters:
    ///   - base: The base, such as `develop`, `v1.2`, or a hash.
    ///   - asItIs: `true` compares with the base as it is; `false` with where the head left it, as a pull
    ///     request into it compares.
    ///   - head: The head, or `nil` for the working tree.
    /// - Returns: Why the comparison cannot be made, or `nil` once it is under way.
    func compare(base: String, asItIs: Bool, head: String?) -> String? {
        guard let root else { return "No folder is open." }
        let scanned = Loaded.scanned(root).path
        for revision in [base, head].compactMap({ $0 }) where (try? Revision.commit(revision, in: scanned)) == nil {
            return "git knows no commit named \(revision)."
        }
        choose(asItIs ? .revision(base) : .branch(base))
        if head != self.head {
            self.head = head
            // The marks were made against the other head, so none show until this one is read.
            diff = nil
            reload()
        }
        return nil
    }

    /// The branches the Changes menu offers to compare with: the default branch, then the other
    /// branches here most recently committed to, eight in all, then the one compared with now when it
    /// is none of those; never the head's own branch, which has no changes since itself.
    var baseChoices: [String] {
        let own = head ?? currentBranch
        var seen: Set<String> = []
        let names = ([defaultBranch].compactMap { $0 } + refs.filter { $0.kind == .branch }.map(\.name))
            .filter { $0 != own && seen.insert($0).inserted }
        var choices = Array(names.prefix(8))
        if case .branch(let branch) = comparison, !choices.contains(branch) { choices.append(branch) }
        return choices
    }

    /// What the comparison is with, for the toolbar and the map's count of changes.
    var comparisonTitle: String {
        switch comparison {
        case .off: "No Comparison"
        case .branch(let branch): "Since \(branch)"
        case .lastCommit: "Since Last Commit"
        case .revision(let revision): "Since \(revision) as It Is"
        }
    }

    /// The comparison as the end of a sentence about changes: `since main`, or `since the last commit`.
    var comparisonPhrase: String {
        switch comparison {
        case .off: ""
        case .branch(let branch): "since \(branch)"
        case .lastCommit: "since the last commit"
        case .revision(let revision): "since \(revision)"
        }
    }

    private func restore() {
        let stillThere: Bool
        switch selection {
        case .overview, .modules, .changes: stillThere = true
        case .module(let module): stillThere = atlas?.modules.contains(module) == true
        case .folder(let module, let folder): stillThere = scopes.contains { $0.kind == .folder(module, folder) }
        case .type(let id): stillThere = atlas?.byID[id] != nil
        }
        if !stillThere { selection = .overview }
        if ![Self.focus, Self.changes].contains(scopeID) || !stillThere, !scopes.contains(where: { $0.id == scopeID }) {
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
        Timing.event("select", "\(target)")
        navigate {
            showing?.cancel()
            hiding?.cancel()
            preview = nil
            let rerooted = target != selection
            selection = target
            inspected = nil
            showsFullPage = false
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

    /// Pins a drawn type's tie to the focused type in the details, leaving the focus where it is.
    ///
    /// - Parameter id: A type the focus draws other than its root; clicking the root unpins instead.
    func inspect(_ id: String) {
        guard scopeID == Self.focus, case .type(let root) = selection else { return }
        navigate {
            showing?.cancel()
            hiding?.cancel()
            preview = nil
            inspected = id == root || drawing.reach?.parents[id] == nil ? nil : id
        }
    }

    /// Unpins the type the details show, returning them to the focused type's own page.
    func closeInspection() {
        guard inspected != nil else { return }
        navigate { inspected = nil }
    }

    /// Answers a click on a box: in a focus, one click pins the box's tie to the root and a second
    /// re-roots the focus on it; elsewhere, one click selects a box and a second zooms into a type's
    /// focus. The first click acts at once, so a single click never waits to see whether a second
    /// follows.
    ///
    /// - Parameters:
    ///   - unit: What the box stands for.
    ///   - count: The click count of the event, 2 for the second click of a double click.
    func clicked(_ unit: MapScope.Unit, count: Int) {
        let target = Self.selection(of: unit)
        guard case .type(let id) = target else { return select(target) }
        if scopeID == Self.focus {
            if count >= 2 { select(target) } else { inspect(id) }
        } else if count >= 2 {
            focus(on: id)
        } else {
            select(target)
        }
    }

    /// Keeps what a preview shows: in a focus, a drawn type's tie to the root is pinned; anything else is
    /// selected.
    ///
    /// - Parameter target: The previewed selection.
    func keep(_ target: Selection) {
        if scopeID == Self.focus, case .type(let id) = target, drawing.reach?.parents[id] != nil {
            inspect(id)
        } else {
            select(target)
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
    struct Place: Equatable {
        /// What was selected.
        var selection: Selection
        /// The level the map drew.
        var scopeID: String
        /// The level a focus was entered from.
        var focusFrom: String?
        /// The depth chosen there, or `nil` for the default.
        var reachDepth: Int?
        /// The type whose tie to the focused type was pinned there.
        var inspected: String?
    }

    /// Where the reader is now.
    private var here: Place {
        Place(selection: selection, scopeID: scopeID, focusFrom: focusFrom, reachDepth: reachDepth, inspected: inspected)
    }

    private var back: [Place] {
        get { tabs[current].back }
        set { tabs[current].back = newValue }
    }
    private var forward: [Place] {
        get { tabs[current].forward }
        set { tabs[current].forward = newValue }
    }
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
        // Going anywhere leaves the blank page, and the place under it was never shown, so it is no
        // place to go back to.
        let wasBlank = isBlank
        isBlank = false
        let before = here
        navigating += 1
        change()
        navigating -= 1
        guard navigating == 0, here != before, !wasBlank else { return }
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
        tabs[current].reachDepth = place.reachDepth
        inspected = place.inspected
        // A place read before a reload may name what is gone; it falls back as a reload does.
        restore()
    }

    // MARK: Tabs

    /// Opens a tab at the current place, beside the current one, and shows it.
    func newTab() {
        // From the blank page, the hidden tab is the new one.
        guard !isBlank else {
            isBlank = false
            restore()
            return
        }
        insert(Tab(at: tabs[current]))
    }

    /// Opens something in a new tab, from the current place, leaving the current tab where it is.
    ///
    /// - Parameter target: What to select in the new tab.
    func openInNewTab(_ target: Selection) {
        newTab()
        select(target)
        back.removeAll()
    }

    /// Opens a type's focus in a new tab, leaving the current tab where it is.
    ///
    /// - Parameter id: A node id.
    func focusInNewTab(on id: String) {
        newTab()
        focus(on: id)
        back.removeAll()
    }

    /// Shows a tab, as it was left.
    ///
    /// - Parameter id: A tab's id; an unknown one does nothing.
    func activate(_ id: Tab.ID) {
        guard id != currentTabID, tabs.contains(where: { $0.id == id }) else { return }
        showing?.cancel()
        hiding?.cancel()
        preview = nil
        hovered = nil
        currentTabID = id
        if case .type(let node) = selection { reveal(node) }
        restore()
    }

    /// Closes a tab, showing its neighbor if it was the current one; closing the last tab leaves the
    /// blank page.
    ///
    /// - Parameter id: A tab's id.
    func closeTab(_ id: Tab.ID) {
        guard !isBlank, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabs.count > 1 else {
            showing?.cancel()
            hiding?.cancel()
            preview = nil
            hovered = nil
            let fresh = Tab()
            tabs = [fresh]
            currentTabID = fresh.id
            isBlank = true
            restore()
            return
        }
        if id == currentTabID { activate(tabs[index + 1 < tabs.count ? index + 1 : index - 1].id) }
        tabs.remove(at: index)
    }

    /// Closes what Command-W closes in the main window: the current tab, the last one leaving the blank
    /// page.
    ///
    /// - Returns: `false` on the blank page, which has no tab to close, so the window closes instead.
    func closeCurrentTab() -> Bool {
        guard !isBlank else { return false }
        closeTab(currentTabID)
        return true
    }

    /// Shows the tab beside the current one, wrapping around at the ends.
    ///
    /// - Parameter offset: 1 for the next tab, -1 for the previous one.
    func showTab(by offset: Int) {
        activate(tabs[((current + offset) % tabs.count + tabs.count) % tabs.count].id)
    }

    /// Moves a tab to where another one is, for dragging tabs into order.
    ///
    /// - Parameters:
    ///   - id: The tab being moved.
    ///   - target: The tab whose place it takes.
    func moveTab(_ id: Tab.ID, to target: Tab.ID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }), let to = tabs.firstIndex(where: { $0.id == target }), from != to else { return }
        tabs.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }

    /// What a tab is named in the tab bar: the name of what it shows.
    ///
    /// - Parameter tab: An open tab.
    /// - Returns: `Overview`, a module's or folder's name, or a type's.
    func title(of tab: Tab) -> String {
        switch tab.selection {
        case .overview: "Overview"
        case .changes: "Changes"
        case .modules: "Modules"
        case .module(let module): module
        case .folder(_, let folder): Wording.folderLabel(folder)
        case .type(let id): atlas?.byID[id].map { atlas?.label($0) ?? id } ?? id
        }
    }

    /// The module a tab's place belongs to, whose color marks the tab; `nil` for the overview and modules.
    ///
    /// - Parameter tab: An open tab.
    /// - Returns: The module's name.
    func module(of tab: Tab) -> String? {
        switch tab.selection {
        case .overview, .modules, .changes: nil
        case .module(let module), .folder(let module, _): module
        case .type(let id): atlas?.byID[id]?.module
        }
    }

    private func insert(_ tab: Tab) {
        tabs.insert(tab, at: current + 1)
        activate(tab.id)
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
            Timing.event("preview", "\(target)")
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
        case .changes:
            return Self.changes
        case .modules:
            return scopes.first { $0.kind == .modules }?.id ?? first
        case .module(let module):
            return scopes.first { $0.kind == .module(module) }?.id ?? first
        case .folder(let module, let folder):
            return scopes.first { $0.kind == .folder(module, folder) }?.id ?? scope(for: .module(module))
        case .type(let id):
            if scopeID == Self.focus { return Self.focus }
            // The changes level keeps a type it draws, so the reader can walk the changes one by one.
            if scopeID == Self.changes, drawing.layout.boxes.contains(where: { $0.item.id == id }) { return Self.changes }
            guard let root = atlas?.byID[id]?.root, let drawing = levels[root], !drawing.isEmpty else { return scopeID.isEmpty ? first : scopeID }
            return drawing.contains(scopeID) ? scopeID : drawing[0]
        }
    }

    // The focus zooms out to the level it was entered from, unless the focus has since moved to a
    // type that level does not draw; then to the narrowest level that draws it, one step back up the
    // ladder zooming in climbs.
    private func parent(of scope: String) -> String? {
        guard scope == Self.focus else { return scopes.first { $0.id == scope }?.parent }
        if focusFrom == Self.changes, diff != nil { return Self.changes }
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
        guard !isBlank else { return nil }
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
        isBlank ? nil : parent(of: scopeID)
    }

    /// Moves the map to a level without changing the selection.
    ///
    /// - Parameter target: A level id, or ``focus``; `nil` does nothing.
    func zoom(to target: String?) {
        guard let target else { return }
        navigate {
            if target == Self.focus, scopeID != Self.focus { focusFrom = scopeID }
            if target != Self.focus { inspected = nil }
            scopeID = target
            redraw()
        }
    }

    /// The box the map lights: a hovered chip's, or else what the details pane shows, as the current
    /// level draws it.
    var litID: String? {
        if let hovered { return hovered }
        switch shown {
        case .overview, .modules, .changes: return nil
        case .module(let module): return MapScope.Unit.module(module).id
        case .folder(let module, let folder): return MapScope.Unit.folder(module, folder).id
        case .type(let id):
            if scopeID == Self.changes { return id }
            guard scopeID == Self.focus else { return atlas?.byID[id]?.root }
            // A focus is about the whole reach, so its root is marked, not lit; a previewed or pinned box
            // still lights.
            return preview == nil ? inspected : id
        }
    }

    /// The trails that bring a previewed type into the focus, as ``GlossMap/Reach/trails(to:limit:)``
    /// gives them; none outside the focus or with no type previewed.
    var previewTrails: (trails: [[GraphLayout.Link]], more: Int) {
        guard scopeID == Self.focus, case .type(let id)? = preview, let reach = drawing.reach else { return ([], 0) }
        return reach.trails(to: id)
    }

    /// The trails that bring the pinned type into the focus; none when nothing is pinned.
    var inspectedTrails: (trails: [[GraphLayout.Link]], more: Int) {
        guard scopeID == Self.focus, let inspected, let reach = drawing.reach else { return ([], 0) }
        return reach.trails(to: inspected)
    }

    /// The drawn dependencies the map lights beyond the lit box's own: the previewed or else the pinned
    /// type's trails back to the root, so the map shows the chain the details pane reads; none while a
    /// chip lights another box.
    var litTrail: [GraphLayout.Link] {
        guard hovered == nil else { return [] }
        return (preview == nil ? inspectedTrails : previewTrails).trails.flatMap { $0 }
    }

    /// The box the focus grows from, drawn as the current one without dimming the rest; `nil` outside it.
    var anchorID: String? {
        guard scopeID == Self.focus, case .type(let id) = selection else { return nil }
        return id
    }

    /// Draws the current level again, off the main thread, from what the current tab shows. The map
    /// keeps the drawing before until the new one is made; a drawing asked for since replaces it unseen.
    private func redraw() {
        guard let atlas else {
            drawing = Drawing()
            return
        }
        drawingsAsked += 1
        let asked = drawingsAsked
        let request = DrawingRequest(atlas: atlas, scopes: scopes, scopeID: scopeID, selection: selection, focusMode: focusMode,
                                     reachDepth: reachDepth, minimumRank: minimumRank, focusFrom: focusFrom, diff: diff,
                                     comparison: comparison, comparisonPhrase: comparisonPhrase, comparisonProblem: comparisonProblem,
                                     showsUntouched: showsUntouched)
        isDrawing = true
        Task {
            let drawn = await Task.detached(priority: .userInitiated) {
                Timing.measure("draw", request.scopeID) { Self.draw(request) }
            }.value
            guard asked == drawingsAsked else { return }
            drawing = drawn
            isDrawing = false
            // A pinned type the reach no longer draws, after a change of depth or mode, unpins.
            if scopeID == Self.focus, let inspected, drawn.reach?.parents[inspected] == nil { tabs[current].inspected = nil }
        }
    }

    /// Makes the drawing of a level: the selected type's reach in a focus, what changed at the changes
    /// level, or one of the atlas's levels, each with its boxes' and dependencies' marks.
    ///
    /// - Parameter request: What to draw.
    /// - Returns: The drawing.
    nonisolated private static func draw(_ request: DrawingRequest) -> Drawing {
        var drawing = drawingWithoutMarks(request)
        guard let diff = request.diff else { return drawing }
        Timing.measure("marks", request.scopeID) {
            for box in drawing.layout.boxes {
                if let change = request.atlas.change(of: box.item.unit, in: diff) { drawing.boxMarks[box.item.id] = change }
            }
            guard request.scopeID == Self.focus || request.scopeID == Self.changes else { return }
            for curve in drawing.layout.curves {
                if let change = diff.change(from: curve.link.from, to: curve.link.to)?.change {
                    drawing.edgeMarks[curve.link.from + "\t" + curve.link.to] = change
                }
            }
        }
        return drawing
    }

    /// Makes the drawing of a level without its marks.
    ///
    /// - Parameter request: What to draw.
    /// - Returns: The drawing.
    nonisolated private static func drawingWithoutMarks(_ request: DrawingRequest) -> Drawing {
        let atlas = request.atlas
        let scopes = request.scopes
        let focusMode = request.focusMode
        // Every focus is a reach: Neighbors goes both ways from depth 1, and the other two fit the budget.
        if request.scopeID == Self.focus, case .type(let id) = request.selection, let node = atlas.byID[id],
           let reach = atlas.reach(from: id, toward: focusMode.direction,
                                   depth: request.reachDepth ?? (focusMode == .neighbors ? 1 : nil), minimumRank: request.minimumRank) {
            let from = scopes.first { $0.id == request.focusFrom } ?? scopes.first
            let what = switch focusMode {
            case .neighbors: "its neighbors"
            case .below: "all it depends on"
            case .above: "all that uses it"
            }
            let counted = focusMode == .neighbors ? "\(reach.above) above, \(reach.below) below" : "\(reach.drawn)"
            let cut = reach.drawn < reach.total ? " · dashed boxes continue" : ""
            return Drawing(layout: reach.layout,
                           crumbs: [(from?.id ?? "", from?.label ?? "Map"), (Self.focus, "\(atlas.label(node)) and \(what)")],
                           caption: "Depth \(reach.depth) of \(reach.totalDepth) · \(counted) of \(reach.total) types" + cut,
                           overflow: reach.overflow.map { .type($0) },
                           depth: (reach.depth, reach.totalDepth), reach: reach)
        }
        if request.scopeID == Self.changes {
            let phrase = request.comparisonPhrase
            let first = scopes.first.map { [($0.id, $0.label)] } ?? []
            let crumbs = first + [(Self.changes, "Changes " + phrase)]
            guard let diff = request.diff else {
                let caption = request.comparison == .off ? "Pick a base under Changes in the toolbar to see what changed."
                    : request.comparisonProblem ?? "Reading what changed \(phrase)…"
                return Drawing(crumbs: crumbs, caption: caption)
            }
            let figure = atlas.changesFigure(diff, minimumRank: request.minimumRank, includeUntouched: request.showsUntouched)
            let around = request.showsUntouched ? "around them" : "they reach"
            let untouched = figure.untouched.isEmpty ? "" : ", \(figure.untouched.count) around them untouched"
            let caption = diff.isEmpty ? "Nothing changed \(phrase)."
                : "\(figure.changed) changed type\(figure.changed == 1 ? "" : "s"), \(figure.around) \(around)\(untouched)."
            return Drawing(layout: figure.layout, crumbs: crumbs, caption: caption, overflow: figure.overflow.map { .type($0) },
                           untouched: figure.untouched.map { .type($0) })
        }
        guard let scope = scopes.first(where: { $0.id == request.scopeID }) ?? scopes.first else { return Drawing() }
        let figure = atlas.figure(scope, includeBody: true)
        return Drawing(layout: GraphLayout.layered(figure.items, figure.links),
                       crumbs: scope.path.compactMap { id in scopes.first { $0.id == id }.map { ($0.id, $0.label) } },
                       caption: "\(figure.items.count) boxes, \(figure.links.count) dependencies.",
                       loose: figure.loose, overflow: figure.overflow)
    }

    // MARK: Reading

    /// The window's subtitle: the revision read when it is not the working tree, then the size of the
    /// interface and how many findings it has.
    var subtitle: String {
        guard let interface else { return isLoading ? "Reading…" : "" }
        let findings = interface.assessments.reduce(0) { $0 + $1.findings.count }
        let counts = "\(interface.contracts.count) declarations · \(findings) finding\(findings == 1 ? "" : "s")"
        return head.map { "At \($0) · " + counts } ?? counts
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
        columns != .detailOnly
    }

    /// Hides the list, or shows it again, keeping the tabs with the details and the map.
    func toggleList() {
        columns = showsList ? .detailOnly : .all
    }

    // MARK: Expanding

    /// The folders and types open in the list. Both start closed, so a large module opens as its
    /// top folders.
    private var expanded: Set<String> = []
    /// The modules open in the list. Modules start closed, so the list opens as one row per module.
    private var openModules: Set<String> = []

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
                if open { self.expanded.insert(id) } else { self.close(id) }
            }
        )
    }

    /// Whether a module's section is open.
    ///
    /// - Parameter module: The module name.
    /// - Returns: A binding over the open modules; closing one closes every row in it too.
    func expansion(ofModule module: String) -> Binding<Bool> {
        Binding(
            get: { self.openModules.contains(module) },
            set: { open in
                if open {
                    self.openModules.insert(module)
                } else {
                    self.openModules.remove(module)
                    self.expanded = self.expanded.filter { !self.isRow($0, inModule: module) }
                }
            }
        )
    }

    /// Closes a folder or type row and every row under it, so opening it again shows only what it
    /// holds directly.
    ///
    /// - Parameter id: A row id from an outline.
    private func close(_ id: String) {
        expanded.remove(id)
        expanded = expanded.filter { !isRow($0, under: id) }
    }

    /// Whether a row is in a module: one of its folders or types.
    ///
    /// - Parameters:
    ///   - row: A row id from an outline.
    ///   - module: The module name.
    /// - Returns: `true` for the module's folders and types.
    private func isRow(_ row: String, inModule module: String) -> Bool {
        row.hasPrefix(Atlas.folderID(module, [])) || atlas?.byID[row]?.module == module
    }

    /// Whether a row lies under another, at any depth: a folder's subfolders and the types it holds,
    /// and a type's nested types.
    ///
    /// - Parameters:
    ///   - row: A row id from an outline.
    ///   - parent: The id of the row above it.
    /// - Returns: `true` when `row` is somewhere under `parent`.
    private func isRow(_ row: String, under parent: String) -> Bool {
        guard let atlas else { return false }
        let folderPrefix = "folder:"
        if parent.hasPrefix(folderPrefix) {
            if row.hasPrefix(parent + "/") { return true }
            guard let node = atlas.byID[row] else { return false }
            let folder = String(parent.dropFirst(folderPrefix.count))
            return (node.module + "/" + atlas.directories(of: node).joined(separator: "/") + "/").hasPrefix(folder + "/")
        }
        guard let outer = atlas.byID[parent], let inner = atlas.byID[row] else { return false }
        return atlas.isNested(inner, in: outer)
    }

    /// Opens the rows that hold a type, so selecting it from the map or a chip shows it in the list.
    ///
    /// - Parameter id: A node id.
    private func reveal(_ id: String) {
        guard let atlas, let node = atlas.byID[id] else { return }
        openModules.insert(node.module)
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
