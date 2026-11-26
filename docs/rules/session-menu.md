# The target and its menu

This file covers the toolbar's target and the session menu it opens. The bar is in `annotator-toolbar.md`.

- The target shows the agent's logo and the session's title, cut in the middle past 132 pt, with
  the title, details and repository in its tooltip (`SessionMenu.row(of:among:)`). Its width is set, so it springs with the bar. Beside a message field it sits in the box's top row, rising with it out of the bar, parted from the words by a hairline where the grown box curves down, leaving a one-line tab (`targetWidth`, `FollowsFieldTop`, `FieldOutline`). There its hover shade, open-menu shade and focus ring are one rounded rectangle inset 2.5 pt, short of the hairline, concentric with the box, one line high (`TargetShade`). A
  pick from its menu is applied a turn later, after the menu's event loop ends, since a change
  made inside it jumped instead of animating. A pick whose image closed or was replaced while
  the menu was open, or in that turn, is dropped and logs `[send] pick dropped` (`Model.targetMenuImage`). Its menu is `SessionMenu.menu` (`docs/session-menu-2026-10-18.md`): the
  sessions the person sent to in the last 4 hours, newest send first, then the rest by when the agent last worked; five of them, with
  the target always among them but not first when another session can be: it trades places with the second row, whose group
  then leads (`targetNotFirst`), so Return in the empty search picks the likeliest other session. They are grouped under a header for each repository with Other folders last, then, after a separator, one submenu per project, titled as its header, with its count at its right and every
  running session of that project in it, the top rows too (live ink's Tab steps through the five only).
  The rows that start a session are in neither part unless no session is running (`docs/rules/send.md`). The menu's first row is a search field that has the keyboard: typing lists the matches, the project of the best-ranked one first, the rows that start one after the running ones (a query matches a row's details and the words at its right too; - and _ part words), Return picks the first, and Esc closes the menu (`SessionMenuSearch`). A row starts with its agent's logo, which macOS 27 shows only when the item asks for it (`SessionMenu.item`, `preferredImageVisibility`). A row's title is the name of the Herdr tab its terminal is in, unless Herdr numbered it, else
  the session's name. A session's row is one line: its details, the worktree, the branch and the
  inbox mod's goal (`SessionMenu.Row.details`; `InboxModStore` reads the mod's private file and may
  find nothing), are in its tooltip, under its title. At its right the row says
  working, after a green dot, while a turn runs, else when the session was last active
  (`SessionMenu.Activity`). Those words, and a project's count, follow the title after a right tab
  stop in its attributed title, with no `NSMenuItemBadge`, which has no API for its look or its
  distance from the chevron. `SessionMenuIndicators` sets one tab stop for each menu and
  submenu, past the widest row's text, its words and `SessionMenu.indicatorGap`, so the words end
  in one column; the search sets it again after each rebuild. A menu that holds a view, such as
  the search row, leaves the checkmark's column out of its width, so `SessionMenuIndicators` gives
  it a `minimumWidth` of the width AppKit measures for its other items alone; without it, a checked
  row's words wrap under its title on macOS 15. macOS 27 starts the title of an item
  with no image at the menu's left but measures it from where the others' titles start, so a
  project's row carries a clear 16 pt image (`SessionMenu.showSpace`) to end its count with the
  rows' words, 10 pt before the chevron. A menu with a submenu keeps the chevron's column on every
  row, so there the rows' words end that far short of the menu's right edge. The dot's centre sits on the middle of
  the word's x-height (`IndicatorItem.dotAttachment`). As the menu's delegate it redraws the
  highlighted row's words in `selectedMenuItemTextColor`, since they carry colours of their own. While a row says working, a soft band crosses the word letter by letter, one opacity per
  letter, on live ink's thinking clock (`SessionMenu.shimmer`, one beat across and one at rest), and the dot's soft glow is brightest as each
  pass starts and faintest as it ends, from
  a timer in the common run loop modes, which include the menu's tracking; the word and the dot are still under
  Reduce Motion or `ui.motion` 0, and the timer stops when the menu closes or no row says working. The time is
  in the secondary label grey, as the count and working are. Headers are section headers, as
  written, in AppKit's own section-header font, 11 pt semibold (`SessionMenu.header`). AppKit
  draws a section header's title in the tertiary grey, which replaces any system label colour or
  grey set on it, so the header's secondary grey is a colour of the app's own
  (`SessionMenu.own`). A row cuts its title to `SessionMenu.titleWidth`, since a menu with little
  room on screen wrapped a longer one and drew its first line (`SessionMenu.item`, `fitted`); the
  tooltip keeps it whole. Live ink's row for an agent on the screen that cannot answer says why on
  a second line, its subtitle. AppKit measures a subtitle wider than both its title and
  about 282 pt as two lines, yet draws one, leaving a blank line and the logo below the text, so
  `SessionMenu.setSubtitle` cuts it to fit and the tooltip keeps it whole. `SessionMenuBacking` puts the window colour behind the rows of the menu and each submenu; `QuietSearchField` has no bezel. A Claude Code session is active while the plugin's monitor runs in it,
  and a Codex thread when it was used in the last day, since nothing says which threads the Codex
  app has open.
  The target's menu is an `NSMenu` (`showTargetMenu`), since SwiftUI's `Menu`
  cannot be opened from a key. A press on the target opens it at once, as on a macOS pop-up button:
  the bar's panel opens it before SwiftUI's button, which acts on the release, sees the press (`ToolbarPanel.onPressMenu`,
  `AnnotatorToolbar.pressTarget`), and AppKit's menu tracking then has the press. Dragging onto a
  row and releasing picks it, and a release with no drag leaves the menu open for a second click.
  The press reaches
  the target where its button would take it, the box and its slop, and not while a send is under
  way or the bar is leaving (`Model.shown`). The button's own action is left to VoiceOver. While the
  menu is open, however it opened, the target darkens as a pop-up button does and hides its hairline (`TargetShade`).
  Space opens it a turn later: opened inside the editor's keyDown it took no keys, and a press on its item closed the editor as a press outside. In the message field,
  Up on the first line or Down on the last opens it the same way, as on a pop-up button, and the
  arrows then move through it (`ToolbarPanel.onMenuKey`). Opened from the keyboard, it opens with
  its first row highlighted, the row Return picks: once the search field has the keys, one Down key
  goes to the menu's own window (`SessionMenuSearch.install(highlightingFirstRow:)`). A press
  highlights nothing, as on a pop-up button.
