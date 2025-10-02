Title: Live editing: expand edge‑case coverage (decorators, graphemes, word/line, multi‑node, structural+text)

Summary
- Adds UI and read‑only tests that harden live editing behavior across challenging scenarios:
  - Decorators (inline images): deleteWord forward across attachment; backspace/forward‑delete adjacency; range deletes spanning text+image+text.
  - Grapheme backspace: combining marks and ZWJ family emoji (read‑only via explicit selection; UI via native tokenizer).
  - Word/line granularity (UI): deleteWord forward/back; deterministic line deletes via explicit selection ranges.
  - Attribute toggles while typing: bold on/off around entered/removed characters.
  - Multi‑node text edits in one update: central aggregation path parity.
  - Structural + text in the same update: insertParagraph + neighbor edits.
  - Selection stability with unrelated edits elsewhere in the document.
  - Paste then deleteWord (UI): final text parity around caret.

Changes
- LexicalTests/Tests/OptimizedReconcilerLiveEditingTests.swift
  - New: testMultiNodeEditsInSingleUpdate_TextOnly, testStructuralAndTextInSameUpdate_InsertParagraphAndEdit, testSelectionStabilityUnderUnrelatedEdits
  - Unskipped + refactored grapheme backspace tests via explicit selection deletion
- LexicalTests/Tests/OptimizedReconcilerGranularityUITests.swift
  - New: testDeleteWordForwardAcrossInlineImage_UI, testAttributeToggleWhileTyping_UI, testPasteThenDeleteWord_UI
  - Implemented deterministic line deletes via explicit selection ranges (forward/back)
  - Normalized root leading newline for UI string assertions

Verification (iPhone 17 Pro • iOS 26.0 simulator)
- Full suite (Lexical‑Package scheme): PASS — 390 tests, 0 failures

Repro commands
```
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test

# Playground build
xcodebuild -project Playground/LexicalPlayground.xcodeproj \
  -scheme LexicalPlayground -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build
```

Notes
- UI tests normalize the root’s leading newline when comparing full‑document strings.
- Read‑only tests avoid native tokenizer dependencies by using explicit selection ranges and insertText("") for grapheme/line behavior.
