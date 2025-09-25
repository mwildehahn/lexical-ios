/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// This function is analagous to the parts of onBeforeInput() where inputType == 'insertText'.
// However, on iOS, we are assuming that `shouldPreventDefaultAndInsertText()` has already been checked
// before calling onInsertTextFromUITextView().

@MainActor
internal func onInsertTextFromUITextView(
  text: String, editor: Editor,
  updateMode: UpdateBehaviourModificationMode = UpdateBehaviourModificationMode()
) throws {
  try editor.updateWithCustomBehaviour(mode: updateMode, reason: .update) {
    guard let selection = try getSelection() else {
      editor.log(.UITextView, .error, "Expected a selection here")
      return
    }

    // Ensure the model selection is in sync with the UITextView's native selection
    // right before we mutate the tree. This avoids edge cases where a previous
    // numeric→Point round‑trip produced an off‑by‑one at text boundaries and
    // ensures operations like insertParagraph/delete apply at the caret the
    // user currently sees.
    if editor.featureFlags.optimizedReconciler, let rangeSelection = selection as? RangeSelection {
      let nativeSel = editor.getNativeSelection()
      try rangeSelection.applyNativeSelection(nativeSel)
    }

    if editor.featureFlags.diagnostics.verboseLogs {
      let ns = editor.getNativeSelection()
      let loc = ns.range?.location ?? -1
      let len = ns.range?.length ?? -1
      print("🔥 INPUT onInsertText: text='\(text.replacingOccurrences(of: "\n", with: "\\n"))' native=[\(loc),\(len)]")
    }

    if let markedTextOperation = updateMode.markedTextOperation,
      markedTextOperation.createMarkedText == true,
      let rangeSelection = selection as? RangeSelection
    {
      // Here we special case STARTING or UPDATING a marked text operation.
      try rangeSelection.applySelectionRange(
        markedTextOperation.selectionRangeToReplace, affinity: .forward)
    } else if let markedRange = editor.getNativeSelection().markedRange,
      let rangeSelection = selection as? RangeSelection
    {
      // Here we special case ENDING a marked text operation by replacing all the marked text with the incoming text.
      // This is usually used by hardware keyboards e.g. when typing e-acute. Software keyboards such as Japanese
      // do not seem to use this way of ending marked text.
      try rangeSelection.applySelectionRange(markedRange, affinity: .forward)
    }

    // (Removed) caret coercion guardrail: keep selection derived solely from applyNativeSelection

    if text == "\n" || text == "\u{2029}" {
      try selection.insertParagraph()

      if let updatedSelection = try getSelection(),
        let selectedNode = try updatedSelection.getNodes().first
      {
        editor.frontend?.resetTypingAttributes(for: selectedNode)
      }
    } else if text == "\u{2028}" {
      try selection.insertLineBreak(selectStart: false)
    } else {
      try selection.insertText(text)
    }
  }
}

@MainActor
internal func onInsertLineBreakFromUITextView(editor: Editor) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  try selection.insertLineBreak(selectStart: false)
}

@MainActor
internal func onInsertParagraphFromUITextView(editor: Editor) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  try selection.insertParagraph()
}

@MainActor
internal func onRemoveTextFromUITextView(editor: Editor) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  try selection.removeText()

  editor.frontend?.showPlaceholderText()
}

