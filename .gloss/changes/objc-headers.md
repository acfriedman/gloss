# Let Swift docs link the Objective-C types beside them

A project migrating from Objective-C writes Swift docs that link the classes and error codes still declared in headers, and gloss, reading only Swift, called every such link dead: on the example migration project they were the last 4 false findings. gloss now reads the headers for the names of the types they declare, the names Swift imports them as, and takes a link to one on trust.

## Headers are read for their type names

``ObjectiveCHeaders`` finds the classes, protocols, `NS_ENUM` and `NS_OPTIONS` types, typed enums, and `NS_ERROR_ENUM` errors a header declares, the last by the name Swift gives it from its domain, and any type `NS_SWIFT_NAME` renames; comments and forward declarations declare nothing. ``Reading`` sets the headers among its sources apart, so the model never sees one, and hands their names to ``SymbolIndex``, which resolves a link under one without checking the member, since gloss reads no Objective-C members.

### ``ObjectiveCHeaders``

New: the type names a header declares, by their Swift names.

### ``Reading``

Reads the headers among its sources for their type names, and parses only the Swift files.

### ``SymbolIndex``

Takes the Objective-C types, and resolves a link that starts with one on trust.

## Every front end gathers the headers

``SourceFiles/files(under:includeTests:extensions:)`` collects files of any extension, ``SourceFiles/readExtensions`` naming the two gloss reads, and ``Revision`` reads them at a revision. The command line's ``sourceFiles(under:)`` and the app gather headers beside the Swift files, and the command line counts only the Swift files it linted. On the example project, 173 findings become 169, the 4 dead links gone; swift-syntax, with headers of its own, lints byte for byte as it did.

### ``SourceFiles``

Gains a collector for any extensions, which the Swift one now calls, and the list of extensions gloss reads.

### ``Revision``

Reads the files of the extensions asked for at a revision, Swift's alone by default.

### ``sourceFiles(under:)``

Replaces the command line's Swift-only collector, gathering headers too.
