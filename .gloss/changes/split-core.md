# Split the core into reading, lint, and model

The linter is to ship on its own, to a team that may not use the app, and the model should hold what the docs say whether or not the lint runs: docs written to Swift's own format read the same by hand or by rule. GlossCore held all three, and ``Interface`` ran the lint while it built, so nothing kept the model from leaning on the house style. Now GlossRead parses once, GlossLint and GlossModel each read from it and cannot import each other, and the two meet only in the views. The lint output, the JSON export, and the page are byte for byte what they were.

## Read once, in GlossRead

``Reading`` parses every source once, spreading the files over every core, and indexes what they declare; both the lint and the model take it. The reader and everything it hands out move here unchanged: ``DeclarationReader``, ``Declaration``, ``DocComment``, ``DocLine``, ``DocStructure``, ``Callout``, ``Header``, ``Mention``, ``Mentions``, ``SymbolIndex``, ``SourceFiles``, ``Revision``, ``Timing``, and the helpers ``StringProtocol``, ``Duration``, ``Slots``, and ``concurrentMap(_:_:)``.

### ``Reading``

New: every source read once, each file's entries and the index the links resolve against. The lint and the model are both built from one.

### ``DeclarationReader``

Moved unchanged, but for its doc, which names its two consumers by target rather than linking types it can no longer see.

### ``Declaration``

Keeps what the syntax says, exemptions included; whether a declaration owes a doc is policy, so ``Declaration/requiresDoc`` moves to GlossLint as an extension.

### ``DocComment``

Moved unchanged.

### ``DocLine``

Moved unchanged.

### ``DocStructure``

Moved unchanged; the lint reads its shape and the model its entries.

### ``Callout``

Moved unchanged.

### ``Header``

Moved unchanged.

### ``Mention``

Moved unchanged, its doc saying the contract model resolves it rather than linking `Graph` from below.

### ``Mentions``

Moved unchanged, its doc reworded the same way.

### ``SymbolIndex``

Now holds ``SymbolIndex/externalPrefixes``, the names no scanned source declares, since resolving a link needs them for the story check as well as the lint; it names modules with ``SourceFiles/module(of:)``.

### ``SourceFiles``

Takes ``SourceFiles/module(of:)`` from `Interface`, since the index names modules too and sits below the model.

### ``Revision``

Moved unchanged: reading sources at a revision is reading; its `git` runner is shared with the model's commits.

### ``Timing``

Moved unchanged.

### ``StringProtocol``

Its trimming helpers are shared with the lint and the model now.

### ``Duration``

Moved unchanged.

### ``Slots``

Moved unchanged, with ``concurrentMap(_:_:)``.

### ``concurrentMap(_:_:)``

Shared with the lint and the model now, which each spread their work over every core.

## The house style, in GlossLint

The rules and what they find move here, and nothing below them knows them: ``Linter``, ``Rules``, ``Rule``, ``Diagnostic``, ``Assessment``, ``SymbolReference``, and ``Sentences``. ``Linter/assess(_:)`` lints a whole `Reading` beside the model rather than inside it, and ``Declaration/requiresDoc`` comes with the rules, since only the house style owes docs.

### ``Linter``

Gains ``Linter/assess(_:)``, which assesses every declaration of a reading in the order the model keeps its contracts. ``Linter/check(sources:)`` reads through `Reading` too, so it parses files in parallel: linting swift-syntax went from 18.7 to 5.7 seconds in a debug build.

### ``Rules``

Moved, and now the home of ``Declaration/requiresDoc``.

### ``Rule``

Moved unchanged.

### ``Diagnostic``

Moved unchanged.

### ``Assessment``

Moved unchanged; it is now the only thing the views take from the lint.

### ``SymbolReference``

Hands its list of outside names down to `SymbolIndex` and reads it from there.

### ``Sentences``

Moved unchanged.

## What the docs say, in GlossModel

``Interface`` holds the contracts and their graph and no longer runs the lint or carries `Assessment` values; ``Interface/build(_:)`` builds from a `Reading`. A base read only to compare with is no longer linted. ``Contract``, ``Graph``, ``InterfaceDiff``, ``Reason``, ``ChangeStory``, ``StoryCoverage``, and ``ChangeCommits`` move with it.

### ``Interface``

Drops `assessments` and `schema`, which go to the JSON export, and gives ``SourceFiles/module(of:)`` to GlossRead. Builds from a reading, or reads its sources first.

### ``Contract``

Moved; its doc links the module naming where it now lives.

### ``Graph``

Moved unchanged.

### ``InterfaceDiff``

Moved unchanged.

### ``Reason``

Moved unchanged.

### ``ChangeStory``

Moved unchanged.

### ``StoryCoverage``

Moved unchanged.

### ``ChangeCommits``

Moved unchanged; it runs git through `Revision` below it.

## The views join findings to contracts

``Atlas`` takes the assessments beside the interface, and arranges the interface alone when they are not given: the same docs, no findings, nothing owed. ``Workspace`` and ``Bench`` read once and hand the reading to both, ``InterfacePage`` takes the assessments to count findings, and ``Export`` puts them back beside the contracts so `gloss interface --json` writes what it did.

### ``Atlas``

Takes optional assessments, so the model can be read without the lint, and counts ``Atlas/totalFindings`` for the window's subtitle.

### ``InterfacePage``

Takes the assessments to render, and shows none when it is not given them.

### ``Export``

New: the JSON document, schema 2 as before, the interface's contracts and graph with the assessments at the same indexes.

### ``Workspace``

Reads the folder once, then builds the interface and lints it from that reading; the subtitle counts findings from `Atlas`.

### ``Bench``

Times the same work the app now does: one reading, then the interface, the lint, and the arrangement.

## Doc links name the new modules

Links that named `GlossCore` now name the target that holds the type.

### ``RevisionFieldView``

Its doc links `Revision` in GlossRead.

### ``Highlight``

Its doc links `Interface` in GlossModel.