@MainActor
internal func onDeleteBackwardsFromUITextView(editor: Editor) throws {
  guard let editor = getActiveEditor(), let selection = try getSelection() else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  if editor.featureFlags.diagnostics.verboseLogs {
    let t = editor.textStorage?.string ?? "<nil>"
    print("🔥 DEL EVT: before='\(t.replacingOccurrences(of: "\n", with: "\\n"))' sel=\(editor.getNativeSelection().range?.debugDescription ?? "nil")")
  }
  // Optimized-only deterministic boundary handling:
  // If caret is logically at the start of a paragraph (element offset 0, or
  // text offset 0 inside that paragraph), merge with previous paragraph by
  // collapsing at start. This avoids relying on native backward-extend mapping
  // which can land on the previous character in tricky tie-break cases.
  if editor.featureFlags.optimizedReconciler, let rs = selection as? RangeSelection, rs.isCollapsed() {
    let a = rs.anchor
    // Find the paragraph element to consider
    var elem: ElementNode?
    if a.type == .element, let e = try? a.getNode() as? ElementNode { elem = e }
    else if a.type == .text, let n = try? a.getNode(), let p = try? n.getParentOrThrow() as ElementNode { elem = p }
    if let e = elem, a.offset == 0, e.getPreviousSibling() != nil {
      try editor.update {
        let prev = e.getPreviousSibling() as? ElementNode
        if try e.collapseAtStart(selection: rs) {
          if let p = prev { internallyMarkNodeAsDirty(node: p, cause: .userInitiated) }
          if let p = prev { editor.pendingPostambleCleanup.insert(p.getKey()) }
          // Directly remove the trailing newline in TextStorage at survivor's lastChildEnd
          if let p = prev, let fe = editor.frontend, let ts = editor.textStorage {
            // Compute deletion index robustly: prefer the character just before the caret
            // if it is a newline; otherwise fall back to survivor's lastChildEnd.
            var idxToDelete: Int? = nil
            // Derive numeric from model selection (rs) to avoid stale UI selection.
            if let modelNS = try? createNativeSelection(from: rs, editor: editor),
               let ns = modelNS.range, ns.length == 0, ns.location > 0 {
              let idxLeft = ns.location - 1
              if idxLeft >= 0 && idxLeft < ts.length {
                let ch = (ts.string as NSString).substring(with: NSRange(location: idxLeft, length: 1))
                if ch == "\n" { idxToDelete = idxLeft }
              }
            }
            if idxToDelete == nil, let item = editor.rangeCache[p.getKey()] {
              let loc = item.locationFromFenwick(using: editor.fenwickTree)
                + item.preambleLength + item.childrenLength + item.textLength
              let idx = max(0, min(loc, max(0, ts.length - 1)))
              if idx < ts.length {
                let ch = (ts.string as NSString).substring(with: NSRange(location: idx, length: 1))
                if ch == "\n" { idxToDelete = idx }
              }
            }
            if let delIdx = idxToDelete {
              ts.beginEditing()
              ts.replaceCharacters(in: NSRange(location: delIdx, length: 1), with: "")
              ts.endEditing()
              // Update cache postamble and ancestor children lengths conservatively
              var prevItem = editor.rangeCache[p.getKey()] ?? RangeCacheItem()
              if prevItem.postambleLength > 0 { prevItem.postambleLength = max(0, prevItem.postambleLength - 1) }
              editor.rangeCache[p.getKey()] = prevItem
              var parentKey = p.getParent()?.getKey()
              while let pk = parentKey {
                if var it = editor.rangeCache[pk] { it.childrenLength = max(0, it.childrenLength - 1); editor.rangeCache[pk] = it }
                parentKey = getNodeByKey(key: pk)?.parent
              }
            } else if ts.length > 0 {
              // Final safe fallback: if last character in the string is a newline, remove it.
              let lastIdx = ts.length - 1
              let ch = (ts.string as NSString).substring(with: NSRange(location: lastIdx, length: 1))
              if ch == "\n" {
                ts.beginEditing(); ts.replaceCharacters(in: NSRange(location: lastIdx, length: 1), with: ""); ts.endEditing()
                // Update cache conservatively like above
                var prevItem = editor.rangeCache[p.getKey()] ?? RangeCacheItem()
                if prevItem.postambleLength > 0 { prevItem.postambleLength = max(0, prevItem.postambleLength - 1) }
                editor.rangeCache[p.getKey()] = prevItem
                var parentKey = p.getParent()?.getKey()
                while let pk = parentKey {
                  if var it = editor.rangeCache[pk] { it.childrenLength = max(0, it.childrenLength - 1); editor.rangeCache[pk] = it }
                  parentKey = getNodeByKey(key: pk)?.parent
                }
              }
            }
            try fe.updateNativeSelection(from: rs)
          } else {
            if let fe = editor.frontend { try fe.updateNativeSelection(from: rs) }
          }
        }
      }
      if editor.featureFlags.diagnostics.verboseLogs {
        let t2 = editor.textStorage?.string ?? "<nil>"
        print("🔥 DEL EVT: collapsed-at-start; after='\(t2.replacingOccurrences(of: "\n", with: "\\n"))'")
      }
      return
    }
  }
  try selection.deleteCharacter(isBackwards: true)

  editor.frontend?.showPlaceholderText()
  if editor.featureFlags.diagnostics.verboseLogs {
    let t = editor.textStorage?.string ?? "<nil>"
    print("🔥 DEL EVT: after='\(t.replacingOccurrences(of: "\n", with: "\\n"))' sel=\(editor.getNativeSelection().range?.debugDescription ?? "nil")")
  }
}

