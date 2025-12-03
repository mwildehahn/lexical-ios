/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Tests for decorator node support on AppKit

#if os(macOS) && !targetEnvironment(macCatalyst)

import AppKit
@testable import Lexical
@testable import LexicalAppKit
import XCTest

extension NodeType {
  static let testDecoratorNodeAppKit = NodeType(rawValue: "testDecoratorNodeAppKit")
}

class TestDecoratorNodeAppKit: DecoratorNode {
  var numberOfTimesDecorateHasBeenCalled = 0

  public required init(numTimes: Int, key: NodeKey? = nil) {
    super.init(key)
    self.numberOfTimesDecorateHasBeenCalled = numTimes
  }

  override init() {
    super.init(nil)
  }

  public required init(_ key: NodeKey?) {
    super.init(key)
  }

  required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    fatalError("init(from:) has not been implemented")
  }

  override public func clone() -> Self {
    Self(numTimes: numberOfTimesDecorateHasBeenCalled, key: key)
  }

  override public class func getType() -> NodeType {
    .testDecoratorNodeAppKit
  }

  override public func createView() -> NSImageView {
    return NSImageView()
  }

  override public func decorate(view: NSView) {
    getLatest().numberOfTimesDecorateHasBeenCalled += 1
  }

  override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGSize {
    return CGSize(width: 100, height: 100)
  }
}

class DecoratorNodeAppKitTests: XCTestCase {

  func createLexicalView() -> LexicalView {
    return LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  }

  func testIsDecoratorNode() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.update {
      let decoratorNode = DecoratorNode()
      let textNode = TextNode()

      XCTAssert(isDecoratorNode(decoratorNode))
      XCTAssert(!isDecoratorNode(textNode))
    }
  }

  func testDecoratorNodeGetAttributedStringAttributes() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.registerNode(nodeType: NodeType.testDecoratorNodeAppKit, class: TestDecoratorNodeAppKit.self)

    var nodeKey: NodeKey?

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      let paragraphNode = ParagraphNode()
      let decoratorNode = TestDecoratorNodeAppKit()
      try paragraphNode.append([decoratorNode])
      nodeKey = decoratorNode.getKey()

      try rootNode.append([paragraphNode])
    }

    try editor.read {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail("Could not get decorator node")
        return
      }

      let theme = Theme()
      let attributes = decoratorNode.getAttributedStringAttributes(theme: theme)

      // Verify the attachment is a TextAttachmentAppKit
      XCTAssertNotNil(attributes[.attachment], "Decorator node should have attachment attribute")
      XCTAssert(attributes[.attachment] is TextAttachmentAppKit, "Attachment should be TextAttachmentAppKit")

      if let attachment = attributes[.attachment] as? TextAttachmentAppKit {
        XCTAssertEqual(attachment.key, nodeKey, "Attachment should have the correct node key")
        XCTAssertNotNil(attachment.editor, "Attachment should have editor reference")
      }
    }
  }

  func testDecoratorNodeAddsSubViewOnceOnNodeCreation() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.registerNode(nodeType: NodeType.testDecoratorNodeAppKit, class: TestDecoratorNodeAppKit.self)

    guard let viewForDecoratorSubviews = view.viewForDecoratorSubviews else {
      XCTFail("No view for decorator subviews")
      return
    }

    let initialSubViewCount = viewForDecoratorSubviews.subviews.count

    XCTAssertFalse(viewForDecoratorSubviews.subviews.last is NSImageView)

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      let paragraphNode = ParagraphNode()

      let textNode = TextNode()
      try textNode.setText("Hello")

      let decoratorNode = TestDecoratorNodeAppKit()

      try paragraphNode.append([textNode])
      try paragraphNode.append([decoratorNode])

      try rootNode.append([paragraphNode])
    }

    // Multiple updates to ensure mounting happens
    try editor.update {}
    try editor.update {}
    try editor.update {}

    XCTAssertEqual(viewForDecoratorSubviews.subviews.count, initialSubViewCount + 1, "Should have added one decorator subview")
    XCTAssertTrue(viewForDecoratorSubviews.subviews.last is NSImageView, "Last subview should be NSImageView")
  }

  func testDecorateCalledOnlyWhenDirty() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.registerNode(nodeType: NodeType.testDecoratorNodeAppKit, class: TestDecoratorNodeAppKit.self)

    var nodeKey: NodeKey?

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      let paragraphNode = ParagraphNode()

      let decoratorNode = TestDecoratorNodeAppKit()
      try paragraphNode.append([decoratorNode])
      nodeKey = decoratorNode.getKey()

      try rootNode.append([paragraphNode])
    }

    try editor.read {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail()
        return
      }
      XCTAssertEqual(decoratorNode.numberOfTimesDecorateHasBeenCalled, 1)
    }

    try editor.update {}

    try editor.read {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail()
        return
      }
      XCTAssertEqual(decoratorNode.numberOfTimesDecorateHasBeenCalled, 1, "should still be 1 after an update where nothing changed")
    }

    try editor.update {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail()
        return
      }
      internallyMarkNodeAsDirty(node: decoratorNode, cause: .userInitiated)
    }

    try editor.read {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail()
        return
      }
      XCTAssertEqual(decoratorNode.numberOfTimesDecorateHasBeenCalled, 2, "should be 2 after a dirty update")
    }
  }

  func testDecoratorViewCache() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.registerNode(nodeType: NodeType.testDecoratorNodeAppKit, class: TestDecoratorNodeAppKit.self)

    var nodeKey: NodeKey?

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      let paragraphNode = ParagraphNode()
      let decoratorNode = TestDecoratorNodeAppKit()
      try paragraphNode.append([decoratorNode])
      nodeKey = decoratorNode.getKey()

      try rootNode.append([paragraphNode])
    }

    // Force mounting
    try editor.update {}

    try editor.read {
      guard let nodeKey else {
        XCTFail("No node key")
        return
      }

      // Check that decorator view was cached
      let cacheItem = editor.decoratorCache[nodeKey]
      XCTAssertNotNil(cacheItem, "Decorator should be in cache")

      if case .cachedView(let view) = cacheItem {
        XCTAssertTrue(view is NSImageView, "Cached view should be NSImageView")
      } else if case .unmountedCachedView(let view) = cacheItem {
        XCTAssertTrue(view is NSImageView, "Unmounted cached view should be NSImageView")
      } else {
        // needsCreation or needsDecorating states are also valid at this point
      }
    }
  }

  func testDecoratorSizeCalculation() throws {
    let view = createLexicalView()
    let editor = view.editor

    try editor.registerNode(nodeType: NodeType.testDecoratorNodeAppKit, class: TestDecoratorNodeAppKit.self)

    var nodeKey: NodeKey?

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      let paragraphNode = ParagraphNode()
      let decoratorNode = TestDecoratorNodeAppKit()
      try paragraphNode.append([decoratorNode])
      nodeKey = decoratorNode.getKey()

      try rootNode.append([paragraphNode])
    }

    try editor.read {
      guard let nodeKey, let decoratorNode = getNodeByKey(key: nodeKey) as? TestDecoratorNodeAppKit else {
        XCTFail("Could not get decorator node")
        return
      }

      let size = decoratorNode.sizeForDecoratorView(textViewWidth: 500, attributes: [:])
      XCTAssertEqual(size.width, 100)
      XCTAssertEqual(size.height, 100)
    }
  }
}

#endif
