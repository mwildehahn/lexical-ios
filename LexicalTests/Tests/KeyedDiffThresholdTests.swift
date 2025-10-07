/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalUIKit
import XCTest

@MainActor
final class KeyedDiffThresholdTests: XCTestCase {
  func testReorderPrefersMinimalMovesWhenLISHigh() throws {
    // Prev children keys: A,B,C,D,E
    // Next order keeps most items in relative order (only E moves forward): A,B,E,C,D
    // Expect a high LIS and thus a large stable set (>= 80%).
    let A: NodeKey = "A", B: NodeKey = "B", C: NodeKey = "C", D: NodeKey = "D", E: NodeKey = "E"
    let prev = [A, B, C, D, E]
    let next = [A, B, E, C, D]
    let stable = computeStableChildKeys(prev: prev, next: next)
    XCTAssertEqual(stable.count, 4) // A,B,C,D remain in LIS
    XCTAssertGreaterThanOrEqual(Double(stable.count) / Double(next.count), 0.8)
  }

  func testReorderFallsBackToRebuildWhenLISLow() throws {
    // Prev children keys: A,B,C,D
    // Next order reverses everything: D,C,B,A
    // Expect a very small LIS (1) and thus a small stable set (<= 25%).
    let A: NodeKey = "A", B: NodeKey = "B", C: NodeKey = "C", D: NodeKey = "D"
    let prev = [A, B, C, D]
    let next = [D, C, B, A]
    let stable = computeStableChildKeys(prev: prev, next: next)
    XCTAssertEqual(stable.count, 1)
    XCTAssertLessThanOrEqual(Double(stable.count) / Double(next.count), 0.25)
  }
}
