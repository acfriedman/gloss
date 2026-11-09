# gloss videos

Every `README.md` in gloss has a video: the repository's README and each module's page under
`Sources/<Module>/README.md`. CI makes and refreshes them unattended, and nobody reviews them, so every
claim must come from the code at the current commit. Each video tells the story of its one file.

## Audience

Swift developers who found gloss and want to know what it does for them, and contributors about to work
in one module. They know Swift, doc comments and Swift Package Manager. They don't know gloss's
vocabulary (a reading, a contract, a reach, a change story) until a video gives it to them.

## Ground truth

The repository, at `..` from here:
- `Sources/<Module>/`: the code, and the module's page (`README.md`): its summary, its Overview and its
  Topics, which name the types a reader reaches for. Read the types the page names before writing about
  them.
- `Tests/GlossTests/`: the behaviour the code promises, with small examples worth showing on screen.
- `Package.swift`: the modules and how they depend on each other.
- `.gloss/changes/*.md`: one story per feature branch, saying why each change was made. Use them for
  history and motivation.
- `git log`: what changed, and when.

The macOS app (GlossApp) can't run in CI. Describe it from its code and its page, and never invent what
its screens look like.

## House rules

- **The name** is written "gloss", lowercase, and said "gloss".
- **Module names** are said as two words: "Gloss Read", "Gloss Lint", "Gloss Model", "Gloss Map",
  "Gloss Page", "Gloss App". `pronounce` in `lyceum.config.json` maps them, so on screen they keep their
  code spelling. The command-line module, `Sources/gloss`, is "the gloss command".
- **Code on screen** is real: real declarations and real doc comments from the sources, marked
  "simplified" in the visual brief when trimmed.
- **Length:** a module's page gets 1–2 minutes in 3–4 scenes; the repository's README 3–5 minutes.
- **Tone:** plain and specific, like the READMEs themselves. No marketing.
- **Look:** the default dark canvas.

## Delivery

Videos are published by CI to the project's store (Cloudflare R2) at fixed URLs, and each README shows
its video as a thumbnail, between `lyceum:video` markers, written once by `lyceum embed`. Never edit a
README outside that block. Changes land as pull requests from `lyceum/refresh-*` branches that merge
themselves. Those branches change no Swift declarations, so they carry no change story.
