/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class FeatureFlagsTests: XCTestCase {

  func testDefaultsAreDisabled() {
    let flags = FeatureFlags()

    XCTAssertFalse(flags.reconcilerSanityCheck)
    XCTAssertFalse(flags.proxyTextViewInputDelegate)
    XCTAssertFalse(flags.reconcilerAnchors)
  }

  func testCustomInitializerSetsAnchors() {
    let flags = FeatureFlags(
      reconcilerSanityCheck: true,
      proxyTextViewInputDelegate: true,
      reconcilerAnchors: true
    )

    XCTAssertTrue(flags.reconcilerSanityCheck)
    XCTAssertTrue(flags.proxyTextViewInputDelegate)
    XCTAssertTrue(flags.reconcilerAnchors)
  }
}
