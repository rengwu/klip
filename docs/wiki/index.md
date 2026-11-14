---
title: Klip
updated: 2026-11-15
order: 0
---

# Klip

A simple clipboard manager for macOS, built in native Swift and AppKit. Version 0.1.0 is built to the decisions in the plan. Keyboard interaction still needs checking by hand; see the implementation page.

- [Plan: requirements, decisions and open questions](plan.md)
- [Implementation and validation](implementation.md)
- [Round 1 submitted answers](journal/2026-11-15-grill-7d3869271726245c7ebb9033e751b70f.md)
- [Round 2 submitted answers: panel and Settings designs](journal/2026-11-15-grill-fa5df67048705dd811815a067848e180.md)
- [Round 3 submitted answers: last details and go-ahead](journal/2026-11-15-grill-258f485c35ac2e1fd80af1bd43633e2a.md)

## Project workflow

At the user's request, this project uses the sibling `../jstack` workflows:

- `grill-form` presents decision rounds and design prototypes, following the `grill-me` process.
- `plan` interprets submitted answers and records accepted decisions in this wiki.
- `wiki` maintains these Markdown pages and the offline HTML reader.

Submitted forms are saved under `journal/`. A recommendation is not a decision until the user accepts it.

Markdown is authoritative. Rebuild the reader with `node docs/wiki/_build.mjs`, then validate it with `node docs/wiki/_build.mjs --check`.
