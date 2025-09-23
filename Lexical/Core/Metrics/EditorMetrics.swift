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
    self.documentSize = documentSize
    self.nodeCount = nodeCount
  }
}

public struct OptimizedReconcilerMetric {
  public let deltaCount: Int
  public let fenwickOperations: Int
  public let nodeCount: Int
  public let textStorageLength: Int
  public let timestamp: Date
  public let duration: TimeInterval

  public init(
    deltaCount: Int,
    fenwickOperations: Int,
    nodeCount: Int,
    textStorageLength: Int,
    timestamp: Date,
    duration: TimeInterval = 0
  ) {
    self.deltaCount = deltaCount
    self.fenwickOperations = fenwickOperations
    self.nodeCount = nodeCount
    self.textStorageLength = textStorageLength
    self.timestamp = timestamp
    self.duration = duration
  }
}

public struct DeltaApplicationMetric {
  public let deltaType: String
  public let fenwickOperations: Int
  public let lengthDelta: Int
  public let timestamp: Date

  public init(
    deltaType: String,
    fenwickOperations: Int,
    lengthDelta: Int,
    timestamp: Date
  ) {
    self.deltaType = deltaType
    self.fenwickOperations = fenwickOperations
    self.lengthDelta = lengthDelta
    self.timestamp = timestamp
  }
}

public enum EditorMetric {
  case reconcilerRun(ReconcilerMetric)
  case optimizedReconcilerRun(OptimizedReconcilerMetric)
  case deltaApplication(DeltaApplicationMetric)
}

public final class NullEditorMetricsContainer: EditorMetricsContainer {
  public var metricsData: [String: Any] = [:]

  public init() {}

  public func record(_ metric: EditorMetric) {}

  public func resetMetrics() {}
}
