/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerNoOpDeleteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_BackspaceAtStartOfDocument_NoOp() throws {
    let (opt, leg) = makeEditors()
    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return ctx.textStorage.string
    }
    let a = try run(on: opt).trimmingCharacters(in: .newlines)
    let b = try run(on: leg).trimmingCharacters(in: .newlines)
    XCTAssertEqual(a, b)
  }

  func testParity_ForwardDeleteAtEndOfDocument_NoOp() throws {
    let (opt, leg) = makeEditors()
    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return ctx.textStorage.string
    }
    let a = try run(on: opt).trimmingCharacters(in: .newlines)
    let b = try run(on: leg).trimmingCharacters(in: .newlines)
    XCTAssertEqual(a, b)
  }
}
