/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical

final class FlagsStore {
  static let shared = FlagsStore()
  private let d = UserDefaults.standard

  // Keys
  private enum K: String {
    case useOptimized, strict, fenwickDelta, centralAgg, keyedDiff, blockRebuild
    case shadowCompare, tk2, insertBlockFenwick, sanityCheck, proxyInputDelegate
  }

  private init() {}

  private func b(_ k: K, _ def: Bool = false) -> Bool { d.object(forKey: k.rawValue) == nil ? def : d.bool(forKey: k.rawValue) }
  private func set(_ k: K, _ v: Bool) { d.set(v, forKey: k.rawValue); d.synchronize(); notifyChanged() }

  var useOptimized: Bool { get { b(.useOptimized) } set { set(.useOptimized, newValue) } }
  var strict: Bool { get { b(.strict) } set { set(.strict, newValue) } }
  var fenwickDelta: Bool { get { b(.fenwickDelta) } set { set(.fenwickDelta, newValue) } }
  var centralAgg: Bool { get { b(.centralAgg) } set { set(.centralAgg, newValue) } }
  var keyedDiff: Bool { get { b(.keyedDiff) } set { set(.keyedDiff, newValue) } }
  var blockRebuild: Bool { get { b(.blockRebuild) } set { set(.blockRebuild, newValue) } }
  var shadowCompare: Bool { get { b(.shadowCompare) } set { set(.shadowCompare, newValue) } }
  var tk2: Bool { get { b(.tk2) } set { set(.tk2, newValue) } }
  var insertBlockFenwick: Bool { get { b(.insertBlockFenwick) } set { set(.insertBlockFenwick, newValue) } }
  var sanityCheck: Bool { get { b(.sanityCheck) } set { set(.sanityCheck, newValue) } }
  var proxyInputDelegate: Bool { get { b(.proxyInputDelegate) } set { set(.proxyInputDelegate, newValue) } }

  func makeFeatureFlags() -> FeatureFlags {
    FeatureFlags(
      reconcilerSanityCheck: sanityCheck,
      proxyTextViewInputDelegate: proxyInputDelegate,
      useOptimizedReconciler: useOptimized,
      useReconcilerFenwickDelta: fenwickDelta,
      useReconcilerKeyedDiff: keyedDiff,
      useReconcilerBlockRebuild: blockRebuild,
      useOptimizedReconcilerStrictMode: strict,
      useReconcilerFenwickCentralAggregation: centralAgg,
      useReconcilerShadowCompare: shadowCompare,
      useTextKit2Experimental: tk2,
      useReconcilerInsertBlockFenwick: insertBlockFenwick
    )
  }

  func signature() -> String {
    return [
      useOptimized, strict, fenwickDelta, centralAgg, keyedDiff, blockRebuild,
      insertBlockFenwick, tk2, shadowCompare, sanityCheck, proxyInputDelegate
    ].map { $0 ? "1" : "0" }.joined()
  }

  private func notifyChanged() { NotificationCenter.default.post(name: .featureFlagsDidChange, object: nil) }
}

extension Notification.Name { static let featureFlagsDidChange = Notification.Name("FeatureFlagsDidChange") }
