/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public class FeatureFlags: NSObject {
  public let reconcilerSanityCheck: Bool
  public let proxyTextViewInputDelegate: Bool
  public let useOptimizedReconciler: Bool
  public let useReconcilerFenwickDelta: Bool
  public let useReconcilerKeyedDiff: Bool
  public let useReconcilerBlockRebuild: Bool
  public let useOptimizedReconcilerStrictMode: Bool
  public let useReconcilerFenwickCentralAggregation: Bool
  public let useReconcilerShadowCompare: Bool
  public let useReconcilerInsertBlockFenwick: Bool
  public let useReconcilerPrePostAttributesOnly: Bool
  public let useModernTextKitOptimizations: Bool
  public let verboseLogging: Bool

  // Profiles: convenience presets to reduce flag surface in product contexts.
  // Advanced flags remain available for development and testing.
  public enum OptimizedProfile {
    case minimal         // optimized + fenwick + modern batching; strict OFF
    case minimalDebug    // same as minimal, but verbose logging enabled
    case balanced        // minimal + pre/post attrs-only + insert-block
    case aggressive      // balanced + central aggregation + keyed diff + block rebuild
    case aggressiveDebug // same as aggressive, but verbose logging enabled
  }

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    useOptimizedReconciler: Bool = false,
    useReconcilerFenwickDelta: Bool = false,
    useReconcilerKeyedDiff: Bool = false,
    useReconcilerBlockRebuild: Bool = false,
    useOptimizedReconcilerStrictMode: Bool = false,
    useReconcilerFenwickCentralAggregation: Bool = false,
    useReconcilerShadowCompare: Bool = false,
    useReconcilerInsertBlockFenwick: Bool = false,
    useReconcilerPrePostAttributesOnly: Bool = false,
    useModernTextKitOptimizations: Bool = false,
    verboseLogging: Bool = false
  ) {
    self.reconcilerSanityCheck = reconcilerSanityCheck
    self.proxyTextViewInputDelegate = proxyTextViewInputDelegate
    self.useOptimizedReconciler = useOptimizedReconciler
    self.useReconcilerFenwickDelta = useReconcilerFenwickDelta
    self.useReconcilerKeyedDiff = useReconcilerKeyedDiff
    self.useReconcilerBlockRebuild = useReconcilerBlockRebuild
    self.useOptimizedReconcilerStrictMode = useOptimizedReconcilerStrictMode
    self.useReconcilerFenwickCentralAggregation = useReconcilerFenwickCentralAggregation
    self.useReconcilerShadowCompare = useReconcilerShadowCompare
    self.useReconcilerInsertBlockFenwick = useReconcilerInsertBlockFenwick
    self.useReconcilerPrePostAttributesOnly = useReconcilerPrePostAttributesOnly
    self.useModernTextKitOptimizations = useModernTextKitOptimizations
    self.verboseLogging = verboseLogging
    super.init()
  }

  // MARK: - Convenience Profiles
  public static func optimizedProfile(_ p: OptimizedProfile) -> FeatureFlags {
    switch p {
    case .minimal:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerInsertBlockFenwick: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false
      )
    case .minimalDebug:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerInsertBlockFenwick: true,
        useModernTextKitOptimizations: true,
        verboseLogging: true
      )
    case .balanced:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false
      )
    case .aggressive:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: true,
        useReconcilerBlockRebuild: true,
        useReconcilerFenwickCentralAggregation: true,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false
      )
    case .aggressiveDebug:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: true,
        useReconcilerBlockRebuild: true,
        useReconcilerFenwickCentralAggregation: true,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: true
      )
    }
  }
}
