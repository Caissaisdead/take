# Take on the Mac and the iPhone

The design for both apps: what each screen holds, how they are reached,
what the two share and where they differ. The Mac app keeps the shape it
has; this document names the small things to align. The iPhone app is
designed here for the first time. The mockups in `docs/mockups/index.html`
draw the key screens of both.

## One idea, two shapes

Take is a manuscript as a git repository with takes on every scene. On the
Mac the writer sits with three columns: the binder, the page, and an
inspector that answers questions about the page. On the phone the writer
is standing, reading back, fixing a line, catching a thought. So:

- The **Mac** is for writing and revising. Every pane is on screen at once.
- The **iPhone** is for reading, small edits, notes, and having the draft
  with you. One thing on screen at a time; the inspector's panes become
  sheets pulled up over the page; anything the Mac does in a column, the
  phone does in a push or a sheet.
- The **iPad** is the Mac's layout on a touch screen: the binder as a
  sidebar, the page, the inspector as a trailing column when wide and a
  sheet when narrow. Nothing is designed for the iPad alone.

Both apps run on ManuscriptKit unchanged. The phone never has less of the
manuscript than the Mac: every take, milestone, note and count is there.

## Shared language

| Thing | Symbol | Word |
|---|---|---|
| Scene on main | `doc.text` | Main |
| Take | `arrow.triangle.branch` | Take |
| Discarded take | `arrow.triangle.branch` faded | Discarded |
| Milestone | `flag` | Milestone |
| Versions pane | `clock` | Versions |
| Compare | `doc.on.doc` | Compare |
| Scene pane (synopsis, notes) | `note.text` | Scene |
| Find | `magnifyingglass` | Find |
| Untangle | `wand.and.sparkles` | Untangle |
| Three Takes | `sparkles` | Three Takes |
| Map | `map` | Map |
| Since | `clock.arrow.circlepath` | Since |
| Keep | `checkmark.circle` | Keep |
| Discard | `xmark.circle` | Discard |
| Back up / pull | `icloud.and.arrow.up` / `icloud.and.arrow.down` | Back Up / Pull |
| Unsaved | small orange dot | (none) |

Verbs are the same everywhere: Keep, Discard, Restore, Mark (a milestone),
Take (a paragraph), Back Up, Pull. A thing is never "synced", "deleted" or
"reverted"; it is backed up, removed, or brought back.

### Type

- **UI**: the system face (SF Pro on both). Sizes follow the platform's text
  styles; the binder is `body`, its synopsis line `caption`, counts
  `caption` with tabular digits.
- **Prose**: the system serif (New York) at 17pt on the Mac, 18pt on the
  phone; line height 1.5 on the Mac, 1.45 on the phone where lines are
  shorter. Paragraph spacing is the gap between paragraphs (there are no
  blank lines in the editor). Emphasis markers, `[[notes]]` and scene
  breaks are dimmed to the tertiary label colour, italic for notes.
- **Measure**: the phone's page keeps 20pt side margins; the Mac's keeps
  32pt. Neither centres a narrow column: the page is the width it has.

### Colour

The platform's. The accent is the system accent; the only fixed colours
are the diff's red (removed) and green (added), the orange unsaved dot, and
the map's tint on live takes (the accent at 8% for the fill). Dark mode is
the system's, with no colour of the app's own that needs a second version.

### Words in the status line

One sentence, present tense, no exclamation, naming the thing: "Kept Take 2
as 3f1c9a2", "Main changed since Take 2 began; nothing written", "Backed up
to github.com/…". Failures say what and what to do: "The remote has changes
this Mac does not; pull them before backing up again."

## The Mac

The layout stays: binder (min 220), page, inspector (min 280, wider for
Compare), the status bar under the page, the map and Since in place of the
page. What changes is alignment with the phone and a few loose ends:

1. **Toolbar in three groups**, left to right: *make* (New Scene, Save),
   *this take* (New Take; Keep and Discard when in a take), *views*
   (Compare, Map, Since, Inspector). The Milestone button moves to the
   *make* group. Symbols from the table above on every button that has one.
