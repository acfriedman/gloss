# Give every module a short page the lint keeps in step

Nothing said what each module is for, short of reading its code. Now each module under `Sources` keeps a `README.md` of a few sentences and grouped type links, the lint holds it to the code, and the app leads the module's page with it.

## Every module keeps a short page

``ModulePage`` reads `Sources/<Module>/README.md`: a title, a summary, an Overview, and Topics. Pages travel with the sources the way headers do.

### ``ModulePage/file``

Where the page is, so its findings point at its lines.

### ``ModulePage/module``

The module the title names, so a page copied from another module is caught.

### ``ModulePage/titleLine``

The line a missing summary or a wrong title is reported on.

### ``ModulePage/summary``

Kept as lines, so the doc rules check it as they check a doc's summary.

### ``ModulePage/overview``

Kept as lines, so a too-long Overview is reported where it starts.

### ``ModulePage/topics``

The groups a reader scans for a type, in the page's order.

### ``ModulePage/lines``

Every line, so a link anywhere on the page is checked.

### ``ModulePage/isPage(_:)``

Knows a page by its place, the README right in a module's folder, so no other Markdown is ever read as one.

### ``ModulePage/path(forModule:in:)``

Names the file a missing page should be, so the finding says exactly what to write.

### ``ModulePage/parse(_:file:)``

Reads the page into its parts, code fences left out, so the rest of gloss never parses Markdown itself.

### ``ModulePage/overviewParagraphs``

Joins the Overview's lines back into paragraphs, for counting sentences and for showing.

### ``ModulePage/link(in:)``

Finds a line's link, which a Topics item is.

### ``ModulePage/Topic/title``

The group's name, shown over its chips.

### ``ModulePage/Topic/line``

The line a too-long lead is reported on.

### ``ModulePage/Topic/lead``

What the group holds, in a sentence at most.

### ``ModulePage/Topic/links``

The types the group lists, in the page's order.

### ``Reading``

Its doc says module pages ride along with the sources.

### ``Reading/modulePages``

Added so the lint and the model read the pages from the same reading as the code.

### ``Reading/init(sources:)``

Sets the pages apart and parses only Swift files as Swift.

### ``SourceFiles/readExtensions``

Adds Markdown, so the walk finds each module's page.

### ``SourceFiles/reads(_:extensions:)``

Added so the walk and a revision's listing agree that only a module's README counts as Markdown to read.

### ``SourceFiles/files(under:includeTests:extensions:)``

Judges each file by its whole path, since a page is known by the folders above it.

### ``Revision/chosen(_:place:includeTests:extensions:)``

Chooses files the same way as the walk, so a revision's pages are read too.

### ``DocLine``

Now `Codable`, so a page's lines can travel with the interface.

## The lint keeps each page in step

Four new rules hold a page to its module: there, titled for it, short, and linking every public type. The summary rules, `symbol-link`, and `dead-link` check a page as they check a doc, so a removed type is caught too.

### ``Rule/moduleDocMissing``

Added so a new module cannot go without saying what it is for.

### ``Rule/moduleDocTitle``

Added so a page copied from another module is caught.

### ``Rule/moduleDocUnlisted``

Added so a new public type shows on its module's page, keeping the page in step with the code.

### ``Rule/moduleDocLength``

Added so a page stays readable at a glance, the point of having one.

### ``Linter/check(_:style:)``

Lints the pages as well as the files, from the same reading.

### ``Linter/files(_:style:)``

The file lint as it was, split out so the pages can join it.

### ``Linter/overviewLimit``

Five sentences, about what a reader takes in before wanting a type's own page.

### ``Linter/topicLeadLimit``

One sentence, enough to say what a group holds.

### ``Linter/pages(_:style:)``

Checks each page against its module, and asks only SwiftPM's modules for one, since an Xcode project's folders are not modules.

### ``ChangedFindings``

Its doc says a change answers for its modules' pages too.

### ``ChangedFindings/filter(_:)``

Keeps the page findings of a module the change touched, so a hook catches the new type its page does not list.

### ``top-level code``

Counts only Swift files as linted, now that pages ride along with them.

## A module's page leads its page in the app

The app shows a module's summary and Overview first, and groups its types as the page's Topics do. A type no group lists still shows, under Other types.

### ``Interface/pages``

Added so the views get the pages with the interface they belong to.

### ``Interface/build(_:)``

Carries the reading's pages into the interface.

### ``Atlas/pages``

Each module's page, found once by its folder.

### ``Atlas/page(ofModule:)``

Added so a view asks for a module's page by name, as it asks for its types.

### ``Atlas/init(_:assessments:)``

Files each page under its module as it arranges the interface.

### ``ModuleView``

Its doc says the page leads with the module's own words and groups its types by Topics.

### ``ModuleView/body``

Shows the page's prose first, and its groups in place of one long list of types.

### ``ModuleView/type(named:in:from:)``

Turns a page's link into the module's type, with or without the module's name in front.

### ``ModuleProseView/page``

The page whose words lead.

### ``ModuleProseView/body``

Sets the summary in body text and the Overview quieter beneath it, so the summary reads first.

### ``TopicView/topic``

The group to show.

### ``TopicView/units``

Its types, already looked up, so the view only draws them.

### ``TopicView/atlas``

Needed to name the chips.

### ``TopicView/body``

Draws a group as a titled row of chips with its lead under the title.

### ``ChipBlockView/lede``

Added so a group's lead sits under its title, before its chips.

### ``ChipBlockView/body``

Shows the lede when there is one.

### ``HeadingView/title``

Its doc no longer says italic, which the titles stopped being on the last branch.
