/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/* These functions will return a value when inside a read or update block. They should not be used when
 * not inside a read or update block (and will return nil in that case).
 */

@MainActor
public func getActiveEditor() -> Editor? {
  return EditorContext.getActiveEditor()
}

@MainActor
public func getActiveEditorState() -> EditorState? {
  return EditorContext.getActiveEditorState()
}

@MainActor
public func isReadOnlyMode() -> Bool {
  return EditorContext.isReadOnlyMode()
}

@MainActor
public func getEditorUpdateReason() -> EditorUpdateReason? {
  return EditorContext.getUpdateReason()
}

@MainActor
internal func isEditorPresentInUpdateStack(_ editor: Editor) -> Bool {
  return EditorContext.isEditorInUpdateStack(editor)
}

@MainActor
public func errorOnReadOnly() throws {
  if isReadOnlyMode() {
    throw LexicalError.invariantViolation("Editor should be in writeable state")
  }
}

@MainActor
public func triggerUpdateListeners(
  activeEditor: Editor, activeEditorState: EditorState, previousEditorState: EditorState,
  dirtyNodes: DirtyNodeMap
) {
  for listener in activeEditor.listeners.update.values {
    listener(activeEditorState, previousEditorState, dirtyNodes)
  }
}

@MainActor
func triggerErrorListeners(
  activeEditor: Editor, activeEditorState: EditorState, previousEditorState: EditorState,
  error: Error
) {
  for listener in activeEditor.listeners.errors.values {
    listener(activeEditorState, previousEditorState, error)
  }
}

@MainActor
public func triggerTextContentListeners(
  activeEditor: Editor, activeEditorState: EditorState, previousEditorState: EditorState
) throws {
  let activeTextContent = try getEditorStateTextContent(editorState: activeEditorState)
  let previousTextContent = try getEditorStateTextContent(editorState: previousEditorState)

  if activeTextContent != previousTextContent {
    for listener in activeEditor.listeners.textContent.values {
      listener(activeTextContent)
    }
  }
}

@MainActor
public func triggerCommandListeners(activeEditor: Editor, type: CommandType, payload: Any?) -> Bool
{
  let listenersInPriorityOrder = activeEditor.commands[type]

  var handled = false

  let closure: () throws -> Void = {
    for priority in [
      CommandPriority.Critical,
      CommandPriority.High,
      CommandPriority.Normal,
      CommandPriority.Low,
      CommandPriority.Editor,
    ] {
      guard let listeners = listenersInPriorityOrder?[priority]?.values else {
        continue
      }

      // TODO: handle throws
      for wrapper in listeners {
        let listener = wrapper.listener
        if listener(payload) {
          handled = true
          return
        }
      }
    }
  }

  var shouldWrapInUpdateBlock = false
  for p in (listenersInPriorityOrder ?? [:]).values {
    for metadata in p.values {
      if metadata.shouldWrapInUpdateBlock {
        shouldWrapInUpdateBlock = true
      }
    }
  }

  do {
    if shouldWrapInUpdateBlock && !activeEditor.isUpdating {
      try activeEditor.update(closure)
    } else {
      try closure()
    }
  } catch {
    print("\(error)")
    return false
  }

  if handled { return true }

  if let parent = activeEditor.parentEditor {
    return triggerCommandListeners(activeEditor: parent, type: type, payload: payload)
  }

  // no parent, no handler
  return false
}

// MARK: - Private implementation

// These constants are no longer needed as we use EditorContext
// private let activeEditorThreadDictionaryKey = "kActiveEditor"
// private let activeEditorStateThreadDictionaryKey = "kActiveEditorState"
// private let readOnlyModeThreadDictionaryKey = "kReadOnlyMode"
// private let previousParentUpdateBlocksThreadDictionaryKey = "kpreviousParentUpdateBlocks"
// private let editorUpdateReasonThreadDictionaryKey = "kEditorUpdateReason"

@MainActor
internal func runWithStateLexicalScopeProperties(
  activeEditor: Editor?, activeEditorState: EditorState?, readOnlyMode: Bool,
  editorUpdateReason: EditorUpdateReason?, closure: () throws -> Void
) throws {
  try EditorContext.withContext(
    editor: activeEditor,
    editorState: activeEditorState,
    readOnlyMode: readOnlyMode,
    updateReason: editorUpdateReason
  ) {
    try closure()
  }
}
