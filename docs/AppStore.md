# Take on the Mac App Store

What goes into the App Store Connect record, and what is left to decide.
`scripts/appstore.sh` builds and uploads; this file is the rest.

## App record (create once, at appstoreconnect.apple.com)

- Platform: macOS
- Name: Take
- Primary language: English (U.S.)
- Bundle ID: com.siddharthnigam.take (registered by Xcode already)
- SKU: take-mac
- User access: full

## Version information

**Subtitle** (30 characters)

    Write a novel in takes

**Promotional text** (170 characters, can change without a review)

    Every scene can have takes: alternate versions written side by side,
    then kept or discarded. Your manuscript stays a folder on your Mac.

**Description**

    Take is a Mac app for writing a novel, with the manuscript kept as a
    folder of Markdown files and its whole history kept for you.

    Every scene can have takes: alternate versions written side by side.
    Keep the one that works, discard the rest, and bring a discarded take
    back whenever you change your mind. Compare any two versions paragraph
    by paragraph, with the words that changed picked out, and fold a take
    into the draft one paragraph at a time.

    Mark milestones and see, scene by scene, what has moved since. Map a
    chapter as its scenes in a line with every take beneath. Search the
    whole draft. Keep notes in the prose that never reach the page.

    Counts and targets: words per chapter and for the whole, today's words,
    a target for the day and for the book.

    Export as Markdown, Word or PDF, a chapter or the whole. Import a
    manuscript you have already written. Back up the whole project, takes
    and all, to a git remote of your own.

    Untangle asks Apple's on-device model to lay out a scene's beats.
    Three Takes, with your own Anthropic API key, writes three angles on a
    scene and lands each as a take for you to read, keep or discard.

    Your manuscript is a git repository under a folder you choose. Any
    other tool reads it as plain files; git reads it as history. Take has
    no account, no server, and sends nothing anywhere unless you ask.

**Keywords** (100 characters)

    novel,writing,manuscript,draft,fiction,author,scrivener,markdown,takes,versions,git,book

**Support URL**: needs a public page. The repository is private, so
either make it public, or put `docs/Privacy.md` and a support line on a
GitHub Pages site or whynaught.

**Privacy policy URL**: same page, the contents of `docs/Privacy.md`.

**Category**: Productivity. Secondary: none.

**Copyright**: © 2026 Siddharth Nigam

**Age rating**: none of the content descriptors apply; 4+.

**Pricing**: undecided. Free, paid, or free with nothing to buy: there is
no in-app purchase in the app, so a paid price is the only way to charge.

## App privacy (the questionnaire)

Data collection: **No, we do not collect data from this app.**

That is true as written: Take has no analytics, no account, and the text
sent to Anthropic or to a git remote goes under the writer's own
credentials, at the writer's request, to a service the writer chose.
Say so in the review notes, since a reviewer will see the network
entitlement.

## Review notes

    Take keeps a novel as a folder of Markdown files with a git
    repository inside it. Nothing is sent anywhere by default.

    To try it: File > Open Sample loads a sample project with several
    scenes. Select a scene, edit, ⌘S to checkpoint. Take > New Take
    starts an alternate version of the scene; Keep or Discard it from
    the inspector. Compare shows the difference. ⌥⌘M opens the chapter
    map.

    Two features reach the network, both optional and both under
    credentials the writer enters:
    - Three Takes calls Anthropic's API with an API key the writer
      enters in Settings. Without a key the menu item explains what it
      needs. No key is required to use the app.
    - Draft > Back Up pushes the git repository to a remote URL the
      writer enters, with a token they enter.

    Untangle uses Apple's on-device Foundation model and needs Apple
    Intelligence turned on.

    Export compliance: the app uses only the system's TLS (URLSession),
    which is exempt.

## Screenshots

Mac screenshots must be 16:10, one of 1280×800, 1440×900, 2560×1600 or
2880×1800, and at least one is required. The set, in order:

1. The sample project open: binder, a scene in the editor, inspector.
2. A scene with its takes in the inspector, one selected.
3. Compare, with a paragraph link showing.
4. The chapter map with takes on the spine.
5. Since, after a milestone.
6. Settings, the Accent choice.

They are made without a hand on the mouse: `-TakeShot <pose>` on the
command line opens the sample and poses the window (`take`, `compare`,
`map`, `since`, `settings`; no pose for the first), a window capture is
taken with `screencapture -l`, and `scripts/screenshot.swift` lays it on
the store canvas. The window is 1152×720 points so the capture is 2304×1440
and sits on the 2560×1600 canvas unscaled.

## Open decisions before submission

- Pricing.
- Where the privacy policy and support page live.
- Whether to ship Three Takes in the store build at all. Bring-your-own
  API key is allowed; the risk is a reviewer without a key marking the
  feature as broken. The review note covers it, and a demo key in the
  notes would remove the doubt.
- Whether to keep the Developer ID release and the store build in step,
  or let the store lag.
