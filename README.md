# Take

A Mac app for writing a novel, with the manuscript kept as a git
repository and every scene able to have *takes*: alternate versions
written side by side, then kept or discarded.

## What it does

- **A project is a folder with a git repository in it.** `manuscript.json`
  at the root holds the order of parts, chapters and scenes; each scene is
  one Markdown file under `chapters/`. Main is always checked out, so the
  folder reads as the current draft to any other tool, and `git log` reads
  as the draft's history.
- **Saves are checkpoints** on main, made ten seconds after the last
  keystroke, on ⌘S, and before anything that changes the manuscript's shape
  or the app quits.
- **A take** is a branch scoped to one scene, under
  `refs/takes/<scene>/<name>`. Keeping it lands the scene on main as a
  merge; if main's copy of the scene moved meanwhile, the writer chooses one
  whole scene. Discarding moves the ref under `refs/discarded/`, from where
  Restore brings it back.
- **Milestones** are annotated tags under `refs/tags/milestones/`, so the
  whole draft can be marked and any scene compared against how it stood.
- **Compare** shows a paragraph-level diff, with word-level detail inside
  paragraphs that changed, against any version or milestone. A link on each
  paragraph that differs takes the other side, so a take can be folded into
  main a paragraph at a time.
- **Since** lists every scene against a milestone: the words that came and
  went, the scenes added and gone.
- **The map** draws a chapter as its scenes in a line with every take
  beneath.
- **Each scene has a synopsis and notes**, kept in the manifest, shown in
  the binder and on the map, and handed to the engines. `[[A note]]` in the
  prose is dimmed on the page, listed in the Scene pane, and never exported.
- **Find** (⇧⌘F) searches the whole draft, and the takes when asked; case
  and accents do not matter.
- **Counts and targets**: words per chapter and for the draft in the binder,
  the day's words in the status bar, a target for the whole and for the day.
- **Recently removed** scenes come back from history with their text and
  their takes.
- **Untangle** reads a scene on Apple's on-device model and fills a fixed
  template: the scene's job, the value shift, its beats, what the reader
  needs, and a smallest version. Nothing leaves the Mac.
- **Three Takes** writes the open scene three ways on Claude, under the
  writer's own API key, each take on its own angle. A consent sheet says so
  first.
- **Import** a Markdown or text file (headings and `* * *` become chapters
  and scenes), a Word document, or a folder of Markdown files; a project
  folder that lost its `.git` is taken in as it stands.
- **Export** the draft or one chapter as a folder of Markdown, a Word
  document or a PDF.
- **Back Up** (⇧⌘B) pushes main, the milestones and every take to a remote
  over HTTPS with a token from the keychain. This and Three Takes are the two
  things that send anything off the Mac.

## Layout

```
project.yml      XcodeGen spec; Take.xcodeproj is generated and not committed
ManuscriptKit/   SwiftPM library: the git overlay, the store, prose rules, the differ, exports
Take/            The SwiftUI and AppKit app
Vendor/          libgit2, built from source under SwiftPM
```

ManuscriptKit has no UI and is where the tests are. The app keeps only what
needs AppKit, SwiftUI, the keychain or the engines.

## Building

Requires macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
xcodegen generate          # writes Take.xcodeproj
open Take.xcodeproj        # build and run the Take scheme
cd ManuscriptKit && swift test
```

The tests shell out to `/usr/bin/git` to check that the system git reads
what the app writes.

### Releasing

`scripts/release.sh` archives the Release build, signs it with the
Developer ID, and zips it under `dist/`. With `NOTARY_PROFILE=Take` in the
environment it also sends the zip to Apple's notary service, waits, and
staples the ticket, so the app opens on any Mac without a warning. The
profile is made once with `xcrun notarytool store-credentials`.

The icon is drawn by `scripts/icon.swift`; run it from the repository root
after changing the drawing and the asset catalog is rewritten.

For the Mac App Store, `scripts/appstore.sh` archives and exports a signed
installer package, and with `UPLOAD=1` sends it to App Store Connect; the
listing, privacy answers and review notes are in `docs/AppStore.md`, the
privacy policy in `docs/Privacy.md`. `scripts/screenshot.swift` lays a
window capture on a 2560×1600 canvas for the store.

CI (`.github/workflows/ci.yml`) runs the package tests and a Release build
on a macOS 26 runner for every push to main and every pull request.

### Bench

Run the app with `-TakeBench` and it loads the sample scene and a 20k-word
stress text into the real window, types into each, writes the timings to
`bench.json` beside the sample project in the app's container, and quits.
The Stress button and the load-time readout appear only in that mode.

## Prose

Scenes are stored as Markdown with one paragraph per line, a blank line
between paragraphs and no hard wrapping; `Prose` in ManuscriptKit is the
one place those rules live. The editor shows the same text with no blank
lines, one paragraph per line, so a return is always a new paragraph.
`*italic*`, `_italic_` and `**bold**` are dimmed in the editor and become
real emphasis in exports; `* * *` on a line of its own is a scene break;
`[[a note]]` is the writer's and leaves with no export.

## The manifest

`manuscript.json` is format 3: parts, chapters and scenes with their
titles, paths, synopses and notes, and the word targets. A format-2 file
(no synopses, notes or targets) opens as it is and is written back as 3 by
its next commit.

## Commits

Subjects read `raise, …` for something new, `mend, …` for a fix and
`hold, …` for upkeep, followed by a body in prose that says what was wrong
or missing, what changed and why, and `Seen:` with how a bug showed itself.
