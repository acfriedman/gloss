# Read a type that moves modules as one move

Splitting GlossCore moved some thirty types and their nested ones, and the diff read each as one gone and one new: 142 changes to explain, the Changes page listing every type twice, and every dependency between moved types gone and new again. A move is one change: callers import the type from elsewhere, and what it declares may not differ at all.

## The diff pairs a gone type with a new one

``InterfaceDiff`` matches a gone type with a new one of the same name when each is the only one of that name on its side, declared types and extensions counted apart, so an extension added beside a moved type stays new. Dependencies are compared through the move, so one that moved with its ends is no change. Compared with the commit before the split, gloss now reads 64 moves, 11 changes, and 4 new types, with the file scope that moved still gone and new, since it has no name to match by.

### ``InterfaceDiff``

Pairs moves before it compares, finds a moved node by the id it had in the base too, and names a moved dependency's ends as the head does.

### ``InterfaceDiff/Change``

New case `moved`: the type lives in another module under the same name.

### ``InterfaceDiff/NodeChange``

Carries ``InterfaceDiff/NodeChange/movedFrom``, the node as the base gives it, and only the declarations that differ from where it was.

### ``InterfaceDiff/EdgeChange``

Its ends are named as the head names them when they moved.

## Stories and drafts follow the move

``StoryCoverage`` explains a move by a link to either module. ``ChangeStory/draft(for:commits:)`` gives what no commit made a theme per module, since `git blame` follows a moved file back to the commits that first wrote its lines, outside the range; a module that types moved into says where from.

### ``StoryCoverage``

A link to the module a type left now explains its move, and a move needs a theme and a note like any change.

### ``ChangeStory``

The draft no longer drops changes no commit made; they fall to a theme per module after the commits'.

## The views mark a move

A moved box carries a blue `→`, and ``Atlas`` marks a module whose every type moved in as moved. The Changes page counts moves, a moved type's row says where it came from, and its page, under ``ChangePageBarView``, says it moved and lists only what else changed. The map's header counts moves and names a gone file scope by its module.

### ``Atlas``

Returns `moved` for a moved type's box and for a module or folder whose every type moved in, and reads what can break from a moved type's declarations as from a changed one's.

### ``Palette``

Gains a blue for moves and the `→` glyph.

### ``NodeChangeView``

Says which module a moved type came from, and lists its declarations that changed.
