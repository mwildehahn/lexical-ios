/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import Foundation
import AppKit

@MainActor
class ResponderForNodeSelection: NSResponder {

  private weak var editor: Editor?
  private weak var textStorage: TextStorage?
  private weak var textView: NSResponder?

  init(editor: Editor, textStorage: TextStorage, nextResponder: NSResponder) {
    self.editor = editor
    self.textStorage = textStorage
    self.textView = nextResponder
    super.init()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Text Input

  func insertText(_ text: String) {
    guard let editor, let textStorage else {
      return
    }
    textStorage.mode = TextStorageEditingMode.controllerMode
    editor.dispatchCommand(type: .insertText, payload: text)
    textStorage.mode = TextStorageEditingMode.none
  }

  func deleteBackward() {
    editor?.dispatchCommand(type: .deleteCharacter, payload: true)
  }

  // MARK: - Responder Chain

  override var acceptsFirstResponder: Bool {
    return true
  }

  override var nextResponder: NSResponder? {
    get { textView }
    set { /* ignore */ }
  }

  var isFirstResponder: Bool {
    // Check if we're the current first responder in the window
    return NSApp.keyWindow?.firstResponder == self
  }
}
#endif
