/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@MainActor
public protocol EditorMetricsContainer: AnyObject {
  func record(_ metric: EditorMetric)
  func resetMetrics()
}

public struct ReconcilerMetric {
  // Total wall duration of reconciler update
  public let duration: TimeInterval
  // Dirty bookkeeping
  public let dirtyNodes: Int
  public let rangesAdded: Int
  public let rangesDeleted: Int
  public let treatedAllNodesAsDirty: Bool

  // Optional: optimized reconciler details (when available)
  public let pathLabel: String?             // e.g., text-only, prepost-only, reorder-minimal, reorder-rebuild, slow
  public let planningDuration: TimeInterval // time spent planning (s)
  public let applyDuration: TimeInterval    // time spent applying to TextStorage (s)

  // Instruction application counts (optimized paths)
  public let deleteCount: Int
  public let insertCount: Int
  public let setAttributesCount: Int
  public let fixAttributesCount: Int

  public init(
    duration: TimeInterval,
    dirtyNodes: Int,
    rangesAdded: Int,
    rangesDeleted: Int,
    treatedAllNodesAsDirty: Bool,
    pathLabel: String? = nil,
    planningDuration: TimeInterval = 0,
    applyDuration: TimeInterval = 0,
    deleteCount: Int = 0,
    insertCount: Int = 0,
    setAttributesCount: Int = 0,
    fixAttributesCount: Int = 0
  ) {
    self.duration = duration
    self.dirtyNodes = dirtyNodes
    self.rangesAdded = rangesAdded
    self.rangesDeleted = rangesDeleted
    self.treatedAllNodesAsDirty = treatedAllNodesAsDirty
    self.pathLabel = pathLabel
    self.planningDuration = planningDuration
    self.applyDuration = applyDuration
    self.deleteCount = deleteCount
    self.insertCount = insertCount
    self.setAttributesCount = setAttributesCount
    self.fixAttributesCount = fixAttributesCount
  }
}

public enum EditorMetric {
  case reconcilerRun(ReconcilerMetric)
}

@MainActor
public final class NullEditorMetricsContainer: EditorMetricsContainer {
  public init() {}

  public func record(_ metric: EditorMetric) {}

  public func resetMetrics() {}
}
