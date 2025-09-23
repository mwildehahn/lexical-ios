/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Protocol for collecting and analyzing reconciler metrics
@MainActor
public protocol ReconcilerMetricsCollector: AnyObject {
  /// Record a new reconciler metric
  func record(_ metric: ReconcilerMetric)

  /// Get all recorded metrics
  var metrics: [ReconcilerMetric] { get }

  /// Get summary statistics
  var summary: ReconcilerMetricsSummary { get }

  /// Clear all recorded metrics
  func reset()
}

/// Summary statistics for reconciler performance
public struct ReconcilerMetricsSummary {
  public let totalMetrics: Int
  public let averageDuration: TimeInterval
  public let minDuration: TimeInterval
  public let maxDuration: TimeInterval
  public let p50Duration: TimeInterval
  public let p95Duration: TimeInterval
  public let p99Duration: TimeInterval
  public let averageNodesProcessed: Double
  public let averageTextStorageMutations: Double

  public init(metrics: [ReconcilerMetric]) {
    self.totalMetrics = metrics.count

    guard !metrics.isEmpty else {
      self.averageDuration = 0
      self.minDuration = 0
      self.maxDuration = 0
      self.p50Duration = 0
      self.p95Duration = 0
      self.p99Duration = 0
      self.averageNodesProcessed = 0
      self.averageTextStorageMutations = 0
      return
    }

    let durations = metrics.map(\.duration).sorted()
    self.averageDuration = durations.reduce(0, +) / Double(durations.count)
    self.minDuration = durations.first ?? 0
    self.maxDuration = durations.last ?? 0

    self.p50Duration = Self.percentile(durations, 0.50)
    self.p95Duration = Self.percentile(durations, 0.95)
    self.p99Duration = Self.percentile(durations, 0.99)

    self.averageNodesProcessed = metrics.map { Double($0.nodesProcessed) }.reduce(0, +) / Double(metrics.count)
    self.averageTextStorageMutations = metrics.map { Double($0.textStorageMutations) }.reduce(0, +) / Double(metrics.count)
  }

  private static func percentile(_ sortedArray: [TimeInterval], _ percentile: Double) -> TimeInterval {
    guard !sortedArray.isEmpty else { return 0 }
    let index = Int(Double(sortedArray.count - 1) * percentile)
    return sortedArray[index]
  }
}

/// Default implementation of ReconcilerMetricsCollector
@MainActor
public final class DefaultReconcilerMetricsCollector: ReconcilerMetricsCollector {
  private var _metrics: [ReconcilerMetric] = []
  private let maxMetrics: Int

  public init(maxMetrics: Int = 1000) {
    self.maxMetrics = maxMetrics
  }

  public func record(_ metric: ReconcilerMetric) {
    _metrics.append(metric)

    // Keep only the last N metrics to avoid unbounded memory growth
    if _metrics.count > maxMetrics {
      _metrics.removeFirst(_metrics.count - maxMetrics)
    }
  }

  public var metrics: [ReconcilerMetric] {
    return _metrics
  }

  public var summary: ReconcilerMetricsSummary {
    return ReconcilerMetricsSummary(metrics: _metrics)
  }

  public func reset() {
    _metrics.removeAll()
  }
}

// MARK: - Editor Integration

extension EditorMetricsContainer {
  /// Get or create the reconciler metrics collector
  @MainActor
  public var reconcilerMetrics: ReconcilerMetricsCollector {
    if let existing = self.metricsData["reconcilerMetrics"] as? ReconcilerMetricsCollector {
      return existing
    }
    let collector = DefaultReconcilerMetricsCollector()
    self.metricsData["reconcilerMetrics"] = collector
    return collector
  }
}

// MARK: - Debug Output

extension ReconcilerMetric: CustomStringConvertible {
  public var description: String {
    return """
    ReconcilerMetric(
      duration: \(String(format: "%.3fms", duration * 1000)),
      dirtyNodes: \(dirtyNodes),
      nodesProcessed: \(nodesProcessed),
      rangesAdded: \(rangesAdded),
      rangesDeleted: \(rangesDeleted),
      mutations: \(textStorageMutations),
      documentSize: \(documentSize),
      nodeCount: \(nodeCount)
    )
    """
  }
}

extension ReconcilerMetricsSummary: CustomStringConvertible {
  public var description: String {
    return """
    ReconcilerMetricsSummary(
      totalMetrics: \(totalMetrics),
      avgDuration: \(String(format: "%.3fms", averageDuration * 1000)),
      p50: \(String(format: "%.3fms", p50Duration * 1000)),
      p95: \(String(format: "%.3fms", p95Duration * 1000)),
      p99: \(String(format: "%.3fms", p99Duration * 1000))
    )
    """
  }
}
