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
  public let duration: TimeInterval
  public let dirtyNodes: Int
  public let rangesAdded: Int
  public let rangesDeleted: Int
  public let treatedAllNodesAsDirty: Bool

  public init(
    duration: TimeInterval,
    dirtyNodes: Int,
    rangesAdded: Int,
    rangesDeleted: Int,
    treatedAllNodesAsDirty: Bool
  ) {
    self.duration = duration
    self.dirtyNodes = dirtyNodes
    self.rangesAdded = rangesAdded
    self.rangesDeleted = rangesDeleted
    self.treatedAllNodesAsDirty = treatedAllNodesAsDirty
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
