# Move the reader and the lint to SwiftLucid

The linter now ships on its own, as SwiftLucid, so a project can lint its docs without the app, the page, or this repository. GlossRead and GlossLint moved there as LucidRead and LucidLint, and the `gloss` command's lint mode became the `swiftlucid` command. gloss depends on SwiftLucid and reads through it, and keeps the model, the map, the page, the app, and the `interface`, `story`, and `bench` commands.

## The reader moves to LucidRead

GlossRead moved to SwiftLucid as LucidRead, unchanged but for its name, so gloss and the lint still read the sources one way. A project that only lints never builds gloss.

The exemption marker is now `// swiftlucid:exempt`, and the timing logs under the `swiftlucid` subsystem, since both are SwiftLucid's now.

### ``Reading``

Moved to LucidRead unchanged.

### ``DeclarationReader``

Moved to LucidRead; its doc no longer names gloss's model, which it cannot see from there.

### ``DeclarationReader/Entry``

Moved to LucidRead unchanged.

### ``DeclarationReader/Details``

Moved to LucidRead unchanged.

### ``DeclarationReader/Scope``

Moved to LucidRead unchanged.

### ``Declaration``

Moved to LucidRead, and its lint half, which says whether a declaration owes a doc, to LucidLint. It reads `// swiftlucid:exempt` now, so the marker names the tool that honors it.

### ``Declaration/Kind``

Moved to LucidRead unchanged.

### ``Declaration/Parameter``

Moved to LucidRead unchanged.

### ``Declaration/Exemption``

Moved to LucidRead; its doc names the new marker.

### ``DocComment``

Moved to LucidRead unchanged.

### ``DocLine``

Moved to LucidRead unchanged.

### ``DocStructure``

Moved to LucidRead unchanged.

### ``Callout``

Moved to LucidRead unchanged.

### ``Callout/Entry``

Moved to LucidRead unchanged.

### ``Header``

Moved to LucidRead unchanged.

### ``Mention``

Moved to LucidRead unchanged.

### ``Mention/Role``

Moved to LucidRead unchanged.

### ``Mentions``

Moved to LucidRead unchanged.

### ``Mentions/AccessCollector``

Moved to LucidRead unchanged.

### ``Mentions/Collector``

Moved to LucidRead unchanged.

### ``ModulePage``

Moved to LucidRead unchanged.

### ``ModulePage/Topic``

Moved to LucidRead unchanged.

### ``ObjectiveCHeaders``

Moved to LucidRead unchanged.

### ``Revision``

Moved to LucidRead, with its git runner public now, since gloss's commit reading calls it from another package.

### ``Revision/Failure``

Moved to LucidRead unchanged.

### ``Revision/Ref``

Moved to LucidRead unchanged.

### ``Revision/Ref/Kind``

Moved to LucidRead unchanged.

### ``Revision/Place``

Moved to LucidRead unchanged.

### ``SourceFiles``

Moved to LucidRead unchanged.

### ``SourceFiles/Missing``

Moved to LucidRead unchanged.

### ``SymbolIndex``

Moved to LucidRead, with its disambiguation helper public now, since the page's links use it from another package.

### ``Timing``

Moved to LucidRead; it logs under the `swiftlucid` subsystem and answers to `SWIFTLUCID_TIMING`, since the timing is SwiftLucid's now.

### ``Timing/Sample``

Moved to LucidRead unchanged.

### ``Timing/Phase``

Moved to LucidRead unchanged.

### ``Duration``

Moved to LucidRead with ``Timing``, which reports in its milliseconds.

## The lint moves to LucidLint

GlossLint moved to SwiftLucid as LucidLint, so a team can adopt the house style without the app. A project's style is now `.swiftlucid.json` at its root, and gloss shows the findings as it did.

### ``Linter``

Moved to LucidLint unchanged.

### ``Rules``

Moved to LucidLint; its exemption finding names the new marker.

### ``Rule``

Moved to LucidLint unchanged.

### ``Diagnostic``

Moved to LucidLint; its exemption cases name the new marker.

### ``Diagnostic/Severity``

Moved to LucidLint unchanged.

### ``Assessment``

Moved to LucidLint unchanged; it is still what the map and the page take from the lint.

### ``Assessment/Finding``

Moved to LucidLint unchanged.

### ``HouseStyle``

Moved to LucidLint, reading `.swiftlucid.json` beside the folder it styles instead of `.gloss/style.json`. The lint's config is SwiftLucid's, so it sits where SwiftLint's and SwiftFormat's do.

### ``HouseStyle/Level``

Moved to LucidLint unchanged.

### ``HouseStyle/Problem``

Moved to LucidLint; its messages name SwiftLucid.

### ``SymbolReference``

Moved to LucidLint unchanged.

### ``Sentences``

Moved to LucidLint unchanged.

## The hook mode moves to swiftlucid

The `gloss` command no longer lints: `swiftlucid` does, `--staged` and `--since` included. SwiftLucid finds what a change touched from two readings, so the lint never needs gloss's model.

### ``ChangedFindings``

Moved to LucidLint, rebuilt to match declarations between two readings instead of an ``InterfaceDiff``. It reports the same findings on gloss's history and on an Xcode project's.

### ``ChangeLint``

Moved to the `swiftlucid` command, which runs it the same way.

### ``ChangeLint/Result``

Moved with ``ChangeLint``.

### ``top-level code``

Drops the lint mode, so `gloss` without a command prints its usage and points to `swiftlucid`.

## gloss reads through SwiftLucid

Every module imports LucidRead and LucidLint from the SwiftLucid package, and docs that link their types name those modules. A few helpers the reader kept to its own package stay gloss's own too.

The links changed in ``Contract``, ``Interface``, ``Graph/Edge``, ``Reason``, ``Atlas``, ``Atlas/Rolled``, ``ChangeCommits``, ``InterfacePage``, ``RevisionFieldView``, ``ModuleView``, ``Workspace/Loaded``, and ``Bench``.

### ``Contract``

Its doc links the lint's types by module, since they live in another package now.

### ``Contract/module``

Its doc links the reader's module naming under its new module.

### ``Contract/make(_:)``

Its doc links the reader under its new module.

### ``Contract/reason(toward:)``

Its doc links mentions under their new module.

### ``Interface``

Its doc links the reading under its new module.

### ``Graph/Edge/roles``

Its doc links mention roles under their new module.

### ``Reason/roles``

Its doc links mention roles under their new module.

### ``InterfacePage/roleMask(_:)``

Its doc links mention roles under their new module.

### ``Atlas/init(_:assessments:)``

Its doc links the lint under its new module.

### ``Atlas/Rolled/roles``

Its doc links mention roles under their new module.

### ``ChangeCommits/read(_:base:head:root:)``

Its doc links git's failure under its new module.

### ``RevisionFieldView/refs``

Its doc links the refs reader under its new module.

### ``ModuleView/type(named:in:from:)``

Its doc's example names the reader's new module.

### ``Workspace/Loaded/read(_:head:)``

Its doc links what it throws under their new modules.

### ``Bench``

Its doc links the timing under its new module.

### ``concurrentMap(_:_:)``

gloss keeps its own copy, since SwiftLucid's stays package-private rather than becoming API that every project importing LucidRead would see.

### ``Slots``

Moved with ``concurrentMap(_:_:)``, whose results it holds.

### ``StringProtocol``

gloss keeps its own `trimmed` and `isBlank`, so SwiftLucid adds nothing to the strings of a project that imports it.
