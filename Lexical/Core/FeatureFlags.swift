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
  public let useReconcilerDeleteBlockFenwick: Bool
  public let useReconcilerPrePostAttributesOnly: Bool
  public let useModernTextKitOptimizations: Bool
  public let verboseLogging: Bool
  public let prePostAttrsOnlyMaxTargets: Int

  // Profiles: convenience presets to reduce flag surface in product contexts.
  // Advanced flags remain available for development and testing.
  public enum OptimizedProfile {
    case minimal         // optimized + fenwick + modern batching; strict OFF
    case minimalDebug    // same as minimal, but verbose logging enabled
    case balanced        // minimal + pre/post attrs-only + insert-block
    case aggressive      // balanced + central aggregation + keyed diff + block rebuild
    case aggressiveDebug // same as aggressive, but verbose logging enabled
    case aggressiveEditor // tuned for live editing safety in the Editor tab
  }

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    useOptimizedReconciler: Bool = false,
    useReconcilerFenwickDelta: Bool = false,
    useReconcilerKeyedDiff: Bool = false,
    useReconcilerBlockRebuild: Bool = false,
    useOptimizedReconcilerStrictMode: Bool = true,
    useReconcilerFenwickCentralAggregation: Bool = false,
    useReconcilerShadowCompare: Bool = false,
    useReconcilerInsertBlockFenwick: Bool = false,
    useReconcilerDeleteBlockFenwick: Bool = false,
    useReconcilerPrePostAttributesOnly: Bool = false,
    useModernTextKitOptimizations: Bool = false,
    verboseLogging: Bool = false,
    prePostAttrsOnlyMaxTargets: Int = 0
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
    self.useReconcilerDeleteBlockFenwick = useReconcilerDeleteBlockFenwick
    self.useReconcilerPrePostAttributesOnly = useReconcilerPrePostAttributesOnly
    self.useModernTextKitOptimizations = useModernTextKitOptimizations
    self.verboseLogging = verboseLogging
    self.prePostAttrsOnlyMaxTargets = prePostAttrsOnlyMaxTargets
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
        useReconcilerDeleteBlockFenwick: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false,
        prePostAttrsOnlyMaxTargets: 16
      )
    case .minimalDebug:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerDeleteBlockFenwick: true,
        useModernTextKitOptimizations: true,
        verboseLogging: true,
        prePostAttrsOnlyMaxTargets: 16
      )
    case .balanced:
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerDeleteBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false,
        prePostAttrsOnlyMaxTargets: 16
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
        useReconcilerDeleteBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: false,
        prePostAttrsOnlyMaxTargets: 16
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
        useReconcilerDeleteBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: true,
        useModernTextKitOptimizations: true,
        verboseLogging: true,
        prePostAttrsOnlyMaxTargets: 16
      )
    case .aggressiveEditor:
      // Safer defaults for live editing in Editor tab:
      // - Keep all structural fast paths ON
      // - Disable pre/post attrs-only multi to avoid unexpected no-ops during typing
      // - Keep central aggregation ON for text multi
      // - Modern TextKit ON
      // - Gating threshold 0 (unused since pre/post attrs-only is OFF)
      return FeatureFlags(
        reconcilerSanityCheck: false,
        proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: true,
        useReconcilerBlockRebuild: true,
        useOptimizedReconcilerStrictMode: true,
        useReconcilerFenwickCentralAggregation: true,
        useReconcilerShadowCompare: false,
        useReconcilerInsertBlockFenwick: true,
        useReconcilerDeleteBlockFenwick: true,
        useReconcilerPrePostAttributesOnly: false,
        useModernTextKitOptimizations: true,
        verboseLogging: true,
        prePostAttrsOnlyMaxTargets: 0
      )
    }
  }
}
