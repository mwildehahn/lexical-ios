//
//  EventPlugin.swift
//  LexicalPlayground
//
//  Created by Nemanja Kovacevic on 15.11.24..
//
import Foundation
import Lexical
import UIKit

extension CommandType {
  
  public static let event = CommandType(rawValue: "event")
  public static let removeEvent = CommandType(rawValue: "removeEvent")
  
}

public struct EventPayload {
  
  let event: Event?
  let originalSelection: RangeSelection?

  public init(event: Event?, originalSelection: RangeSelection?) {
    self.event = event
    self.originalSelection = originalSelection
  }
  
}

open class EventPlugin: Plugin {
  
  public init() {}

  weak var editor: Editor?
  public weak var lexicalView: LexicalView?

  public func setUp(editor: Editor) {
    self.editor = editor
    do {
      try editor.registerNode(nodeType: NodeType.event, class: EventNode.self)
    } catch {
      print("\(error)")
    }

    _ = editor.registerCommand(type: .event, listener: { [weak self] payload in
      guard let strongSelf = self,
            let eventPayload = payload as? EventPayload,
            let editor = strongSelf.editor
      else { return false }

      strongSelf.insertEvent(eventPayload: eventPayload, editor: editor)
      return true
    })

    _ = editor.registerCommand(type: .removeEvent, listener: { [weak self] _ in
      guard let strongSelf = self,
            let editor = strongSelf.editor
      else { return false }

      strongSelf.insertEvent(eventPayload: nil, editor: editor)
      return true
    })
  }

  public func tearDown() {
  }

  public func createEventNode(title: String) -> EventNode {
    EventNode(event: Event(title: title), key: nil)
  }

  public func isEventNode(_ node: Node?) -> Bool {
    node is EventNode
  }

  func insertEvent(eventPayload: EventPayload?, editor: Editor) {
    do {
      var modifiedSelection: BaseSelection?
      try editor.update {
        getActiveEditorState()?.selection = eventPayload?.originalSelection
        try insertEvent(event: eventPayload?.event)
        modifiedSelection = try getSelection()?.clone()
      }
      lexicalView?.textViewBecomeFirstResponder()
      try editor.update {
        getActiveEditorState()?.selection = modifiedSelection
      }
    } catch {
      print("\(error)")
    }
  }

  func insertEvent(event: Event?) throws {
    guard let selection = try getSelection() else { return }
    let nodes = try selection.extract()
    let eventNode = EventNode(event: event)
    try nodes.first?.insertAfter(nodeToInsert: eventNode)
  }
  
}