2. **Inspector tabs** are icons with their names as help; the selected tab's
   name shows beside the picker in `caption` so a new writer is never lost.
3. **Status bar order**: what is open · unsaved dot · this scene's words ·
   today · (bench readouts) · the message, right-aligned. The message
   truncates in the middle, never the counts.
4. **Binder rows** carry the synopsis under the title, chapter words at the
   right of the header, the total and target at the bottom, and Recently
   removed last; all in place.
5. **Sheets** (name, targets, consent, conflict, Three Takes) share one
   width rule: 360 for a name or numbers, 460 for a consent, 520 for a
   progress sheet, full-window for the conflict's three columns.
6. **Every menu item has the phone's word for it.** Draft > Back Up stays;
   a Draft > Pull is added once the Mac can pull (part-3's code), with the
   same conflict rule as the phone below.

## The iPhone

### Screen map

```
Projects
└─ Binder (one project)
   ├─ Editor (a scene, main or a take)
   │    sheets: Takes · Versions · Compare · Scene · Untangle · Three Takes
   ├─ Find (sheet over the binder)
   ├─ Map (push)
   ├─ Since (push)
   └─ Project settings (sheet): remote, token, targets, export, key
```

One `NavigationStack`. Sheets use the medium and large detents and keep the
page visible behind them at medium, so a Compare can be read against the
text. A sheet never covers a sheet: opening Versions from Compare replaces
it.

### Projects

The first screen, and the one the app opens on unless a project was open
when it quit. A list of the projects on the phone, each a row: title, the
words and chapters, and when it was last pulled or backed up. Two ways to
add one:

- **Pull from a remote**: a URL and the token, the same as the Mac's backup
  settings. The phone clones into its own container.
- **Open a folder**: a project folder in iCloud Drive or another provider,
  through the document picker; the phone works on it in place.

The sample project is here too, seeded on first launch, so the app is
never empty.

### Binder

The chapters as sections, parts as larger headers when the manuscript uses
them, one row per scene: title, the synopsis in caption under it, the words
at the right in tabular caption. Swipe a scene for Rename and Remove; long
press for New Scene After, Move (a sheet with the chapter list), Export.
The chapter header's menu: New Scene, Rename, Export Chapter, Remove.

The bottom of the list: the draft's total against the target, with the
thin progress bar, then Recently removed with Restore buttons.

Toolbar: Find (`magnifyingglass`), Map, Since, and a menu (`ellipsis.circle`)
for New Chapter, New Part, Mark Milestone, Targets, Pull, Back Up, Project
settings. A `+` in the navigation bar adds a scene at the end of the open
chapter.

The title is the manuscript's; under it, in caption, "today +812" and
"backed up 3 min ago" when there is a remote.

### Editor

The page, edge to edge, the scene's title in the navigation bar. Under the
title, in caption, which text this is: "Main", or "Take 2", with a chevron;
tapping it opens the **Takes** sheet (below).

The keyboard's accessory bar has, left to right: `*` (wrap the selection in
italics), `**` (bold), `[[ ]]` (a note), `* * *` (a scene break on its own
line), a paragraph-jump pair (previous, next), and Done. Nothing else: the
phone is for lines, not formatting.

Saves are as on the Mac: ten seconds after the last keystroke, when the
scene is left, when the app goes to the background. The unsaved dot sits at
the trailing end of the caption line.

The navigation bar's trailing menu (`ellipsis.circle`): Compare, Versions,
Scene, Untangle, Three Takes, New Take; and, in a take, Keep and Discard
above a divider. Keep and Discard also appear as a pair of buttons in a
thin bar above the keyboard accessory when a take is open, so the two
things a take exists for are one tap away.

### Takes (sheet, medium)

The scene's texts: Main first, then each live take with its word delta
against main ("+120 −38") and its saves, then Discarded with Restore. A row
opens that text in the editor. "New Take…" at the bottom.

