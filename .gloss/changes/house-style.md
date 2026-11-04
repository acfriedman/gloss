# Let each project choose its own house style

The rules were gloss's own taste, every finding an error and every declaration but the private ones owing a doc, so a team adopting the linter on an existing codebase had no way in short of fixing thousands of findings at once. The docs gloss reads are Swift's own format; how strictly they are held to it is the project's call. A project now says so in `.gloss/style.json`.

## A style file, checked as strictly as the docs

``HouseStyle`` reads `.gloss/style.json` from the nearest folder at or above where the sources are given from: a level for every rule, levels by code or by prefix, globs of paths not linted, and the narrowest access that owes a doc. A key, rule code, or value gloss does not know stops the run with a line that names the fix, so a typo cannot leave a rule quietly on. No file is gloss's own style, and on swift-syntax the lint prints byte for byte what it did.

### ``HouseStyle``

New: a project's house style, how it is found and parsed, and what it decides: a rule's level, whether a declaration owes a doc, whether a file is linted, and how diagnostics are reported.

### ``Declaration``

Carries its effective access, so the style can ask for docs from `public` alone, and ``Declaration/rank(_:)``, which orders access levels below both the lint and the model.

## The lint follows the style

``Rules/check(_:doc:style:)`` asks the style whether a missing doc is owed, and ``Linter`` reports what the rules find at the style's levels, dropping the rules turned off. A file the style excludes is still read, so links into it resolve, but has no findings and owes no docs. ``Diagnostic`` carries its severity and prints `warning:` for a warning, and only errors fail the run, so a team can bring a rule in as a warning before it gates anything.

### ``Rules``

Decides `missing-doc` by the style's access; every other rule is unchanged.

### ``Linter``

Takes a style in every entry point, excludes files by it, and reports by it.

### ``Diagnostic``

Gains ``Diagnostic/Severity``, set by the style and printed in place of `error:`.

### ``Assessment``

Each finding carries its severity, so the export and the views can tell a warning from an error, and an excluded declaration says it was excluded.

## Every front end reads the same style

The command line finds the style from the current directory or takes `--style`, and exits 65 when the file is wrong. ``Workspace`` reads the opened folder's style, so the app shows the findings and the documentation owed that the command line reports, and ``Bench`` times the lint as the app runs it. The JSON export's findings gain their severity, a field added, so its schema stays at 2.

### ``Workspace``

Lints with the opened folder's house style, and says so when the style cannot be read.

### ``Bench``

Lints with the style the command line found.

### ``Atlas``

Its doc links the lint's entry point under its new name.
