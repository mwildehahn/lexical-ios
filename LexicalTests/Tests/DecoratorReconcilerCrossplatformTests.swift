/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Cross-platform decorator reconciler tests that run on both UIKit and AppKit

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class DecoratorReconcilerCrossplatformTests: XCTestCase {

  func testParagraphReorderWithDecoratorMiddle() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Build: P -> [A, D, B]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([createTextNode(text: "A"), TestDecoratorNodeCrossplatform(), createTextNode(text: "B")])
      try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([createTextNode(text: "A"), TestDecoratorNodeCrossplatform(), createTextNode(text: "B")])
      try root.append([p])
    }

    // Reorder to [B, D, A]
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let d = p.getChildAtIndex(index: 1) as? DecoratorNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try b.insertBefore(nodeToInsert: a) // [B, D, A]
      _ = try b.insertAfter(nodeToInsert: d)  // keep decorator in middle
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let d = p.getChildAtIndex(index: 1) as? DecoratorNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try b.insertBefore(nodeToInsert: a)
      _ = try b.insertAfter(nodeToInsert: d)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testNestedReorderWithDecorators() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Build: root -> [P1, P2] where P1 -> [A, D1], P2 -> [B, D2]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let p2 = createParagraphNode()
      try p1.append([createTextNode(text: "A"), TestDecoratorNodeCrossplatform()])
      try p2.append([createTextNode(text: "B"), TestDecoratorNodeCrossplatform()])
      try root.append([p1, p2])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let p2 = createParagraphNode()
      try p1.append([createTextNode(text: "A"), TestDecoratorNodeCrossplatform()])
      try p2.append([createTextNode(text: "B"), TestDecoratorNodeCrossplatform()])
      try root.append([p1, p2])
    }

    // Swap order: P2 first, then P1
    try opt.0.update {
      guard let root = getRoot(),
            let p1 = root.getFirstChild() as? ParagraphNode,
            let p2 = root.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2)
    }
    try leg.0.update {
      guard let root = getRoot(),
            let p1 = root.getFirstChild() as? ParagraphNode,
            let p2 = root.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testDecoratorInsertionMidParagraph() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Build: P -> [A, B]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([createTextNode(text: "A"), createTextNode(text: "B")])
      try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([createTextNode(text: "A"), createTextNode(text: "B")])
      try root.append([p])
    }

    // Insert decorator between A and B
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode else { return }
      let d = TestDecoratorNodeCrossplatform()
      _ = try a.insertAfter(nodeToInsert: d)
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode else { return }
      let d = TestDecoratorNodeCrossplatform()
      _ = try a.insertAfter(nodeToInsert: d)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testDecoratorRemoval() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    var optDecoratorKey: NodeKey?
    var legDecoratorKey: NodeKey?

    // Build: P -> [A, D, B]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNodeCrossplatform()
      try p.append([createTextNode(text: "A"), d, createTextNode(text: "B")])
      try root.append([p])
      optDecoratorKey = d.getKey()
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNodeCrossplatform()
      try p.append([createTextNode(text: "A"), d, createTextNode(text: "B")])
      try root.append([p])
      legDecoratorKey = d.getKey()
    }

    // Remove decorator
    try opt.0.update {
      guard let key = optDecoratorKey,
            let d = getNodeByKey(key: key) as? DecoratorNode else { return }
      try d.remove()
    }
    try leg.0.update {
      guard let key = legDecoratorKey,
            let d = getNodeByKey(key: key) as? DecoratorNode else { return }
      try d.remove()
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    // Should just have "AB" now (plus pre/postamble)
    XCTAssertTrue(opt.1.textStorage.string.contains("AB"))
  }

  func testMultipleDecoratorsInSequence() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Build: P -> [D1, D2, D3]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([
        TestDecoratorNodeCrossplatform(),
        TestDecoratorNodeCrossplatform(),
        TestDecoratorNodeCrossplatform()
      ])
      try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([
        TestDecoratorNodeCrossplatform(),
        TestDecoratorNodeCrossplatform(),
        TestDecoratorNodeCrossplatform()
      ])
      try root.append([p])
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)

    // Each decorator contributes one attachment character (the \uFFFC character)
    // The text storage should contain 3 attachment characters
    let attachmentChar = "\u{FFFC}"
    let optCount = opt.1.textStorage.string.filter { String($0) == attachmentChar }.count
    let legCount = leg.1.textStorage.string.filter { String($0) == attachmentChar }.count
    XCTAssertEqual(optCount, legCount, "Optimized and legacy should have same number of attachment chars")
    XCTAssertEqual(optCount, 3, "Should have 3 decorator attachment characters")
  }

  func testDecoratorWithTextFormatting() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Build: P -> [bold "A", D, italic "B"]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let a = createTextNode(text: "A")
      try a.setBold(true)
      let b = createTextNode(text: "B")
      try b.setItalic(true)
      try p.append([a, TestDecoratorNodeCrossplatform(), b])
      try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let a = createTextNode(text: "A")
      try a.setBold(true)
      let b = createTextNode(text: "B")
      try b.setItalic(true)
      try p.append([a, TestDecoratorNodeCrossplatform(), b])
      try root.append([p])
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
