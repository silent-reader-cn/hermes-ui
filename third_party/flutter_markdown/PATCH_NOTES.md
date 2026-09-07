# Patch notes for third_party/flutter_markdown_patched
#
# Vendored from flutter_markdown 0.7.7+1 (discontinued upstream;
# pub.dev points to flutter_markdown_plus which we deliberately do
# not adopt this cycle to keep the diff minimal).
#
# Root cause of "Bad state: Too many elements" (crash dialog when
# previewing README files with badge images [![x](y)](z)):
# MarkdownBuilder._addAnonymousBlockIfNeeded() used `_inlines.single`,
# which throws when a link-wrapped block-level image leaves more than
# one inline element on the stack at flush time (p > a > img).

## 1. lib/src/builder.dart
- `_addAnonymousBlockIfNeeded`: merge ALL accumulated inline elements
  into one block (children of every `_InlineElement` in order) instead
  of asserting exactly one.
- `visitElementAfter` inline unwind: skip the pop when the inline stack
  is already empty (link `a` unwinds after the img builder already
  dropped its own inline).

## 2. lib/src/widget.dart
- `_parseMarkdown` wraps `builder.build(astNodes)` in try/catch:
  any builder crash now degrades to a plain-text build of the source
  (second parse attempt) instead of surfacing a widgets-library
  exception to the global error dialog. Recognizers created during the
  failed attempt are disposed before fallback.

## 3. lib/src/builder.dart (block-tag scoping)
- The package-global `_kBlockTags` list was mutated by
  `build()` (builder registrations appended, never removed). The first
  MarkdownBody that registered `img` as a block element permanently
  changed block semantics for every later MarkdownBody in the process
  (e.g. file-preview/memory pages silently lost default inline img
  rendering). Block tags are now a per-builder list initialised from
  `_kDefaultBlockTags` and rebuilt on each `build()`.

## Regression tests
- test/features/chat/widgets/markdown_image_link_crash_test.dart

Patch author: hermes-ui maintainers, 2026-09-07.
