# Manual Testing Guide - macOS App

This guide covers manual testing procedures for features that require interactive testing.

## Prerequisites

Build and run the macOS Playground app:
```bash
xcodebuild -project Playground/LexicalPlayground.xcodeproj \
  -scheme LexicalPlaygroundMac -destination 'platform=macOS' build

open /Users/vedranburojevic/Library/Developer/Xcode/DerivedData/LexicalPlayground-*/Build/Products/Debug/LexicalPlaygroundMac.app
```

Enable verbose logging to see detailed operation logs:
- **Features Menu** → **Verbose Logging** (toggle on)

---

## 1. IME (Input Method Editor) Testing

### Overview
IME support allows input of non-Latin characters (Japanese, Chinese, Korean, etc.) using composition sequences.

### Implementation Files
- **macOS**: `Lexical/TextView/TextViewMacOS.swift`
  - `setMarkedText(_:selectedRange:replacementRange:)` - Handles composition
  - `unmarkText()` - Commits composition
  - `hasMarkedText()` - Returns marked text state
  - `markedRange()` - Returns composition range

### Test Scenarios

#### 1.1 Japanese Hiragana Input
**Setup**: Enable Japanese input method in System Settings
1. Open macOS Playground app
2. Click in the editor to focus
3. Switch to Japanese input (⌘+Space or Control+Space)
4. Type: `konnichiwa` (こんにちは)

**Expected Behavior**:
- As you type, underlined composition text appears
- Press Space to see conversion candidates
- Press Enter to commit the text
- Logs should show:
  ```
  🔥 MARKED: setMarkedText range=NSRange(location: X, length: Y)
  🔥 TYPE: insertText text='こんにちは' len=5 at anchor=X:Y
  ```

**Verify**:
- [ ] Composition text appears with underline during typing
- [ ] Conversion works correctly
- [ ] Final text is committed without underline
- [ ] Cursor position is correct after commit

#### 1.2 Chinese Pinyin Input
**Setup**: Enable Chinese (Simplified Pinyin) input method
1. Switch to Chinese Pinyin input
2. Type: `nihao` (你好)
3. Select characters from candidate list
4. Press Enter to commit

**Expected Behavior**:
- Pinyin appears as composition text
- Candidate window shows character options
- Selected characters replace composition
- Logs show marked text and final insertion

**Verify**:
- [ ] Candidate window appears
- [ ] Character selection works
- [ ] Text commits correctly
- [ ] No duplicate characters

#### 1.3 Emoji Input
**Setup**: Use native emoji picker
1. Press ⌘+Control+Space to open emoji picker
2. Select an emoji
3. Click to insert

**Expected Behavior**:
- Emoji inserts at cursor position
- Logs show: `🔥 TYPE: insertText text='😀' len=2`
- Cursor moves after emoji

**Verify**:
- [ ] Emoji displays correctly
- [ ] Cursor position correct
- [ ] Can type after emoji
- [ ] Emoji counted correctly in text length

#### 1.4 Multiple Composition Cycles
**Test**: Start and cancel composition multiple times
1. Type some composition text
2. Press Escape to cancel
3. Repeat 3-4 times
4. Then complete a composition normally

**Expected Behavior**:
- Each Escape clears composition
- Logs show: `🔥 MARKED: unmarkText`
- No ghost characters remain
- Normal typing still works

**Verify**:
- [ ] Escape properly cancels composition
- [ ] No leftover marked text
- [ ] Editor state remains consistent
- [ ] Subsequent compositions work

#### 1.5 Composition with Selection
**Test**: Replace selected text with IME input
1. Type some text: "Hello World"
2. Select "World"
3. Switch to Japanese input
4. Type: `sekai` (世界)
5. Commit

**Expected Behavior**:
- Selected text replaced by composition
- Logs show deleteCharacter then insertText
- Final text: "Hello 世界"

**Verify**:
- [ ] Selection properly replaced
- [ ] No duplicate text
- [ ] Cursor at end of inserted text

---

## 2. Decorator Overlay Testing

### Overview
Decorator overlays allow interactive views (images, embeds) to be positioned over the text editor.

### Implementation Files
- **macOS**: `Lexical/LexicalView/LexicalOverlayViewMacOS.swift`
  - `handleClick(_:)` - Intercepts clicks on decorators
  - `hitTest(_:)` - Routes events to decorators

### Test Scenarios

#### 2.1 Inline Image Interaction
**Setup**: Insert an inline image
1. Open macOS Playground
2. Create inline image (via plugin or code)
3. Click on the image

**Expected Behavior**:
- Image view is positioned correctly in text flow
- Clicking image creates NodeSelection
- Logs show:
  ```
  🔥 INSERT-NODE: decorator inserted key=X into target=Y
  ```

**Verify**:
- [ ] Image renders at correct position
- [ ] Image updates position when text above changes
- [ ] Click on image selects it (blue border)
- [ ] Can type before/after image

