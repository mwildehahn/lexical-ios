/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class ReconcilerMetricsTests: XCTestCase {

  func testDefaultReconcilerMetricsCollector() throws {
    let collector = DefaultReconcilerMetricsCollector()

    // Initially should have no metrics
    XCTAssertEqual(collector.metrics.count, 0)

    // Add a metric
    let metric1 = ReconcilerMetric(
      duration: 0.001,
      dirtyNodes: 5,
      rangesAdded: 3,
      rangesDeleted: 2,
      treatedAllNodesAsDirty: false
    )
    collector.record(metric1)

    XCTAssertEqual(collector.metrics.count, 1)
    XCTAssertEqual(collector.metrics.first?.dirtyNodes, 5)
  }

  func testMetricsCollectorMaxCapacity() throws {
    let collector = DefaultReconcilerMetricsCollector(maxMetrics: 5)

    // Add more than max metrics
    for i in 0..<10 {
      let metric = ReconcilerMetric(
        duration: Double(i) * 0.001,
        dirtyNodes: i,
        rangesAdded: i,
        rangesDeleted: 0,
        treatedAllNodesAsDirty: false
      )
      collector.record(metric)
    }

    // Should only keep the last 5
    XCTAssertEqual(collector.metrics.count, 5)
    XCTAssertEqual(collector.metrics.first?.dirtyNodes, 5) // First should be metric 5
    XCTAssertEqual(collector.metrics.last?.dirtyNodes, 9)  // Last should be metric 9
  }

  func testMetricsSummary() throws {
    let collector = DefaultReconcilerMetricsCollector()

    // Add several metrics
    let metrics = [
      ReconcilerMetric(duration: 0.001, dirtyNodes: 5, rangesAdded: 3, rangesDeleted: 2, treatedAllNodesAsDirty: false),
      ReconcilerMetric(duration: 0.002, dirtyNodes: 10, rangesAdded: 5, rangesDeleted: 3, treatedAllNodesAsDirty: true),
      ReconcilerMetric(duration: 0.003, dirtyNodes: 15, rangesAdded: 7, rangesDeleted: 4, treatedAllNodesAsDirty: false)
    ]

    for metric in metrics {
      collector.record(metric)
    }

    let summary = collector.summary
    XCTAssertEqual(summary.totalMetrics, 3)
    XCTAssertEqual(summary.averageDuration, 0.002, accuracy: 0.0001)
    XCTAssertEqual(summary.minDuration, 0.001, accuracy: 0.0001)
    XCTAssertEqual(summary.maxDuration, 0.003, accuracy: 0.0001)
  }

  func testMetricsSummaryWithFallback() throws {
    let collector = DefaultReconcilerMetricsCollector()

    // Add metrics with different types
    collector.record(ReconcilerMetric(
      duration: 0.001,
      dirtyNodes: 5,
      rangesAdded: 3,
      rangesDeleted: 2,
      treatedAllNodesAsDirty: false,
      fallbackTriggered: false,
      reconcilerType: .optimized
    ))

    collector.record(ReconcilerMetric(
      duration: 0.002,
      dirtyNodes: 10,
      rangesAdded: 5,
      rangesDeleted: 3,
      treatedAllNodesAsDirty: true,
      fallbackTriggered: true,
      reconcilerType: .hybrid
    ))

    collector.record(ReconcilerMetric(
      duration: 0.003,
      dirtyNodes: 15,
      rangesAdded: 7,
      rangesDeleted: 4,
      treatedAllNodesAsDirty: false,
      fallbackTriggered: false,
      reconcilerType: .legacy
    ))

    let summary = collector.summary
    XCTAssertEqual(summary.fallbackRate, 1.0 / 3.0, accuracy: 0.01) // 1 out of 3 had fallback
    XCTAssertEqual(summary.optimizedUsageRate, 1.0 / 3.0, accuracy: 0.01) // 1 out of 3 was optimized
  }

  func testMetricsReset() throws {
    let collector = DefaultReconcilerMetricsCollector()

    // Add some metrics
    collector.record(ReconcilerMetric(
      duration: 0.001,
      dirtyNodes: 5,
      rangesAdded: 3,
      rangesDeleted: 2,
      treatedAllNodesAsDirty: false
    ))

    XCTAssertEqual(collector.metrics.count, 1)

    // Reset should clear all metrics
    collector.reset()
    XCTAssertEqual(collector.metrics.count, 0)
  }

  func testEmptyMetricsSummary() throws {
    let collector = DefaultReconcilerMetricsCollector()
    let summary = collector.summary

    // Empty summary should have zero values
    XCTAssertEqual(summary.totalMetrics, 0)
    XCTAssertEqual(summary.averageDuration, 0)
    XCTAssertEqual(summary.minDuration, 0)
    XCTAssertEqual(summary.maxDuration, 0)
    XCTAssertEqual(summary.p50Duration, 0)
    XCTAssertEqual(summary.p95Duration, 0)
    XCTAssertEqual(summary.p99Duration, 0)
    XCTAssertEqual(summary.fallbackRate, 0)
    XCTAssertEqual(summary.optimizedUsageRate, 0)
  }

  func testPercentileCalculations() throws {
    let collector = DefaultReconcilerMetricsCollector()

    // Add 100 metrics with varying durations
    for i in 1...100 {
      collector.record(ReconcilerMetric(
        duration: Double(i) * 0.001,
        dirtyNodes: i,
        rangesAdded: i,
        rangesDeleted: 0,
        treatedAllNodesAsDirty: false
      ))
    }

    let summary = collector.summary
    // P50 should be around the 50th value (0.050)
    XCTAssertEqual(summary.p50Duration, 0.050, accuracy: 0.001)
    // P95 should be around the 95th value (0.095)
    XCTAssertEqual(summary.p95Duration, 0.095, accuracy: 0.001)
    // P99 should be around the 99th value (0.099)
    XCTAssertEqual(summary.p99Duration, 0.099, accuracy: 0.001)
  }

  func testMetricDescription() throws {
    let metric = ReconcilerMetric(
      duration: 0.001234,
      dirtyNodes: 5,
      rangesAdded: 3,
      rangesDeleted: 2,
      treatedAllNodesAsDirty: false,
      nodesProcessed: 10,
      textStorageMutations: 5,
      fenwickOperations: 2,
      fallbackTriggered: false,
      reconcilerType: .optimized,
      documentSize: 1000,
      nodeCount: 20
    )

    let description = metric.description
    XCTAssertTrue(description.contains("optimized"))
    XCTAssertTrue(description.contains("1.234ms"))
    XCTAssertTrue(description.contains("dirtyNodes: 5"))
  }
}