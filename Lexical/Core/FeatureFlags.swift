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
  let darkLaunchOptimized: Bool
  let decoratorSiblingRedecorate: Bool
  let selectionParityDebug: Bool

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    optimizedReconciler: Bool = false,
    reconcilerMetrics: Bool = false,
    darkLaunchOptimized: Bool = false,
    decoratorSiblingRedecorate: Bool = false,
    selectionParityDebug: Bool = false
  ) {
    self.reconcilerSanityCheck = reconcilerSanityCheck
    self.proxyTextViewInputDelegate = proxyTextViewInputDelegate
    self.optimizedReconciler = optimizedReconciler
    self.reconcilerMetrics = reconcilerMetrics
    self.darkLaunchOptimized = darkLaunchOptimized
    self.decoratorSiblingRedecorate = decoratorSiblingRedecorate
    self.selectionParityDebug = selectionParityDebug
    super.init()
  }
}
