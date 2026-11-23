# Testing QuillAgent

`quill` is tested three ways:

- its own suite, with a stand-in model;
- a gated build that installs it and runs it over the wire;
- a gated run that has Pages save a file.

Prompts run through [Craft](https://github.com/riteshpakala/Craft) are logged here as they are run.

## The suite

```
swift test                                            # the record, drafts, layout, Word and the model loop (about 20 s)
QUILL_BUILD=1 swift test --filter QuillBuildTests     # installed and asked over the wire (about 2 min, a release build)
QUILL_PAGES=1 swift test --filter QuillPagesTests     # Pages saves the Word file as a .pages (launches Pages hidden)
QUILL_KEEP=<folder> swift test                        # also copies every written document into <folder> to open by hand
```

The layout tests run WebKit headless: a `WebPage` with no window. Every name, place and figure in the fixtures is made
up.

### What each test file covers

- **`QuillAgentTests`**
  - The record is found with nothing listed.
  - The schema the model is shown: one lane, `makes` a document into `quill/*`.
  - The guide's pins:
    - never write the document's files by hand;
    - the call for a Word letter;
    - nothing invented, and a bracketed place to fill in;
    - a page limit;
    - sources;
    - a spec changed;
    - the PDF always written.
  - Every refusal comes before any work and writes nothing:
    - nothing to write from;
    - a bad page limit;
    - a missing source;
    - an unreadable source;
    - a spec that is not a draft;
    - a brief with no model (`model`).
  - A form is read loosely ("Cover Letter", "CV", "NDA") and guessed from a brief.
  - With no formats named, a PDF and a Word file are written. The PDF is always written, and each format once.
- **`QuillSpecTests`**
  - A loose draft is read, and a bad block is dropped alone.
  - Inline marks are read the same everywhere: "5 * 3" stays text, and a link keeps its parentheses.
  - Placeholders are the bracketed places, not links.
  - The Markdown reader reads what people write:
    - front matter, and a lone `#` as the title;
    - callouts, a quote's speaker, and pipe tables;
    - runs of `**Label:** value` as fields;
    - page breaks and figures.
- **`QuillLayoutTests`**
  - A Markdown report is laid out in Letter pages with running heads and page numbers, and written as every format
    asked. The PDF has selectable text and its title set.
  - No paragraph leaves one line alone on a page.
  - A page limit is met by tightening, or is said as the number of words to cut.
  - Every form lays out.
- **`QuillDocxTests`**
  - Every part of the Word file is well-formed XML and uses the named styles.
  - The Word file reads back through `NSAttributedString` with every block's text.
  - The same draft gives the same bytes.
  - Every form and every block kind writes a well-formed Word file.
- **`QuillDraftingTests`** (a stand-in model)
  - A clean letter is one ask, and the answer lists the places left to fill in.
  - A letter over its page limit is revised to fit.
  - What the brief does not give is handled:
    - a sender's lines, a signature or a date become places to fill in;
    - an invented figure goes back to the model.
  - A copied example is caught and rewritten.
  - A report is outlined, then written a section at a time.
  - A draft written before is changed as asked.
  - A revision the model fails keeps the best round.
  - A first draft that is not JSON is the model's refusal.
- **`QuillPagesTests`**
  - Pages failing is said as something the person can fix (Automation, or no answer in time).
  - Gated: a report is saved as a `.pages`, and the Word file made only for Pages does not stay.
- **`QuillBuildTests`** (gated)
  - Installed through Granite's `AgentInstaller`, as Craft installs it.
  - `--describe` names `quill` and its `makes`.
  - Over the wire, with no model:
    - a brief is refused as `model`;
    - a Markdown source comes back as a PDF, a Word file and the draft, laid out by the runner's own WebKit.

## Runs

- **2026-11-22, before the first push:**
  - `swift test`: green.
  - `QUILL_BUILD=1`: green in 122 s.
  - The kept fixture opened by hand:
    - the PDF has five Letter pages, running heads, a forced break, and a table split between rows;
    - the Word file in Quick Look is set in Charter, with real headings and lists.
  - `QUILL_PAGES=1`, run live after the push:
    - Pages 15 (Pages Creator Studio, `com.apple.Pages`) saved a 6-page `.pages` from a cold launch in 6 s, and quit
      after. Pages set the text in Charter, with the title block, real headings and "1 of 6" in the footer.
    - The first attempt failed twice. The old bundle id, `com.apple.iWork.Pages`, is Pages 14. Beside Pages 15 it
      waits behind an "out of date" dialog no one sees while it is hidden. And Pages 15 is sandboxed, so a file named
      in an AppleScript `open` "can't be opened right now". Now Pages 15 is asked first, the file is handed over
      through Launch Services, and AppleScript only saves the document and closes it.

## Through Craft

Not yet run: waiting for the Craft update to land.
