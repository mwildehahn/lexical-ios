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
  let optimizedReconciler: Bool
  let reconcilerMetrics: Bool

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    optimizedReconciler: Bool = false,
    reconcilerMetrics: Bool = false
  ) {
    self.reconcilerSanityCheck = reconcilerSanityCheck
    self.proxyTextViewInputDelegate = proxyTextViewInputDelegate
    self.optimizedReconciler = optimizedReconciler
    self.reconcilerMetrics = reconcilerMetrics
    super.init()
  }
}
