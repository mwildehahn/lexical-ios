/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class RangeCacheTests: XCTestCase {

  @MainActor
  func testRangeCacheStoresAnchorLengths() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = context.editor

    var paragraphKeys: [NodeKey] = []

    var textNodeKey: NodeKey = ""

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }

      let firstParagraph = ParagraphNode()
      let firstTextNode = TextNode(text: "Alpha", key: nil)
      try firstParagraph.append([firstTextNode])
      try rootNode.append([firstParagraph])
      paragraphKeys.append(firstParagraph.key)

      let secondParagraph = ParagraphNode()
      let secondTextNode = TextNode(text: "Beta", key: nil)
      try secondParagraph.append([secondTextNode])
      try rootNode.append([secondParagraph])
      paragraphKeys.append(secondParagraph.key)
    }

    try editor.read {
      for key in paragraphKeys {
        guard let cacheItem = editor.rangeCache[key] else {
          XCTFail("Missing cache entry for \(key)")
          continue
        }
        let expectedStartLength = AnchorMarkers.make(kind: .start, key: key).lengthAsNSString()
        let expectedEndLength = AnchorMarkers.make(kind: .end, key: key).lengthAsNSString()

        XCTAssertEqual(cacheItem.startAnchorLength, expectedStartLength)
        XCTAssertEqual(cacheItem.endAnchorLength, expectedEndLength)
        XCTAssertGreaterThanOrEqual(cacheItem.preambleLength, cacheItem.startAnchorLength)
        XCTAssertGreaterThanOrEqual(cacheItem.postambleLength, cacheItem.endAnchorLength)
      }
    }
  }

  func testSearchRangeCacheForPoints() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      createExampleNodeTree()
    }

    let rangeCache = editor.rangeCache

    try editor.update {
      guard let point1 = try pointAtStringLocation(0, searchDirection: .forward, rangeCache: rangeCache),
            let point2 = try pointAtStringLocation(1, searchDirection: .forward, rangeCache: rangeCache),
            let point3 = try pointAtStringLocation(6, searchDirection: .forward, rangeCache: rangeCache),
            let point4 = try pointAtStringLocation(6, searchDirection: .backward, rangeCache: rangeCache),
            let point5 = try pointAtStringLocation(11, searchDirection: .forward, rangeCache: rangeCache),
            let point6 = try pointAtStringLocation(12, searchDirection: .forward, rangeCache: rangeCache),
            let point7 = try pointAtStringLocation(51, searchDirection: .forward, rangeCache: rangeCache)
      else {
        XCTFail("Expected points")
        return
      }

      XCTAssertEqual(point1.key, "1")
      XCTAssertEqual(point1.type, .text)
      XCTAssertEqual(point1.offset, 0)

      XCTAssertEqual(point2.key, "1")
      XCTAssertEqual(point2.type, .text)
      XCTAssertEqual(point2.offset, 1)

      XCTAssertEqual(point3.key, "1")
      XCTAssertEqual(point3.type, .text)
      XCTAssertEqual(point3.offset, 6)

      XCTAssertEqual(point4.key, "2")
      XCTAssertEqual(point4.type, .text)
      XCTAssertEqual(point4.offset, 0)

      XCTAssertEqual(point5.key, "2")
      XCTAssertEqual(point5.type, .text)
      XCTAssertEqual(point5.offset, 5)

      XCTAssertEqual(point6.key, "3")
      XCTAssertEqual(point6.type, .text)
      XCTAssertEqual(point6.offset, 0)

      XCTAssertEqual(point7.key, "5")
      XCTAssertEqual(point7.type, .element)
      XCTAssertEqual(point7.offset, 0)
    }
  }

  func testSearchRangeCacheForLastParagraphWithNoChildren() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.nodeMap[kRootNodeKey] as? ElementNode,
            let firstParagraph = getNodeByKey(key: "0") as? ParagraphNode
      else {
        XCTFail("Failed to get the rootNode")
        return
      }

      let textNode1 = TextNode()
      try textNode1.setText("This is first paragraph")
      try firstParagraph.append([textNode1])

      let newParagraphNode = ParagraphNode()
      let anotherParagraph = ParagraphNode()

      let textNode2 = TextNode()
      try textNode2.setText("This is third paragraph")

      try anotherParagraph.append([textNode2])

      let yetAnotherParagraph = ParagraphNode()
      try rootNode.append([newParagraphNode, anotherParagraph, yetAnotherParagraph])

      // location points to yetAnotherParagraph
      guard let newPoint = try pointAtStringLocation(49, searchDirection: .forward, rangeCache: editor.rangeCache) else { return }

      XCTAssertEqual(newPoint.key, yetAnotherParagraph.key)
      XCTAssertEqual(newPoint.type, .element)
      XCTAssertEqual(newPoint.offset, 0)

      let selection = RangeSelection(anchor: newPoint, focus: newPoint, format: TextFormat())
      try selection.insertText("Test")

      if let newTextNode = yetAnotherParagraph.getFirstChild() as? TextNode {
        XCTAssertEqual(newTextNode.getTextPart(), "Test")
      } else {
        XCTFail("Failed to add new text node to yetAnotherParagraph")
      }
    }
  }

  func testUpdatesOffsetsWithFenwick() {
    var rangeCache: [NodeKey: RangeCacheItem] = [:]
    var first = RangeCacheItem()
    first.location = 0
    first.preambleLength = 0
    rangeCache["A"] = first

    var second = RangeCacheItem()
    second.location = 10
    rangeCache["B"] = second

    var third = RangeCacheItem()
    third.location = 20
    rangeCache["C"] = third

    let index = RangeCacheLocationIndex()
    index.rebuild(rangeCache: rangeCache)

    index.shiftNodes(startingAt: 15, delta: 5)

    let resolvedSecond = rangeCache["B"]!.resolvingLocation(using: index, key: "B")
    let resolvedThird = rangeCache["C"]!.resolvingLocation(using: index, key: "C")

    XCTAssertEqual(resolvedSecond.location, 10)
    XCTAssertEqual(resolvedThird.location, 25)
  }

  func testPointAtLocationSkipsAnchorMarkers() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = view.editor

    var paragraphKey: NodeKey = ""
    var textNodeKey: NodeKey = ""
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }

      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Anchor", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
      paragraphKey = paragraph.key
      textNodeKey = textNode.key
      try paragraph.select(anchorOffset: nil, focusOffset: nil)
    }

    let injectedAnchorLength = AnchorMarkers.make(kind: .start, key: paragraphKey).lengthAsNSString()
    guard var cacheItemOverride = editor.rangeCache[paragraphKey] else {
      XCTFail("Missing cache item")
      return
    }
    let originalPreamble = cacheItemOverride.preambleLength
    cacheItemOverride.startAnchorLength = injectedAnchorLength
    cacheItemOverride.preambleLength = originalPreamble + injectedAnchorLength
    cacheItemOverride.preambleSpecialCharacterLength += injectedAnchorLength
    editor.rangeCache[paragraphKey] = cacheItemOverride

    if var textItem = editor.rangeCache[textNodeKey] {
      textItem.location = cacheItemOverride.location + cacheItemOverride.preambleLength
      editor.rangeCache[textNodeKey] = textItem
    }

    editor.rangeCacheLocationIndex.rebuild(rangeCache: editor.rangeCache)

    try editor.read {
      guard let cacheItem = editor.rangeCache[paragraphKey] else {
        XCTFail("Missing cache item")
        return
      }

      let textPoint = Point(key: textNodeKey, offset: 0, type: .text)
      let stringLocation = try stringLocationForPoint(textPoint, editor: editor)
      XCTAssertEqual(stringLocation, cacheItem.location + cacheItem.preambleLength)
      XCTAssertEqual(cacheItem.startAnchorLength, injectedAnchorLength)
    }
  }
}
