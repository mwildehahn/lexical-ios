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
  public let reconcilerAnchors: Bool
  public let useFenwickTreeOffsets: Bool

  @objc public init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    reconcilerAnchors: Bool = false,
    useFenwickTreeOffsets: Bool = false
  ) {
    self.reconcilerSanityCheck = reconcilerSanityCheck
    self.proxyTextViewInputDelegate = proxyTextViewInputDelegate
    self.reconcilerAnchors = reconcilerAnchors
    self.useFenwickTreeOffsets = useFenwickTreeOffsets
    super.init()
  }
}
