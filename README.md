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
  paragraphs that changed, against any version or milestone.
- **The map** draws a chapter as its scenes in a line with every take
  beneath.
- **Untangle** reads a scene on Apple's on-device model and fills a fixed
  template: the scene's job, the value shift, its beats, what the reader
  needs, and a smallest version. Nothing leaves the Mac.
- **Three Takes** writes the open scene three ways on Claude, under the
  writer's own API key, each take on its own angle. This is the one thing
  that sends text off the Mac; a consent sheet says so first.
- **Export** as a folder of Markdown or as a Word document.

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
real emphasis in exports; `* * *` on a line of its own is a scene break.

## Commits

Subjects read `raise, …` for something new, `mend, …` for a fix and
`hold, …` for upkeep, followed by a body in prose that says what was wrong
or missing, what changed and why, and `Seen:` with how a bug showed itself.
