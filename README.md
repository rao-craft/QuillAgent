# QuillAgent

Ask for a document and get it finished: a letter or cover letter, a memo, a report, a resume, a proposal, a contract, a
worksheet or a one-pager, laid out in pages and written as PDF, Word, Pages, HTML or Markdown. Say `$quill` in Craft.
The model writes the words. Quill lays them out in pages in the form's house style, measures the pages, and fixes what
falls short. Then it writes every file from one draft, so the Word file says what the PDF says. It never invents a
name, an address, a date or a figure: what you did not give is left as a bracketed place for you to fill in, and the
answer lists each one.

## What you can ask

```
$quill a cover letter from Dana Reyes to Northwind for the data analyst role, as a Word file
$quill a one-page resume from my notes in about-me.md, as Pages
$quill turn notes/q3.md into a report for the board
$quill a proposal for Harbor Library's reading room, with a price table, as Word and PDF
$quill a memo to the team: the office closes at noon on Friday
$quill a worksheet of ten fraction problems for year 5, with a name and date line
$quill make the cover letter shorter and warmer
```

Craft writes the call from your request and shows it on its agent map as `quill-1`. The PDF opens in Canvas.

## What you get

- **The PDF, always.** Every call writes one, at the paper's own size (US Letter or A4), with selectable text, its title
  and author set, and page numbers along the foot. Craft shows it in Canvas whatever else you asked for.
- **A Word file.** Unless you name other formats, you also get a `.docx` that Word and Pages open and you keep
  editing. It is written from the same draft, not converted from the PDF:
  - named styles (Title, Heading 1–3, Quote, Callout, Caption), so you restyle the whole document in one place;
  - real bullet and numbered lists, and tables whose header row repeats on every page;
  - the PDF's paper and margins, and a footer with live page numbers;
  - links and pictures.
- **A Pages file.** Pages itself saves the Word file as a `.pages`: there is no other honest way to write one.
- **HTML and Markdown.** The HTML is the same document as a single page you open in a browser or print. The Markdown
  has the same blocks, front matter included, and reads back to the same draft.
- **The draft.** `<name>.quill.json` (`quill-document/1`) sits beside the files. Give it back as `spec` to write the
  document again, or to change it ("make it shorter").
- **What is left to you.** Every bracketed place (`[Hiring Manager's Name]`, `[Phone]`, `[figure]`) is listed in the
  answer. So is any line Quill replaced because you never gave it.

The files go in `quill/<title>/` in your project, or wherever `output` says (`Letters/cover-letter.docx`).

## How it works

- **The model writes the words, the kit owns the page.** The draft is a list of blocks (heading, paragraph, list,
  table, quote, callout, figure, fields, signature line, code, rule, page break) with a little inline bold, italic,
  code and links. It never contains HTML or a size, so a model on your Mac never has to get CSS right.
- **WebKit lays out the pages.** The body flows through columns one page wide and one page tall. WebKit breaks it into
  pages itself, keeping a table row, a quote or a callout whole and a heading with its text, and each page is cut out
  as a PDF page. There is no window and no print dialog.
- **The kit fixes the page.** It pushes a paragraph to the next page rather than leave one line of it alone. Over a
  page limit, it tightens the spacing, then the margins, then the type, one step at a time, never below floors a reader
  can still read. What will not fit goes back to the model with the number of words to cut.
- **The model fixes the words.** Pages over the limit, a table wider than the page, a figure no one gave, or a copied
  example go back to the model, up to three rounds. The best round is kept.
- **Nothing invented.** A sender's or recipient's line, an author, a date, a signature or a quote's speaker that the
  brief and the sources do not give is replaced by a bracketed place before the pages are laid out. A figure in the
  body that you never gave goes back to the model to remove.
- **Long documents are planned first.** A report, proposal or contract is outlined, then written one section at a time,
  with your sources beside every section.
- **A Markdown file is laid out as written.** Give one Markdown source and no brief, and no model is asked at all.

## Works well with

`$plate` draws a figure (an infographic, a flow) that a document can carry: name its PNG in the brief. Saved sessions
recall what `$quill` wrote before in a project, and the `spec` beside each document lets a later call change it.

## Get it

In Craft, run `craft agents add https://github.com/rao-craft/QuillAgent.git`, then say `$quill` with what you need.

## Requirements

- A Mac on macOS 26 or later. WebKit's `WebPage` lays the pages out in-process.
- Pages, only for `.pages` files. The first time, macOS asks whether Craft may control Pages. Without Pages, or without
  that permission, the Word file is written and the answer says to open it in Pages.
- Faces every Mac has: Charter, Helvetica Neue and Menlo. Nothing is bundled.
- MIT. It links Granite alone.

## For developers

What a call takes and answers is in [Schema/](Schema/), and how it is tested is in [TESTING.md](TESTING.md).

- `QuillLoop` finds the draft: a spec, a Markdown source as written, or the model's.
- `QuillDrafting` is the model's part: the asks, grounding, checks and rounds.
- `Kit/` composes the HTML.
- `QuillPaging` is the layout loop over `QuillRenderer`'s WebKit page.
- The writers are in `Write/`. `QuillDocxWriter` writes WordprocessingML by hand, in the schema's element order, into
  a stored zip with fixed timestamps, so the same draft gives the same bytes.

## License

MIT. See [LICENSE](LICENSE).
