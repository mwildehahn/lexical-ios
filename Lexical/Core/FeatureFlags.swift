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
    useModernTextKitOptimizations: Bool = false
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
    super.init()
  }
}