#### 2.2 Multiple Decorators
**Test**: Multiple images in same paragraph
1. Insert 3 images in a single line
2. Type text between them
3. Click each image

**Expected Behavior**:
- All images position correctly
- Overlay updates for all decorators
- Each click selects correct image
- Text reflow works around images

**Verify**:
- [ ] All decorators visible
- [ ] Positions update on text changes
- [ ] Click targets correct decorator
- [ ] No overlap or z-order issues

#### 2.3 Decorator Size Changes
**Test**: Decorator resizing
1. Insert an image
2. Change image size (if plugin supports)
3. Verify text reflow

**Expected Behavior**:
- Text reflows around new size
- Overlay position updates
- Cursor positions recalculate
- Logs show reconciler updates

**Verify**:
- [ ] Size change reflected immediately
- [ ] Text wrapping updates
- [ ] Selection still works
- [ ] No visual glitches

#### 2.4 Decorator with Formatting
**Test**: Bold/italic text near decorators
1. Type "Hello "
2. Insert image
3. Type " World"
4. Select "Hello " and make it bold
5. Select " World" and make it italic

**Expected Behavior**:
- Formatting applies correctly
- Image stays in position
- Overlay tracks correctly
- No formatting leaks to/from decorator

**Verify**:
- [ ] Formatting independent of decorator
- [ ] Decorator position stable
- [ ] Can format text on both sides
- [ ] Delete backwards works correctly

---

## 3. Keyboard Shortcuts Testing

### Test All Shortcuts
Run through each shortcut to verify functionality:

**Clipboard**:
- [ ] ⌘C - Copy selected text
- [ ] ⌘X - Cut selected text
- [ ] ⌘V - Paste from clipboard

**Formatting**:
- [ ] ⌘B - Toggle bold
- [ ] ⌘I - Toggle italic
- [ ] ⌘U - Toggle underline
- [ ] ⌘⇧X - Toggle strikethrough

**Selection**:
- [ ] ⌘A - Select all

**Navigation** (verify logs with verbose logging on):
- [ ] Arrow keys move cursor
- [ ] Delete/Backspace remove characters
- [ ] Return inserts paragraph
- [ ] Shift+Return inserts line break

---

## 4. Complex Scenarios

### 4.1 Mixed Input Methods
1. Type English text
2. Switch to Japanese, type hiragana
3. Switch back to English
4. Paste some text
5. Insert emoji
6. Format parts with bold/italic

**Expected**: All input methods work seamlessly together

### 4.2 Undo/Redo with IME
1. Enable EditorHistoryPlugin
2. Type Japanese text with composition
3. Press ⌘Z to undo
4. Press ⌘⇧Z to redo

**Expected**: Undo/redo respects composition boundaries

### 4.3 Rapid IME + Decorators
1. Type some text with IME
2. Insert image
3. Continue typing with IME
4. Delete backwards through image

**Expected**: All operations smooth, no crashes

---

## 5. Performance Testing

### 5.1 Long IME Sessions
**Test**: Extended Japanese input (100+ characters)
- Check for lag during composition
- Monitor memory usage
- Verify smooth scrolling

### 5.2 Many Decorators
**Test**: 20+ images in document
- Check layout performance
- Verify overlay rendering speed
- Test scroll performance

---

## Logging Guide

With verbose logging enabled, look for these patterns:

### Successful IME:
```
🔥 MARKED: setMarkedText range=NSRange(location: 0, length: 4)
🔥 MARKED: unmarkText
🔥 TYPE: insertText text='こんにちは' len=5 at anchor=0:0 focus=0:0 collapsed=true
🔥 OPTIMIZED RECONCILER: delta application success
```

### Successful Decorator Interaction:
```
🔥 INSERT-NODE: decorator inserted key=2 into target=1
🔥 OPTIMIZED RECONCILER: decorator position updated key=2 frame=(10, 20, 100, 100)
```

### Issues to Watch For:
- ❌ Duplicate insertText calls
- ❌ Marked text not cleared after commit
- ❌ Decorator position not updating on text changes
- ❌ Crashes during composition
- ❌ Selection jumping unexpectedly

---

## Reporting Issues

When filing issues, include:
1. Steps to reproduce
2. Expected vs actual behavior
3. Console logs (with verbose logging on)
4. Input method used (if IME issue)
5. macOS version
6. Screenshot or screen recording if applicable

---

## Quick Smoke Test Checklist

Run this 5-minute test before major releases:

- [ ] Type English text
- [ ] Type Japanese/Chinese text (if available)
- [ ] Insert emoji
- [ ] Apply formatting (bold, italic)
- [ ] Copy/paste text
- [ ] Insert image (if plugin available)
- [ ] Click on image to select
- [ ] Undo/redo
- [ ] Select all (⌘A)
- [ ] Save/export content

If all pass ✅, core functionality is working correctly.
