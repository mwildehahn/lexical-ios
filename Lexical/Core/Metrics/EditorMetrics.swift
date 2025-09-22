/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol EditorMetricsContainer: AnyObject {
  func record(_ metric: EditorMetric)
  func resetMetrics()
  var metricsData: [String: Any] { get set }
}

public struct ReconcilerMetric {
  public let duration: TimeInterval
  public let dirtyNodes: Int
  public let rangesAdded: Int
  public let rangesDeleted: Int
  public let treatedAllNodesAsDirty: Bool
  public let nodesProcessed: Int
  public let textStorageMutations: Int
  public let fenwickOperations: Int
  public let fallbackTriggered: Bool
  public let reconcilerType: ReconcilerType
  public let documentSize: Int
  public let nodeCount: Int

  public init(
    duration: TimeInterval,
    dirtyNodes: Int,
    rangesAdded: Int,
    rangesDeleted: Int,
    treatedAllNodesAsDirty: Bool,
    nodesProcessed: Int = 0,
    textStorageMutations: Int = 0,
    fenwickOperations: Int = 0,
    fallbackTriggered: Bool = false,
    reconcilerType: ReconcilerType = .legacy,
    documentSize: Int = 0,
    nodeCount: Int = 0
  ) {
    self.duration = duration
    self.dirtyNodes = dirtyNodes
    self.rangesAdded = rangesAdded
    self.rangesDeleted = rangesDeleted
    self.treatedAllNodesAsDirty = treatedAllNodesAsDirty
    self.nodesProcessed = nodesProcessed
    self.textStorageMutations = textStorageMutations
    self.fenwickOperations = fenwickOperations
    self.fallbackTriggered = fallbackTriggered
    self.reconcilerType = reconcilerType
    self.documentSize = documentSize
    self.nodeCount = nodeCount
  }
}

public enum ReconcilerType {
  case legacy
  case optimized
  case hybrid
}

public enum EditorMetric {
  case reconcilerRun(ReconcilerMetric)
}

public final class NullEditorMetricsContainer: EditorMetricsContainer {
  public var metricsData: [String: Any] = [:]

  public init() {}

  public func record(_ metric: EditorMetric) {}

  public func resetMetrics() {}
}
