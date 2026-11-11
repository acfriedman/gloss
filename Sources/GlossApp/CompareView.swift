import LucidRead
import GlossModel
import SwiftUI

/// The toolbar's Changes menu: the branches to compare with, where the head left each one, the last
/// commit, no comparison, and Compare… for any base and head.
struct ComparisonMenuView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        Menu {
            ForEach(workspace.baseChoices, id: \.self) { branch in
                choice("Since \(branch)", .branch(branch))
            }
            if case .revision(let revision) = workspace.comparison {
                choice("Since \(revision) as It Is", .revision(revision))
            }
            // Changes since the last commit are the edits on disk, which a head read from git has none of.
            if workspace.head == nil {
                choice("Since Last Commit", .lastCommit)
            }
            Divider()
            choice("No Comparison", .off)
            Divider()
            Button("Compare…") { workspace.isCompareShown = true }
                .disabled(workspace.root == nil)
        } label: {
            Label(workspace.comparisonTitle, systemImage: "plusminus")
                .labelStyle(.titleAndIcon)
        }
        .help(workspace.comparisonProblem ?? "Mark what changed since a base: where this branch left another, the last commit, or any base and head")
    }

    /// One comparison in the menu, checked while it is the one made.
    ///
    /// - Parameters:
    ///   - title: The item's title.
    ///   - comparison: The comparison it makes.
    /// - Returns: The item.
    private func choice(_ title: String, _ comparison: Workspace.Comparison) -> some View {
        Toggle(title, isOn: Binding(get: { workspace.comparison == comparison }, set: { _ in workspace.choose(comparison) }))
    }
}

/// The sheet that compares any base with any head: each a branch, a remote's branch, a tag, or a
/// commit, typed or picked, the base taken as it is or from where the head left it, and the head the
/// working tree unless one is named.
struct CompareSheetView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var asItIs = false
    @State private var head = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare").font(.title2.weight(.semibold))
                Text("Mark what changed from a base to a head. Each can be a branch, a tag, or a commit.")
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Base").gridColumnAlignment(.trailing)
                    RevisionFieldView(text: $base, placeholder: "main, develop, v1.2, or a commit", refs: workspace.refs)
                        .frame(maxWidth: .infinity)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Picker("Base", selection: $asItIs) {
                        Text("From where the head left it, as a pull request compares").tag(false)
                        Text("As it is").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Head")
                    RevisionFieldView(text: $head, placeholder: "The working tree", refs: workspace.refs, offersWorkingTree: true)
                        .frame(maxWidth: .infinity)
                }
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
                    problem = workspace.compare(base: trimmed(base), asItIs: asItIs, head: trimmed(head).isEmpty ? nil : trimmed(head))
                    if problem == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(base.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            switch workspace.comparison {
            case .branch(let branch): base = branch
            case .revision(let revision): (base, asItIs) = (revision, true)
            case .off, .lastCommit: base = workspace.defaultBranch ?? ""
            }
            head = workspace.head ?? ""
        }
    }
}

/// A field for a revision, typed or picked from a menu of the repository's branches, remotes'
/// branches, and tags, the most recently committed to first.
struct RevisionFieldView: View {
    /// The revision as typed or picked; empty for the field's placeholder.
    @Binding var text: String
    /// What an empty field means, or which revisions it takes.
    var placeholder: String
    /// The repository's refs, as ``LucidRead/Revision/refs(in:)`` lists them.
    var refs: [Revision.Ref]
    /// Whether the menu starts with the working tree, which empties the field.
    var offersWorkingTree = false

    /// The most refs of each kind the menu lists.
    private static let limit = 20

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Menu {
                if offersWorkingTree {
                    Button("The Working Tree") { text = "" }
                    Divider()
                }
                section("Branches", .branch)
                section("Remote Branches", .remote)
                section("Tags", .tag)
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(refs.isEmpty && !offersWorkingTree)
            .help("Pick a branch or a tag")
        }
    }

    /// The menu's refs of one kind under a header, or nothing when there are none.
    ///
    /// - Parameters:
    ///   - title: The header.
    ///   - kind: The kind of ref.
    /// - Returns: The section.
    @ViewBuilder
    private func section(_ title: String, _ kind: Revision.Ref.Kind) -> some View {
        let names = refs.filter { $0.kind == kind }.prefix(Self.limit).map(\.name)
        if !names.isEmpty {
            Section(title) {
                ForEach(names, id: \.self) { name in
                    Button(name) { text = name }
                }
            }
        }
    }
}
