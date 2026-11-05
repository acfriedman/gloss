# Judge only what a change touched

A team adopting the linter on a codebase that predates its house style had two ways to run it from a commit hook, and neither worked. Linting only the staged files called every link into an unstaged file dead, since the index knew only those files; linting the whole project reported every old finding in code nobody touched, so every commit failed. gloss now reads the whole project, so links resolve, and reports only the declarations a change added or changed, a body edit included, so new and touched code answers to the style and the rest waits until someone works on it.

## A change's findings are the ones on what it touched

``ChangedFindings`` gathers the lines of every declaration a diff added or changed, its doc comment included, and keeps the findings that fall on them. A type that only moved, or a member that is gone, touches nothing. ``Linter/check(_:style:)`` lints a reading already made, so the interface and the lint share one parse.

### ``ChangedFindings``

New: where a change's new and changed declarations are, and the findings on them.

### ``Linter``

Gains ``Linter/check(_:style:)``, which ``Linter/check(sources:style:)`` now calls with a reading of its own.

## A commit is read as staged

``Revision/stagedSources(under:relativeTo:includeTests:extensions:)`` reads the files as git's index holds them, so a hook judges what the commit will hold and not edits made after staging. Reading at a revision and reading the index now share the one `cat-file` read, the paths each lists chosen the same way, and the place of a folder in its repository, ``Revision/Place``, found once.

### ``Revision``

Gains ``Revision/stagedSources(under:relativeTo:includeTests:extensions:)``, and reads a revision's files through the same helpers.

### ``Revision/Place``

New: where a scanned folder and the root its paths are reported from sit in their repository.

## The command line takes a change

``ChangeLint`` runs `--staged` against `HEAD`, or against nothing on a first commit, and `--since <revision>` with the working tree against a base, for a pull request's check. Only errors on what the change touched fail the run, and the summary counts the changed declarations judged. A base git cannot read stops the run with git's own message.

### ``ChangeLint``

New: the lint of what a change touched, from the index or the working tree.

### ``ChangeLint/Result``

New: the findings kept, and how many declarations the change touched.
