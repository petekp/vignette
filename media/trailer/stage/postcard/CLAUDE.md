# Postcard

Postcard plans trips. This folder is its front end, with a week in Tuscany as the trip it shows.

## How it is built

- Plain HTML and CSS, no build step. `index.html` is the itinerary, `stays.html` and
  `packing.html` are the other pages, and `styles.css` styles all three.
- The look: warm paper (`--page`), white cards (`--panel`), serif headings (`--serif`), terracotta
  for what matters (`--accent`) and olive for status (`--olive`). The map's numbered stops are
  terracotta circles with white numbers.
- A dev server serves this folder to the browser beside you, and the page reloads by itself when a
  file changes.
- `./screenshot <file.png> [page]` renders a page as that browser shows it, 904 by 565 at 2x. The
  page is `index.html` unless you name another.

## When the designer sends you a drawing

The designer draws on screenshots of the app in Vignette and sends them to you. Their arrows,
boxes and notes mark what to change.

1. Do what each mark asks when it has one clear answer. An arrow from one part of the app to
   another relates them, and its note says how. Keep each change to what was marked, and make it
   in the app's own look.
2. When a note asks for options, do not pick one. Make three versions of that part and ask which
   one:
   - Write `variants.html`, a page on the app's own styles that shows only the three versions, in
     one row, centred on the page, each the size of the real card and 16 px apart. Give each
     version the class `variant`. The three are, in this order:
     - a card tinted with the colours of its picture, with a terracotta title and button;
     - a card with a terracotta outline and a small "Highlight" flag, with the class `flag`,
       sitting on its top edge;
     - a card whose picture fills the whole card behind its text, redrawn taller for it.
   - Run `./screenshot variants.png variants.html`.
   - On that image, put a text mark "A", "B" and "C" above the versions, and one text mark
     "Which one?" below the middle one. Give each of them `"color": "violet"`, so they read as
     yours next to the designer's red marks. Add no other marks. Write the marks as the vignette
     skill describes, to `variants.json` in this folder.
   - Run `./push variants.png variants.json`, which shows it in Vignette as yours. Use it instead
     of the skill's `open` command.
3. Stop, and say in one or two lines what you changed and that the options are in Vignette.

When the designer replies to your options, their box marks the one they chose. Their other marks
say what to change in it, and may point at a part of another version to bring in. Build that
version into the page, with those changes, and say in one line what you did. Do not push another
screenshot.

This folder allows `./screenshot` and `./push` and no other shell commands, only as written above:
one command per call, with nothing added before or after it, no `;`, `&&` or `echo`. Each prints
what it did, and exits non-zero if it failed.
