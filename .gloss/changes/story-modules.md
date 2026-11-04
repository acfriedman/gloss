# Let one story link cover a type that moved modules

Splitting GlossCore into reading, lint, and model targets moves some thirty types, and `gloss story` could not explain the move: a link ignored the module it started with and took the first type of its name, so a moved type's side in its old module could never be covered, and a free function could not be linked at all.

## A bare name covers every module

``StoryCoverage`` reads a bare name as the type of that name in every module, the head's and the base's, so one link and one note cover both sides of a move. A module first narrows a link to that module's type, and names nothing when that module has none. A lone name that is no type may be a declaration at file scope, such as a free function.

### ``StoryCoverage``

Resolves a link to every type it names rather than the first. A link that starts with a module names only that module's type, and a link to a declaration at file scope counts as its module's file-scope note too, since file scope has no name to head a note with.

## Drafts link moves and file scope

``ChangeStory/draft(for:commits:)`` links each type by its bare name, so a type that moved gets one note under the first theme that names it, and links file scope by the declarations in it that changed, rather than by an empty link.

### ``ChangeStory``

The draft writes one note per name, and no more empty links for file scope.
