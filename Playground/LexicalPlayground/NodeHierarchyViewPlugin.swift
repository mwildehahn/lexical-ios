/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import LexicalListPlugin
import UIKit

// MARK: - Debug Action Log Entry

struct DebugAction: CustomStringConvertible {
  let timestamp: Date
  let action: String
  let details: String

  var description: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return "[\(formatter.string(from: timestamp))] \(action): \(details)"
  }
}

public class NodeHierarchyViewPlugin: Plugin {
  private var containerView: UIView!
  private var segmentedControl: UISegmentedControl!
  private var _hierarchyView: UITextView!
  private var _actionLogView: UITextView!
  private var selectionLabel: UILabel!
  private var buttonStack: UIStackView!

  weak var editor: Editor?

  // Debug state
  private var actionLog: [DebugAction] = []
  private var commandListenerRemovers: [() -> Void] = []

  init() {
    setupViews()
  }

  private func setupViews() {
    containerView = UIView()
    containerView.backgroundColor = .black

    // Segmented control for switching between views
    segmentedControl = UISegmentedControl(items: ["Hierarchy", "Action Log"])
    segmentedControl.selectedSegmentIndex = 0
    segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    segmentedControl.translatesAutoresizingMaskIntoConstraints = false

    // Selection label at top
    selectionLabel = UILabel()
    selectionLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    selectionLabel.textColor = .systemGreen
    selectionLabel.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
    selectionLabel.numberOfLines = 3
    selectionLabel.text = "Selection: --"
    selectionLabel.translatesAutoresizingMaskIntoConstraints = false

    // Hierarchy view
    _hierarchyView = UITextView()
    _hierarchyView.backgroundColor = .black
    _hierarchyView.textColor = .white
    _hierarchyView.isEditable = false
    _hierarchyView.isUserInteractionEnabled = true
    _hierarchyView.isScrollEnabled = true
    _hierarchyView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    _hierarchyView.showsVerticalScrollIndicator = true
    _hierarchyView.translatesAutoresizingMaskIntoConstraints = false

    // Action log view
    _actionLogView = UITextView()
    _actionLogView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
    _actionLogView.textColor = .systemGray
    _actionLogView.isEditable = false
    _actionLogView.isUserInteractionEnabled = true
    _actionLogView.isScrollEnabled = true
    _actionLogView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    _actionLogView.showsVerticalScrollIndicator = true
    _actionLogView.translatesAutoresizingMaskIntoConstraints = false
    _actionLogView.isHidden = true

    // Buttons
    let copyStateButton = UIButton(type: .system)
    copyStateButton.setTitle("Copy State", for: .normal)
    copyStateButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
    copyStateButton.addTarget(self, action: #selector(copyDebugState), for: .touchUpInside)

    let clearButton = UIButton(type: .system)
    clearButton.setTitle("Clear Log", for: .normal)
    clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
    clearButton.addTarget(self, action: #selector(clearActionLog), for: .touchUpInside)

    buttonStack = UIStackView(arrangedSubviews: [copyStateButton, clearButton])
    buttonStack.axis = .horizontal
    buttonStack.spacing = 16
    buttonStack.distribution = .fillEqually
    buttonStack.translatesAutoresizingMaskIntoConstraints = false

    containerView.addSubview(segmentedControl)
    containerView.addSubview(selectionLabel)
    containerView.addSubview(_hierarchyView)
    containerView.addSubview(_actionLogView)
    containerView.addSubview(buttonStack)

    NSLayoutConstraint.activate([
      segmentedControl.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
      segmentedControl.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      segmentedControl.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

      selectionLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
      selectionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      selectionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

      _hierarchyView.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 4),
      _hierarchyView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      _hierarchyView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      _hierarchyView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -4),

      _actionLogView.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 4),
      _actionLogView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      _actionLogView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      _actionLogView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -4),

      buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      buttonStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
      buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
      buttonStack.heightAnchor.constraint(equalToConstant: 30)
    ])
  }

  @objc private func segmentChanged() {
    let showHierarchy = segmentedControl.selectedSegmentIndex == 0
    _hierarchyView.isHidden = !showHierarchy
    _actionLogView.isHidden = showHierarchy
  }

  // MARK: - Plugin API

  public func setUp(editor: Editor) {
    self.editor = editor

    _ = editor.registerUpdateListener { [weak self] activeEditorState, previousEditorState, dirtyNodes in
      if let self {
        self.updateHierarchyView(editorState: activeEditorState)
        self.updateSelectionDisplay()
      }
    }

    setupDebugLogging(editor: editor)
  }

  public func tearDown() {
    // Remove command listeners
    for remover in commandListenerRemovers {
      remover()
    }
    commandListenerRemovers.removeAll()
  }

  public var hierarchyView: UIView {
    get {
      containerView
    }
  }

  // MARK: - Debug Logging

  private func setupDebugLogging(editor: Editor) {
    let priority = CommandPriority.Critical

    // Log text insertion
    let insertTextRemover = editor.registerCommand(type: .insertText, listener: { [weak self] payload in
      if let text = payload as? String {
        let displayText = text.replacingOccurrences(of: "\n", with: "\\n")
        self?.logAction("insertText", details: "text=\"\(displayText)\"")
      }
      return false
    }, priority: priority)
    commandListenerRemovers.append(insertTextRemover)

    // Log paragraph insertion
    let insertParagraphRemover = editor.registerCommand(type: .insertParagraph, listener: { [weak self] _ in
      self?.logAction("insertParagraph", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(insertParagraphRemover)

    // Log line break insertion
    let insertLineBreakRemover = editor.registerCommand(type: .insertLineBreak, listener: { [weak self] _ in
      self?.logAction("insertLineBreak", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(insertLineBreakRemover)

    // Log delete character
    let deleteCharRemover = editor.registerCommand(type: .deleteCharacter, listener: { [weak self] payload in
      let isBackward = (payload as? Bool) ?? true
      self?.logAction("deleteCharacter", details: "backward=\(isBackward)")
      return false
    }, priority: priority)
    commandListenerRemovers.append(deleteCharRemover)

    // Log delete word
    let deleteWordRemover = editor.registerCommand(type: .deleteWord, listener: { [weak self] payload in
      let isBackward = (payload as? Bool) ?? true
      self?.logAction("deleteWord", details: "backward=\(isBackward)")
      return false
    }, priority: priority)
    commandListenerRemovers.append(deleteWordRemover)

    // Log format text
    let formatTextRemover = editor.registerCommand(type: .formatText, listener: { [weak self] payload in
      if let format = payload as? TextFormatType {
        self?.logAction("formatText", details: "format=\(format)")
      }
      return false
    }, priority: priority)
    commandListenerRemovers.append(formatTextRemover)

    // Log selection change
    let selectionChangeRemover = editor.registerCommand(type: .selectionChange, listener: { [weak self] _ in
      self?.updateSelectionDisplay()
      self?.logSelectionState()
      return false
    }, priority: priority)
    commandListenerRemovers.append(selectionChangeRemover)

    // Log undo/redo
    let undoRemover = editor.registerCommand(type: .undo, listener: { [weak self] _ in
      self?.logAction("undo", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(undoRemover)

    let redoRemover = editor.registerCommand(type: .redo, listener: { [weak self] _ in
      self?.logAction("redo", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(redoRemover)

    // Log list commands
    let bulletListRemover = editor.registerCommand(type: .insertUnorderedList, listener: { [weak self] _ in
      self?.logAction("insertUnorderedList", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(bulletListRemover)

    let numberedListRemover = editor.registerCommand(type: .insertOrderedList, listener: { [weak self] _ in
      self?.logAction("insertOrderedList", details: "")
      return false
    }, priority: priority)
    commandListenerRemovers.append(numberedListRemover)
  }

  private func logAction(_ action: String, details: String) {
    let entry = DebugAction(timestamp: Date(), action: action, details: details)
    actionLog.append(entry)
    // Keep log manageable
    if actionLog.count > 500 {
      actionLog.removeFirst(100)
    }
    updateActionLogView()
  }

  private func logSelectionState() {
    guard let editor else { return }
    var logDetails = ""

    try? editor.read {
      if let selection = try? getSelection() as? RangeSelection {
        let anchor = selection.anchor
        let focus = selection.focus
        logDetails = "anchor=(\(anchor.key),\(anchor.offset),\(anchor.type)) focus=(\(focus.key),\(focus.offset),\(focus.type))"
      } else {
        logDetails = "nil selection"
      }
    }

    logAction("selectionChange", details: logDetails)
  }

  private func updateSelectionDisplay() {
    guard let editor else { return }
    var selectionText = "Selection: "

    try? editor.read {
      if let selection = try? getSelection() as? RangeSelection {
        let anchor = selection.anchor
        let focus = selection.focus
        let collapsed = selection.isCollapsed()
        selectionText += "anchor=(\(anchor.key),\(anchor.offset)) focus=(\(focus.key),\(focus.offset)) collapsed=\(collapsed)"
      } else {
        selectionText += "nil"
      }
    }

    // Also get native selection if we can access it
    // Note: We don't have direct access to the text view here, so we just show Lexical selection
    selectionLabel.text = selectionText
  }

  private func updateActionLogView() {
    let recentActions = actionLog.suffix(100)
    let logText = recentActions.map { $0.description }.joined(separator: "\n")
    _actionLogView.text = logText

    // Scroll to bottom
    if !logText.isEmpty {
      let range = NSRange(location: logText.count - 1, length: 1)
      _actionLogView.scrollRangeToVisible(range)
    }
  }

  @objc private func copyDebugState() {
    guard let editor else { return }

    var debugOutput = "=== LEXICAL DEBUG STATE ===\n"
    debugOutput += "Timestamp: \(Date())\n\n"

    // Current selection
    debugOutput += "--- SELECTION ---\n"
    try? editor.read {
      if let selection = try? getSelection() as? RangeSelection {
        let anchor = selection.anchor
        let focus = selection.focus
        debugOutput += "Anchor: key=\"\(anchor.key)\", offset=\(anchor.offset), type=\(anchor.type)\n"
        debugOutput += "Focus: key=\"\(focus.key)\", offset=\(focus.offset), type=\(focus.type)\n"
        debugOutput += "isCollapsed: \(selection.isCollapsed())\n"
      } else {
        debugOutput += "No selection\n"
      }
    }

    // Editor state as JSON
    debugOutput += "\n--- EDITOR STATE JSON ---\n"
    do {
      let json = try editor.getEditorState().toJSON(outputFormatting: [.prettyPrinted, .sortedKeys])
      debugOutput += json
    } catch {
      debugOutput += "Error serializing state: \(error)\n"
    }

    // Action log
    debugOutput += "\n\n--- ACTION LOG (last 100) ---\n"
    let recentActions = actionLog.suffix(100)
    for action in recentActions {
      debugOutput += "\(action)\n"
    }

    // Copy to clipboard
    UIPasteboard.general.string = debugOutput

    // Flash feedback
    let originalColor = containerView.backgroundColor
    containerView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.containerView.backgroundColor = originalColor
    }
  }

  @objc private func clearActionLog() {
    actionLog.removeAll()
    _actionLogView.text = ""
    selectionLabel.text = "Selection: --"
  }

  // MARK: - Hierarchy Update

  private func updateHierarchyView(editorState: EditorState) {
    do {
      let hierarchyString = try getNodeHierarchy(editorState: editorState)
      let selectionString = try getSelectionData(editorState: editorState)
      _hierarchyView.text = "\(hierarchyString)\n\n\(selectionString)"
    } catch {
      print("Error updating node hierarchy.")
    }
  }
}
