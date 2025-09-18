/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import Foundation

@MainActor
enum DocumentFixtures {
  enum Size {
    case small
    case medium
    case large
  }

  static func populateDocument(
    editor: Editor,
    size: Size,
    wordsPerParagraph: Int = 12
  ) throws {
    switch size {
    case .small:
      try populate(editor: editor, paragraphs: 25, wordsPerParagraph: wordsPerParagraph)
    case .medium:
      try populate(editor: editor, paragraphs: 150, wordsPerParagraph: wordsPerParagraph)
    case .large:
      try populate(editor: editor, paragraphs: 600, wordsPerParagraph: wordsPerParagraph)
    }
  }

  static func populate(
    editor: Editor,
    paragraphs: Int,
    wordsPerParagraph: Int = 12
  ) throws {
    guard let rootNode = getActiveEditorState()?.getRootNode() else {
      throw LexicalError.internal("Expected active root node")
    }

    for index in 0..<paragraphs {
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: makeSentence(index: index, wordsPerParagraph: wordsPerParagraph), key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }
  }

  private static func makeSentence(index: Int, wordsPerParagraph: Int) -> String {
    let baseWords = [
      "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
      "integer", "velit", "neque", "fermentum", "gravida", "pulvinar", "sagittis"
    ]
    var words: [String] = []
    for wordIndex in 0..<wordsPerParagraph {
      let seed = (index * wordsPerParagraph + wordIndex) % baseWords.count
      words.append(baseWords[seed])
    }
    return "\(words.joined(separator: " "))."
  }
}
