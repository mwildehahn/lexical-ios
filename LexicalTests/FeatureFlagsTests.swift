/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

class FeatureFlagsTests: XCTestCase {

  func testDefaultFeatureFlags() throws {
    let flags = FeatureFlags()

    // All feature flags should be disabled by default
    XCTAssertFalse(flags.reconcilerSanityCheck)
    XCTAssertFalse(flags.proxyTextViewInputDelegate)
    XCTAssertFalse(flags.optimizedReconciler)
    XCTAssertFalse(flags.reconcilerMetrics)
    XCTAssertFalse(flags.anchorBasedReconciliation)
  }

  func testOptimizedReconcilerFlag() throws {
    let flags = FeatureFlags(optimizedReconciler: true)

    XCTAssertTrue(flags.optimizedReconciler)
    XCTAssertFalse(flags.reconcilerMetrics)
    XCTAssertFalse(flags.anchorBasedReconciliation)
  }

  func testReconcilerMetricsFlag() throws {
    let flags = FeatureFlags(reconcilerMetrics: true)

    XCTAssertTrue(flags.reconcilerMetrics)
    XCTAssertFalse(flags.optimizedReconciler)
    XCTAssertFalse(flags.anchorBasedReconciliation)
  }

  func testAnchorBasedReconciliationFlag() throws {
    let flags = FeatureFlags(anchorBasedReconciliation: true)

    XCTAssertTrue(flags.anchorBasedReconciliation)
    XCTAssertFalse(flags.optimizedReconciler)
    XCTAssertFalse(flags.reconcilerMetrics)
  }

  func testAllFlagsEnabled() throws {
    let flags = FeatureFlags(
      reconcilerSanityCheck: true,
      proxyTextViewInputDelegate: true,
      optimizedReconciler: true,
      reconcilerMetrics: true,
      anchorBasedReconciliation: true
    )

    XCTAssertTrue(flags.reconcilerSanityCheck)
    XCTAssertTrue(flags.proxyTextViewInputDelegate)
    XCTAssertTrue(flags.optimizedReconciler)
    XCTAssertTrue(flags.reconcilerMetrics)
    XCTAssertTrue(flags.anchorBasedReconciliation)
  }

  func testMixedFlags() throws {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: true,
      optimizedReconciler: false,
      reconcilerMetrics: true,
      anchorBasedReconciliation: false
    )

    XCTAssertFalse(flags.reconcilerSanityCheck)
    XCTAssertTrue(flags.proxyTextViewInputDelegate)
    XCTAssertFalse(flags.optimizedReconciler)
    XCTAssertTrue(flags.reconcilerMetrics)
    XCTAssertFalse(flags.anchorBasedReconciliation)
  }
}