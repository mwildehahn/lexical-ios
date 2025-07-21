/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// MainActor-isolated context manager for managing editor state during updates
/// Replaces the thread dictionary pattern for Swift 6 compatibility
@MainActor
final class EditorContext {
  private static var current: ContextStack?

  class ContextStack {
    let editor: Editor?
    let editorState: EditorState?
    let readOnlyMode: Bool
    let updateReason: EditorUpdateReason?
    let previous: ContextStack?
    let updateStack: [Editor]

    init(
      editor: Editor?, editorState: EditorState?, readOnlyMode: Bool,
      updateReason: EditorUpdateReason?, previous: ContextStack?, updateStack: [Editor]
    ) {
      self.editor = editor
      self.editorState = editorState
      self.readOnlyMode = readOnlyMode
      self.updateReason = updateReason
      self.previous = previous
      self.updateStack = updateStack
    }
  }

  static func withContext<T>(
    editor: Editor?,
    editorState: EditorState?,
    readOnlyMode: Bool,
    updateReason: EditorUpdateReason?,
    operation: () throws -> T
  ) rethrows -> T {
    let previous = current
    let updateStack = previous?.updateStack ?? []
    let newStack = (editor != nil && !readOnlyMode) ? updateStack + [editor!] : updateStack

    current = ContextStack(
      editor: editor,
      editorState: editorState,
      readOnlyMode: readOnlyMode,
      updateReason: updateReason,
      previous: previous,
      updateStack: newStack
    )

    defer { current = previous }
    return try operation()
  }

  static func getActiveEditor() -> Editor? {
    current?.editor
  }

  static func getActiveEditorState() -> EditorState? {
    current?.editorState
  }

  static func isReadOnlyMode() -> Bool {
    current?.readOnlyMode ?? true
  }

  static func getUpdateReason() -> EditorUpdateReason? {
    current?.updateReason
  }

  static func isEditorInUpdateStack(_ editor: Editor) -> Bool {
    current?.updateStack.contains(editor) ?? false
  }
}
