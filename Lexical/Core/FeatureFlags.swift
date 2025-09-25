/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public class FeatureFlags: NSObject {
  let reconcilerSanityCheck: Bool
  let proxyTextViewInputDelegate: Bool
  let useOptimizedReconciler: Bool
  let useReconcilerFenwickDelta: Bool
  let useReconcilerKeyedDiff: Bool
  let useReconcilerBlockRebuild: Bool
  let useOptimizedReconcilerStrictMode: Bool
  let useReconcilerFenwickCentralAggregation: Bool
  let useReconcilerShadowCompare: Bool

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    useOptimizedReconciler: Bool = false,
    useReconcilerFenwickDelta: Bool = false,
    useReconcilerKeyedDiff: Bool = false,
    useReconcilerBlockRebuild: Bool = false,
    useOptimizedReconcilerStrictMode: Bool = false,
    useReconcilerFenwickCentralAggregation: Bool = false,
    useReconcilerShadowCompare: Bool = false
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
    super.init()
  }
}
