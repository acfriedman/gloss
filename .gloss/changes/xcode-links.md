# Read an Xcode project as its team writes it

A team adopting the linter on an Xcode project would have drowned in findings that were gloss's mistakes, not theirs. Links into the packages they import were called dead, so was a link under their own target's name, since gloss names an Xcode project's modules by folder, and a `/** */` doc, which Swift accepts, read as empty. Run from the project's folder, gloss also linted every package Xcode had checked out beside it: on one example project that was 43,468 findings in 991 files, where the project's own 31 files hold 173.

## Links resolve the way the project's imports do

``DeclarationReader`` collects each file's imports in the same pass, those inside `#if` included, and ``Reading`` gathers them for ``SymbolIndex``. A link under a module some file imports, such as `Alamofire/Session`, names a symbol gloss cannot see and is taken on trust. A link whose first name nothing scanned declares or imports is taken for the project's own module named another way, and the rest must still name something, so a typo under a declared type stays dead.

### ``DeclarationReader``

Gains ``DeclarationReader/readFile(source:file:)``, which hands back the file's imports with its declarations from the one parse.

### ``Reading``

Gathers every file's imports, sorted, and indexes the links against them.

### ``SymbolIndex``

Resolves a link under an imported module, and one under an unknown first name by what follows it; it keeps every declared name to tell the two apart.

## A block comment says what it says

``DocComment`` reads a `/** */` comment's lines as Xcode does: delimiters dropped, then leading stars when every line has one, else the indentation the lines share. The model shows its summary and entries, and the rules check it like a `///` doc; `block-doc` still flags the form, and a style can turn it off.

### ``DocComment``

Keeps a block comment's lines, each at its own source line, instead of none.

### ``DocLine``

Its doc says it may come from a block comment too.

### ``Contract``

A block comment's text reaches the contract, so its doc says so.

## Other projects' code is left alone

``SourceFiles`` skips hidden folders, and the folders Xcode, CocoaPods, and Carthage check code out into, so a project read from its own folder is only its own. Skipping a hidden file met first, such as `.DS_Store`, used to end the walk; only a folder is skipped past now.

### ``SourceFiles``

Gains ``SourceFiles/dependencyFolders`` and skips hidden folders with them.
