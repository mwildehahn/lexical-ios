/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import LexicalHTML
import LexicalListPlugin
import LexicalMarkdown

enum OutputFormat: CaseIterable {
  case html
  case json
  case markdown
  case plainText

  var title: String {
    switch self {
    case .html: return "HTML"
    case .json: return "JSON"
    case .markdown: return "Markdown"
    case .plainText: return "Plain Text"
    }
  }

  @MainActor
  func generate(editor: Editor) throws -> String {
    switch self {
    case .html:
      var result = ""
      try editor.read {
        result = try generateHTMLFromNodes(editor: editor, selection: nil)
      }
      return result

    case .json:
      let currentEditorState = editor.getEditorState()
      guard let jsonString = try? currentEditorState.toJSON() else {
        throw NSError(domain: "OutputFormat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate JSON"])
      }
      return jsonString

    case .markdown:
      var result = ""
      try editor.read {
        result = try LexicalMarkdown.generateMarkdown(from: editor, selection: nil)
      }
      return result

    case .plainText:
      var result = ""
      try editor.read {
        guard let root = getRoot() else {
          throw NSError(domain: "OutputFormat", code: 2, userInfo: [NSLocalizedDescriptionKey: "No root node"])
        }
        result = root.getTextContent()
      }
      return result
    }
  }
}
