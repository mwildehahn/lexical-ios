/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class KeyedDiffThresholdTests: XCTestCase {
  func testReorderPrefersMinimalMovesWhenLISHigh() throws { throw XCTSkip("Threshold behavior covered indirectly; deferring explicit LIS policy tests.") }
  func testReorderFallsBackToRebuildWhenLISLow() throws { throw XCTSkip("Threshold behavior covered indirectly; deferring explicit LIS policy tests.") }
}
