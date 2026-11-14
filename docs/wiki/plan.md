---
title: Plan
updated: 2026-11-15
order: 1
---

# Plan

## Current phase

Version 0.1.0 is built; see [implementation and validation](implementation.md) for what was tested and what still needs checking by hand. Decisions were settled over three grill-form rounds, and the user authorized implementation in [round 3](journal/2026-11-15-grill-258f485c35ac2e1fd80af1bd43633e2a.md).

## Requirements

From the user's opening request on 2026-11-15:

- Save text and images.
- Native Swift/AppKit UI, with `../yacht` as the reference.
- Configurable decay time, up to 30 days.
- Configurable maximum store size.
- A keyboard shortcut shows the panel.
- The panel highlights the first item, which is the most recently copied.
- The panel loads further items as the user scrolls down.
- The panel is searchable.
- Follow jstack conventions and keep the development journey and decisions in this wiki.

## Accepted decisions

From [round 1](journal/2026-11-15-grill-7d3869271726245c7ebb9033e751b70f.md):

**Capture**

- Content types: plain text, rich text, images, and file references (paths only, not file contents).
- Rich text has a Settings switch. With it off, Klip keeps plain text only.
- Copies marked concealed or transient (the `org.nspasteboard` markers password managers set) are skipped by default. A Settings switch records everything instead.
- Copying something already in history moves the existing item to the top and refreshes its decay timer.

**Panel**

- Default shortcut ⇧⌘V, rebindable in Settings.
- Return pastes into the previous app. Without the Accessibility permission it copies to the clipboard instead.
- Search is a case-insensitive substring match.
- ⌘⌫ deletes the highlighted item (round 2; round 1's plain ⌫ would collide with editing the search). There is a clear-all action.
- ⌘1–⌘9 select the first nine items.
- Items can be pinned. Pinned items never decay.

**Limits**

- Decay defaults to 7 days, configurable up to 30 days.
- Store size is measured in bytes on disk and defaults to 500 MB. The oldest items are evicted first.

**App**

- Menu bar icon without a Dock icon. The icon can be hidden in Settings.
- Launch at login is offered.
- Build setup follows Yacht: SwiftPM with Command Line Tools only, a core library without AppKit plus a thin AppKit app, tests as a plain executable, `build.sh` producing an ad-hoc-signed universal app, macOS 13+. SQLite through the system `libsqlite3`, images as files beside the database, no third-party packages.

**Left out of the first version:** links and colors as distinct types, a per-app ignore list, paste as plain text, pause capture, OCR for images, and showing the source app.

From [round 2](journal/2026-11-15-grill-fa5df67048705dd811815a067848e180.md):

**Panel design**

- Design A, the compact list: a search field above one-line rows, 420 pt wide. Designs B (preview pane) and C (roomy rows) were not chosen.
- Text starts at the same position on every row, whatever the item type. Icons and image thumbnails share one fixed-width leading column.
- The key-hint footer can be hidden through a Settings switch.
- The panel opens centered on the active screen.
- Pinned items stay in their chronological place with a pin mark. A pinned-only filter shows just the pins.
- The Settings mock was accepted as shown (“looks ok”), with the footer switch to be added.

From [round 3](journal/2026-11-15-grill-258f485c35ac2e1fd80af1bd43633e2a.md):

- The revised design A drew no objection.
- The key-hint footer is shown by default.
- ⌘P pins or unpins the highlighted item; ⇧⌘P toggles the pinned-only filter.
- With “Keep text formatting” off, formatting is not stored: new items are plain text only. Items saved while it was on keep theirs.
- Pinned items count toward the size limit and are never evicted.
- A single item larger than 10% of the size limit is not saved.

### Implementation choices

Made by the agent while building, within the decisions above. None was put to the user:

- The shortest decay setting is 1 hour. Settings offers 1 hour, 1 day, 3 days, 7 days, 14 days and 30 days; sizes are 100 MB, 250 MB, 500 MB, 1 GB and 2 GB.
- With the menu bar icon hidden, Settings opens with ⌘, in the panel or by opening Klip again, as Yacht does.
- Clear History keeps pinned items.
- ⌘1–⌘9 paste the item directly.
- When a copy carries both text and an image, the text is kept. Files copied in Finder are stored as paths.
- Pasting an item moves it to the top.

## Open questions

None blocking.