### Versions (sheet, large)

The Mac's Versions pane: milestones, then history, each with Restore. On
the phone Restore loads the version into the editor unsaved, exactly as on
the Mac, and the caption says "Restored First draft, unsaved".

### Compare (sheet, medium or large)

A picker at the top ("Previous version", "Main now" in a take, the
milestones, the versions); the summary line; the diff. The Mac's paragraph
links become buttons under each changed paragraph: "Take theirs", "Bring
back", "Drop". At the medium detent the page stays visible above the
sheet, so a writer reads the diff against the text.

### Scene (sheet, medium)

Synopsis field, notes editor, the `[[notes]]` in the text with a tap to
select each. Saved two seconds after the last keystroke and when the sheet
closes, as on the Mac.

### Find (sheet over the binder, large)

The field first, focused, with "Takes too"; results grouped by chapter and
scene with the hit in bold; a tap opens the editor on that scene with the
hit selected and dismisses the sheet.

### Untangle (sheet, large)

The Mac's pane. Runs on the device's model on an iPhone that has Apple
Intelligence; on one that does not, the sheet says so and offers nothing
else. Nothing leaves the phone.

### Three Takes (sheet, large)

The consent sheet, then the three angles with their progress, then the
takes appear in the Takes sheet. Needs the API key from Project settings.
The phone sends exactly what the Mac sends, and says so on the consent
sheet.

### Map (push)

The Mac's map is wide; the phone's is tall. A list: each scene as a card
with its words and synopsis, and its takes as indented cards beneath, live
ones tinted, discarded ones faded and dashed, each with "+n −m vs main"
and saves. A card opens the text. The chapter picker is a menu in the
navigation bar.

### Since (push)

The Mac's Since as a grouped list: the milestone picker in the navigation
bar, the totals line, then rows with the change symbol, the counts and the
bar. A row opens the editor with Compare set to that milestone.

### Project settings (sheet, large)

Remote URL and token, Back Up Now and Pull Now with the last time of each;
targets; the Anthropic key and model with Check Key; "Ask before each send";
export (Markdown to the Files app, PDF); Remove from this iPhone (the clone
only; the remote and the Mac keep everything).

### Pull, and what happens when both sides moved

Pull fetches the remote and fast-forwards main when the phone has no
commits of its own since the last common point. When both sides have
moved, the phone does not merge prose. It shows a sheet: "The remote and
this iPhone both changed since they last agreed", with the scenes that
differ, and one button: **Keep mine as takes**. That makes a take of each
scene the phone changed, named "iPhone <date>", then sets main to the
remote's. Nothing is lost, the takes are where takes go, and the Mac sees
them on its next pull. The Mac gets the same rule.

### What the phone does not do

Word export (AppKit's writer is not on iOS; PDF and Markdown are). The
bench. Reveal in Finder and Open in Terminal. Drag to reorder scenes across
chapters (Move is a sheet). Everything else the Mac does, the phone does.

## Interaction rules both apps keep

- A destructive step (Remove, Discard, Remove from this iPhone) always
  confirms and always says where the thing still is.
- Nothing the writer typed is ever dropped without a sentence saying so
  first.
- A take is made from main, never from another take; the phone's caption
  and the Mac's status line both say "Started Take 3 from 3f1c9a2".
- The app never merges prose on its own. Whole scene (the conflict sheet)
  or one paragraph at the writer's tap (Compare), or a take.
- What leaves the device is named where it happens: the consent sheet for
  Three Takes, the settings for Back Up and Pull.

## Building it

Part-3's code, in order: `Repository.fetch` and a fast-forward `pull` in
ManuscriptKit with the diverged-to-takes rule and tests; a `TakeMobile`
target in `project.yml` sharing ManuscriptKit; the Projects screen and the
clone; the binder; the editor on `UITextView` with the `ProseStyler` port;
the sheets in the order above; the Mac's tidy list. Untangle and Three
Takes port last, since their engines are already platform-neutral.
