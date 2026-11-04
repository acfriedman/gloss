# Lead the Changes page with the story of why

A reviewer starts from the author's reasons, one theme at a time, and opens a type only to see how; the code comes last. The story is a file on the branch, so it is reviewed with the change and stays as its record.

## Write the story beside the branch

``ChangeStory`` reads `.gloss/changes/<branch>.md`: a headline, a summary, and themes whose links name the types they are about. ``StoryCoverage`` resolves each link against both sides of the diff, so a theme is tied to exactly the changes it explains, and it finds the changes no theme explains and the links that name nothing. ``Revision`` now reads the repository's top and a file at a revision, where a head revision's story is.

## Lead the Changes page with it

``ChangesView`` opens on ``StoryOverviewView``: the headline, the summary, and each ``ThemeView`` with the types it explains, lit together on the map while hovered through ``Workspace``'s lit group, which ``MapCanvasView`` draws. ``StoryGapsView`` lists what the story leaves out, and ``StoryProse`` draws a story's links as code. Without a story, ``StoryPromptView`` offers a draft seeded from the commits, and lists the commits as the outline meanwhile. ``EveryChangeView`` folds the full list of changes beneath.

## Say it on each type's page

``StoryThemesView`` sets the themes that explain a type at the top of its page on the changes level, before the commits behind it.

## Hold a pull request to it

``StoryCheck`` is `gloss story`: it prints what the story covers and leaves out, and fails when a type whose interface changed has no theme, as the lint fails a declaration with no doc.