@MainActor
internal func onDeleteWordFromUITextView(editor: Editor) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }

  try selection.deleteWord(isBackwards: true)

  editor.frontend?.showPlaceholderText()
}

@MainActor
internal func onDeleteLineFromUITextView(editor: Editor) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }

  try selection.deleteLine(isBackwards: true)

  editor.frontend?.showPlaceholderText()
}

@MainActor
internal func onFormatTextFromUITextView(editor: Editor, type: TextFormatType) throws {
  try updateTextFormat(type: type, editor: editor)
}

@MainActor
internal func onCopyFromUITextView(editor: Editor, pasteboard: UIPasteboard) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  try setPasteboard(selection: selection, pasteboard: pasteboard)
}

@MainActor
internal func onCutFromUITextView(editor: Editor, pasteboard: UIPasteboard) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  try setPasteboard(selection: selection, pasteboard: pasteboard)
  try selection.removeText()

  editor.frontend?.showPlaceholderText()
}

@MainActor
internal func onPasteFromUITextView(editor: Editor, pasteboard: UIPasteboard) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() as? RangeSelection else {
    throw LexicalError.invariantViolation("No editor or selection")
  }

  try insertDataTransferForRichText(selection: selection, pasteboard: pasteboard)

  editor.frontend?.showPlaceholderText()
}

@MainActor
public func shouldInsertTextAfterOrBeforeTextNode(selection: RangeSelection, node: TextNode) -> Bool
{
  var shouldInsertTextBefore = false
  var shouldInsertTextAfter = false

  if node.isSegmented() {
    return true
  }

  if !selection.isCollapsed() {
    return true
  }

  let offset = selection.anchor.offset

  shouldInsertTextBefore = offset == 0 && checkIfTokenOrCanTextBeInserted(node: node)

  shouldInsertTextAfter =
    node.getTextContentSize() == offset && checkIfTokenOrCanTextBeInserted(node: node)

  return shouldInsertTextBefore || shouldInsertTextAfter
}

@MainActor
func checkIfTokenOrCanTextBeInserted(node: TextNode) -> Bool {
  let isToken = node.isToken()
  let parent = node.getParent()

  if let parent {
    return !parent.canInsertTextBefore() || !node.canInsertTextBefore() || isToken
  }

  return !node.canInsertTextBefore() || isToken
}

// triggered by selection change event from the UITextView
@MainActor
internal func onSelectionChange(editor: Editor) {
  // Note: we have to detect selection changes here even if an update is in progress, otherwise marked text breaks!
  do {
    try editor.updateWithCustomBehaviour(
      mode: UpdateBehaviourModificationMode(
        suppressReconcilingSelection: true, suppressSanityCheck: true), reason: .update
    ) {
      let nativeSelection = editor.getNativeSelection()
      guard let editorState = getActiveEditorState() else {
        return
      }
      if !(try getSelection() is RangeSelection) {
        guard let newSelection = RangeSelection(nativeSelection: nativeSelection) else {
          return
        }
        editorState.selection = newSelection
      }

      guard let lexicalSelection = try getSelection() as? RangeSelection else {
        return  // we should have a range selection by now, so this is unexpected
      }

      try lexicalSelection.applyNativeSelection(nativeSelection)

      switch lexicalSelection.anchor.type {
      case .text:
        guard let anchorNode = try lexicalSelection.anchor.getNode() as? TextNode else { break }
        lexicalSelection.format = anchorNode.getFormat()
      case .element:
        lexicalSelection.format = TextFormat()
      default:
        break
      }
      editor.dispatchCommand(type: .selectionChange, payload: nil)
    }
  } catch {
    // log error "change selection: failed to update lexical selection"
  }
}

