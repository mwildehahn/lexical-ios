/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class SelectableDecoratorView: PlatformView {
  public weak var editor: Editor?
  public var nodeKey: NodeKey?

  public var contentView: PlatformView? {
    didSet {
      if let oldValue, oldValue != contentView {
        oldValue.removeFromSuperview()
      }
      if let contentView {
        addSubview(contentView)
        contentView.frame = self.bounds
        #if canImport(UIKit)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #elseif canImport(AppKit)
        contentView.autoresizingMask = [.width, .height]
        #endif
      }
    }
  }

  var updateListener: Editor.RemovalHandler?
  #if canImport(UIKit)
  var gestureRecognizer: UITapGestureRecognizer?
  #elseif canImport(AppKit)
  var gestureRecognizer: NSClickGestureRecognizer?
  #endif
  var borderView: PlatformView = PlatformView(frame: .zero)

  internal func setUpListeners() throws {
    guard let editor, let nodeKey, gestureRecognizer == nil else {
      throw LexicalError.invariantViolation("expected editor and node key by now")
    }
    updateListener = editor.registerUpdateListener { [weak self] activeEditorState, previousEditorState, dirtyNodes in
      try? activeEditorState.read {
        let selection = try getSelection()
        if let selection = selection as? NodeSelection {
          let nodes = try selection.getNodes().map { node in
            node.getKey()
          }
          self?.setDrawsSelectionBorder(nodes.contains(nodeKey))
        } else {
          self?.setDrawsSelectionBorder(false)
        }
      }
    }

    #if canImport(UIKit)
    let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapReceived(sender:)))
    self.addGestureRecognizer(gestureRecognizer)
    self.gestureRecognizer = gestureRecognizer
    #elseif canImport(AppKit)
    let gestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(tapReceived(sender:)))
    self.addGestureRecognizer(gestureRecognizer)
    self.gestureRecognizer = gestureRecognizer
    #endif

    addSubview(borderView)
    borderView.frame = self.bounds
    #if canImport(UIKit)
    borderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    borderView.isUserInteractionEnabled = false
    borderView.layer.borderColor = PlatformColor.red.cgColor
    borderView.layer.borderWidth = 2.0
    #elseif canImport(AppKit)
    borderView.autoresizingMask = [.width, .height]
    borderView.wantsLayer = true
    borderView.layer?.borderColor = PlatformColor.red.cgColor
    borderView.layer?.borderWidth = 2.0
    #endif
    borderView.isHidden = true
  }

  #if canImport(UIKit)
  @objc private func tapReceived(sender: UITapGestureRecognizer) {
    if sender.state == .ended {
      try? editor?.update {
        var selection = try getSelection()
        if !(selection is NodeSelection) {
          let nodeSelection = NodeSelection(nodes: Set())
          getActiveEditorState()?.selection = nodeSelection
          selection = nodeSelection
        }
        guard let selection = selection as? NodeSelection, let nodeKey else {
          throw LexicalError.invariantViolation("Expected node selection by now")
        }
        selection.add(key: nodeKey)
      }
    }
  }
  #elseif canImport(AppKit)
  @objc private func tapReceived(sender: NSClickGestureRecognizer) {
    if sender.state == .ended {
      try? editor?.update {
        var selection = try getSelection()
        if !(selection is NodeSelection) {
          let nodeSelection = NodeSelection(nodes: Set())
          getActiveEditorState()?.selection = nodeSelection
          selection = nodeSelection
        }
        guard let selection = selection as? NodeSelection, let nodeKey else {
          throw LexicalError.invariantViolation("Expected node selection by now")
        }
        selection.add(key: nodeKey)
      }
    }
  }
  #endif

  private var drawsSelectionBorder: Bool = false
  private func setDrawsSelectionBorder(_ isSelected: Bool) {
    self.drawsSelectionBorder = isSelected
    borderView.isHidden = !isSelected
  }

  deinit {
    if let updateListener {
      updateListener()
    }
  }
}
