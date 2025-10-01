/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Global runtime defaults for Lexical.
///
/// Use this switch to select whether newly created editors/views use the
/// optimized reconciler (aggressiveEditor profile) or the legacy defaults.
///
/// Notes
/// - This affects only instances created after the flag is changed. Existing
///   editors are not mutated.
/// - Tests and advanced callers can still pass a `FeatureFlags` instance
///   explicitly to override this default per-instance.
@objc public final class LexicalRuntime: NSObject {
  /// Toggle optimized reconciler globally for new instances.
  /// When true, `defaultFeatureFlags` resolves to
  /// `FeatureFlags.optimizedProfile(.aggressiveEditor)`.
  /// Enabled by default for production use. Tests can override per-instance
  /// by passing explicit FeatureFlags, or flip this switch in setUp/tearDown.
  @objc public static var isOptimizedReconcilerEnabled: Bool = true

  /// Optional override for Objective‑C callers to replace the default flags
  /// generator. When set, this value takes precedence over the closure-based
  /// provider and the builtin mapping.
  @objc public static var defaultFeatureFlagsOverride: FeatureFlags? = nil

  /// Optional closure provider for Swift users to customize default flags
  /// (e.g., to tweak logging) without forking. Ignored if the Obj‑C override
  /// is set.
  public static var defaultFeatureFlagsProvider: (() -> FeatureFlags)? = nil

  /// The default feature flags applied by constructors that do not receive
  /// an explicit `FeatureFlags`.
  @objc public static var defaultFeatureFlags: FeatureFlags {
    if let override = defaultFeatureFlagsOverride { return override }
    if let provider = defaultFeatureFlagsProvider { return provider() }
    return isOptimizedReconcilerEnabled
      ? FeatureFlags.optimizedProfile(.aggressiveEditor)
      : FeatureFlags()
  }

}
