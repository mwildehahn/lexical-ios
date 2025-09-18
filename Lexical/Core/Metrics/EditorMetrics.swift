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
}

public enum ReconcilerFallbackReason: String {
  case structuralChange
  case decoratorMutation
  case unsupportedDelta
  case sanityCheckFailed
}

public struct ReconcilerMetric {
  public let duration: TimeInterval
  public let dirtyNodes: Int
  public let rangesAdded: Int
  public let rangesDeleted: Int
  public let treatedAllNodesAsDirty: Bool
  public let nodesVisited: Int
  public let insertedCharacters: Int
  public let deletedCharacters: Int
  public let fallbackReason: ReconcilerFallbackReason?

  public init(
    duration: TimeInterval,
    dirtyNodes: Int,
    rangesAdded: Int,
    rangesDeleted: Int,
    treatedAllNodesAsDirty: Bool,
    nodesVisited: Int,
    insertedCharacters: Int,
    deletedCharacters: Int,
    fallbackReason: ReconcilerFallbackReason?
  ) {
    self.duration = duration
    self.dirtyNodes = dirtyNodes
    self.rangesAdded = rangesAdded
    self.rangesDeleted = rangesDeleted
    self.treatedAllNodesAsDirty = treatedAllNodesAsDirty
    self.nodesVisited = nodesVisited
    self.insertedCharacters = insertedCharacters
    self.deletedCharacters = deletedCharacters
    self.fallbackReason = fallbackReason
  }
}

public enum EditorMetric {
  case reconcilerRun(ReconcilerMetric)
}

public final class NullEditorMetricsContainer: EditorMetricsContainer {
  public init() {}

  public func record(_ metric: EditorMetric) {}

  public func resetMetrics() {}
}