@MainActor
internal func handleIndentAndOutdent(
  insertTab: (Node) -> Void, indentOrOutdent: (ElementNode) -> Void
) throws {
  guard getActiveEditor() != nil, let selection = try getSelection() else {
    throw LexicalError.invariantViolation("No editor or selection")
  }
  var alreadyHandled: Set<NodeKey> = Set()
  let nodes = try selection.getNodes()

  for node in nodes {
    let key = node.getKey()
    if alreadyHandled.contains(key) { continue }
    let parentBlock = try getNearestBlockElementAncestorOrThrow(startNode: node)
    let parentKey = parentBlock.getKey()
    if parentBlock.canInsertTab() {
      insertTab(parentBlock)
      alreadyHandled.insert(parentKey)
    } else if parentBlock.canIndent() && !alreadyHandled.contains(parentKey) {
      alreadyHandled.insert(parentKey)
      indentOrOutdent(parentBlock)
    }
  }
}

@MainActor
public func registerRichText(editor: Editor) {

  _ = editor.registerCommand(
    type: .insertLineBreak,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onInsertLineBreakFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .deleteCharacter,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onDeleteBackwardsFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .deleteWord,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onDeleteWordFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .deleteLine,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onDeleteLineFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .insertText,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        guard let text = payload as? String else {
          editor.log(.TextView, .warning, "insertText missing payload")
          return false
        }

        try onInsertTextFromUITextView(text: text, editor: editor)
        return true
      } catch {
        editor.log(.TextView, .error, "Exception in insertText; \(String(describing: error))")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .insertParagraph,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onInsertParagraphFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .removeText,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try onRemoveTextFromUITextView(editor: editor)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .formatText,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        guard let text = payload as? TextFormatType else { return false }

        try onFormatTextFromUITextView(editor: editor, type: text)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .copy,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        guard let text = payload as? UIPasteboard else { return false }

        try onCopyFromUITextView(editor: editor, pasteboard: text)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .cut,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        guard let text = payload as? UIPasteboard else { return false }

        try onCutFromUITextView(editor: editor, pasteboard: text)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .paste,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        guard let text = payload as? UIPasteboard else { return false }

        try onPasteFromUITextView(editor: editor, pasteboard: text)
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .indentContent,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try handleIndentAndOutdent(
          insertTab: { node in
            editor.dispatchCommand(type: .insertText, payload: "\t")
          },
          indentOrOutdent: { elementNode in
            let indent = elementNode.getIndent()
            if indent != 10 {
              _ = try? elementNode.setIndent(indent + 1)
            }
          })
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(
    type: .outdentContent,
    listener: { [weak editor] payload in
      guard let editor else { return false }
      do {
        try handleIndentAndOutdent(
          insertTab: { node in
            if let node = node as? TextNode {
              let textContent = node.getTextContent()
              if let character = textContent.last {
                if character == "\t" {
                  editor.dispatchCommand(type: .deleteCharacter)
                }
              }
            }

            editor.dispatchCommand(type: .insertText, payload: "\t")
          },
          indentOrOutdent: { elementNode in
            let indent = elementNode.getIndent()
            if indent != 0 {
              _ = try? elementNode.setIndent(indent - 1)
            }
          })
        return true
      } catch {
        print("\(error)")
      }
      return true
    })

  _ = editor.registerCommand(type: .updatePlaceholderVisibility) { [weak editor] payload in
    editor?.frontend?.showPlaceholderText()
    return true
  }
}
