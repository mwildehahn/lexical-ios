/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public enum ReconcilerMode: Int {
  case legacy
  case optimized
  case darkLaunch
}

@objc public class Diagnostics: NSObject {
  @objc public let selectionParity: Bool
  @objc public let sanityChecks: Bool
  @objc public let metrics: Bool
  @objc public let verboseLogs: Bool

  @objc public init(selectionParity: Bool = false,
                    sanityChecks: Bool = false,
                    metrics: Bool = false,
                    verboseLogs: Bool = false) {
    self.selectionParity = selectionParity
    self.sanityChecks = sanityChecks
    self.metrics = metrics
    self.verboseLogs = verboseLogs
    super.init()
  }
}

@objc public class FeatureFlags: NSObject {
  @objc public let reconcilerMode: ReconcilerMode
  @objc public let proxyTextViewInputDelegate: Bool
  @objc public let diagnostics: Diagnostics

  @objc public init(reconcilerMode: ReconcilerMode = .legacy,
                    proxyTextViewInputDelegate: Bool = false,
                    diagnostics: Diagnostics = Diagnostics()) {
    self.reconcilerMode = reconcilerMode
    self.proxyTextViewInputDelegate = proxyTextViewInputDelegate
    self.diagnostics = diagnostics
    super.init()
  }

  // Back-compat computed properties (to be removed after migration)
  @objc public var optimizedReconciler: Bool { reconcilerMode == .optimized }
  @objc public var darkLaunchOptimized: Bool { reconcilerMode == .darkLaunch }
  @objc public var reconcilerSanityCheck: Bool { diagnostics.sanityChecks }
  @objc public var reconcilerMetrics: Bool { diagnostics.metrics }
  @objc public var selectionParityDebug: Bool { diagnostics.selectionParity }

  // Back-compat initializer (drops removed flags)
  @objc public convenience init(
    reconcilerSanityCheck: Bool = false,
    proxyTextViewInputDelegate: Bool = false,
    optimizedReconciler: Bool = false,
    reconcilerMetrics: Bool = false,
    darkLaunchOptimized: Bool = false,
    selectionParityDebug: Bool = false
  ) {
    let mode: ReconcilerMode = darkLaunchOptimized ? .darkLaunch : (optimizedReconciler ? .optimized : .legacy)
    let diags = Diagnostics(selectionParity: selectionParityDebug,
                            sanityChecks: reconcilerSanityCheck,
                            metrics: reconcilerMetrics,
                            verboseLogs: false)
    self.init(reconcilerMode: mode, proxyTextViewInputDelegate: proxyTextViewInputDelegate, diagnostics: diags)
  }
}
