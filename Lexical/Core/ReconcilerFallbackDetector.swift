/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Detects when the optimized reconciler should fallback to full reconciliation
@MainActor
internal class ReconcilerFallbackDetector {

  private let editor: Editor
  private var fallbackMetrics: FallbackMetrics

  // MARK: - Configuration

  private struct FallbackThresholds {
    static let maxDeltasPerBatch = 100
    static let maxStructuralChanges = 50
    static let maxConsecutiveFailures = 3
    static let maxTimeSinceLastSuccess: TimeInterval = 30.0 // seconds
    static let maxMemoryPressure = 0.8 // 80% of available memory
  }

  // MARK: - Initialization

  init(editor: Editor) {
    self.editor = editor
    self.fallbackMetrics = FallbackMetrics()
  }

  // MARK: - Fallback Detection

  /// Determine if we should fallback to full reconciliation
  func shouldFallbackToFullReconciliation(
    for deltas: [ReconcilerDelta],
    textStorage: NSTextStorage,
    context: ReconcilerContext
  ) -> FallbackDecision {

    // Check various fallback conditions
    let checks: [FallbackCheck] = [
      checkDeltaBatchSize(deltas),
      checkStructuralChanges(deltas),
      checkConsecutiveFailures(),
      checkTimeSinceLastSuccess(),
      checkMemoryPressure(),
      checkComplexTransformations(deltas),
      checkDebugMode(),
      checkTextStorageIntegrity(textStorage),
      checkDeltaRangeValidity(deltas, textStorage: textStorage)
    ]

    // Evaluate all checks
    for check in checks {
      if case .fallback(let reason) = check {
        recordFallbackDecision(reason: reason, context: context)
        return .fallback(reason: reason)
      }
    }

    // All checks passed, use optimized reconciliation
    fallbackMetrics.recordSuccessfulOptimization()
    return .useOptimized
  }

  /// Reset fallback state after successful operations
  func resetFallbackState() {
    fallbackMetrics.consecutiveFailures = 0
    fallbackMetrics.lastSuccessfulOptimization = Date()
  }

  /// Record a failed optimization attempt
  func recordOptimizationFailure(reason: String) {
    fallbackMetrics.consecutiveFailures += 1
    fallbackMetrics.totalFailures += 1
    fallbackMetrics.lastFailureReason = reason
    fallbackMetrics.lastFailureTime = Date()
  }

  // MARK: - Individual Checks

  private func checkDeltaBatchSize(_ deltas: [ReconcilerDelta]) -> FallbackCheck {
    if deltas.count > FallbackThresholds.maxDeltasPerBatch {
      return .fallback("Too many deltas in batch: \(deltas.count) > \(FallbackThresholds.maxDeltasPerBatch)")
    }
    return .continueOptimization
  }

  private func checkStructuralChanges(_ deltas: [ReconcilerDelta]) -> FallbackCheck {
    let structuralChanges = countStructuralChanges(deltas)
    if structuralChanges > FallbackThresholds.maxStructuralChanges {
      return .fallback("Too many structural changes: \(structuralChanges) > \(FallbackThresholds.maxStructuralChanges)")
    }
    return .continueOptimization
  }

  private func checkConsecutiveFailures() -> FallbackCheck {
    if fallbackMetrics.consecutiveFailures >= FallbackThresholds.maxConsecutiveFailures {
      return .fallback("Too many consecutive failures: \(fallbackMetrics.consecutiveFailures)")
    }
    return .continueOptimization
  }

  private func checkTimeSinceLastSuccess() -> FallbackCheck {
    let timeSinceSuccess = Date().timeIntervalSince(fallbackMetrics.lastSuccessfulOptimization)
    if timeSinceSuccess > FallbackThresholds.maxTimeSinceLastSuccess {
      return .fallback("Too long since last successful optimization: \(timeSinceSuccess)s")
    }
    return .continueOptimization
  }

  private func checkMemoryPressure() -> FallbackCheck {
    let memoryPressure = getCurrentMemoryPressure()
    if memoryPressure > FallbackThresholds.maxMemoryPressure {
      return .fallback("High memory pressure: \(memoryPressure)")
    }
    return .continueOptimization
  }

  private func checkComplexTransformations(_ deltas: [ReconcilerDelta]) -> FallbackCheck {
    if hasComplexTransformations(deltas) {
      return .fallback("Complex transformations detected that require full reconciliation")
    }
    return .continueOptimization
  }

  private func checkDebugMode() -> FallbackCheck {
    #if DEBUG
    if editor.featureFlags.reconcilerSanityCheck {
      return .fallback("Debug mode enabled - using full reconciliation for validation")
    }
    #endif
    return .continueOptimization
  }

  private func checkTextStorageIntegrity(_ textStorage: NSTextStorage) -> FallbackCheck {
    // Basic integrity checks
    if textStorage.length < 0 {
      return .fallback("Invalid TextStorage length: \(textStorage.length)")
    }

    // Check for attribute consistency
    if hasInconsistentAttributes(textStorage) {
      return .fallback("TextStorage has inconsistent attributes")
    }

    return .continueOptimization
  }

  // MARK: - Helper Methods

  private func countStructuralChanges(_ deltas: [ReconcilerDelta]) -> Int {
    return deltas.count { delta in
      switch delta.type {
      case .nodeInsertion, .nodeDeletion:
        return true
      case .textUpdate, .attributeChange:
        return false
      }
    }
  }

  private func getCurrentMemoryPressure() -> Double {
    #if canImport(Darwin)
    let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
    guard totalMemory > 0 else { return 0 }

    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
        task_info(
          mach_task_self_,
          task_flavor_t(TASK_VM_INFO),
          $0,
          &vmCount
        )
      }
    }

    if vmResult == KERN_SUCCESS {
      let footprintRatio = Double(vmInfo.phys_footprint) / totalMemory
      return min(1.0, max(0.0, footprintRatio))
    }

    var basicInfo = mach_task_basic_info()
    var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let basicResult = withUnsafeMutablePointer(to: &basicInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
        task_info(
          mach_task_self_,
          task_flavor_t(MACH_TASK_BASIC_INFO),
          $0,
          &basicCount
        )
      }
    }

    if basicResult == KERN_SUCCESS {
      let residentRatio = Double(basicInfo.resident_size) / totalMemory
      return min(1.0, max(0.0, residentRatio))
    }
    #endif

    return 0.0 // Default to no pressure if we can't measure
  }

  private func hasComplexTransformations(_ deltas: [ReconcilerDelta]) -> Bool {
    // Check for transformations that are difficult to handle incrementally
    for delta in deltas {
      switch delta.type {
      case .nodeInsertion(_, let insertionData, _):
        // Check if this is a complex node type that's hard to handle incrementally
        if isComplexNodeType(insertionData.nodeKey) {
          return true
        }
      case .nodeDeletion(let nodeKey, _):
        if isComplexNodeType(nodeKey) {
          return true
        }
      default:
        break
      }
    }

    return false
  }

  private func isComplexNodeType(_ nodeKey: NodeKey) -> Bool {
    guard let node = getNodeByKey(key: nodeKey) else { return false }

    // List nodes, decorator nodes, etc. might be complex
    // Check if the node type name contains indicators of complexity
    return String(describing: type(of: node)).contains("List") || String(describing: type(of: node)).contains("Decorator")
  }

  /// Check if delta ranges are valid for the given text storage
  private func checkDeltaRangeValidity(_ deltas: [ReconcilerDelta], textStorage: NSTextStorage) -> FallbackCheck {
    let textStorageLength = textStorage.length

    for delta in deltas {
      switch delta.type {
      case .textUpdate(_, _, let range):
        if range.location < 0 || range.location > textStorageLength ||
           range.location + range.length > textStorageLength {
          return .fallback("Invalid range in textUpdate delta: \(range) for textStorage length \(textStorageLength)")
        }
      case .nodeDeletion(_, let range):
        if range.location < 0 || range.location > textStorageLength ||
           range.location + range.length > textStorageLength {
          return .fallback("Invalid range in nodeDeletion delta: \(range) for textStorage length \(textStorageLength)")
        }
      case .attributeChange(_, _, let range):
        if range.location < 0 || range.location > textStorageLength ||
           range.location + range.length > textStorageLength {
          return .fallback("Invalid range in attributeChange delta: \(range) for textStorage length \(textStorageLength)")
        }
      default:
        // Other delta types don't have ranges to validate
        break
      }
    }

    return .continueOptimization
  }

  private func hasInconsistentAttributes(_ textStorage: NSTextStorage) -> Bool {
    // Check for basic attribute consistency
    // This is a simplified check - a real implementation would be more thorough
    if textStorage.length == 0 { return false }

    var hasInconsistency = false

    textStorage.enumerateAttributes(
      in: NSRange(location: 0, length: min(textStorage.length, 1000)), // Sample first 1000 chars
      options: []
    ) { attributes, range, stop in
      // Check for nil attributes in unexpected places
      if attributes.isEmpty && range.length > 0 {
        // This might indicate corruption
        hasInconsistency = true
        stop.pointee = true
      }
    }

    return hasInconsistency
  }

  private func recordFallbackDecision(reason: String, context: ReconcilerContext) {
    fallbackMetrics.totalFallbacks += 1
    fallbackMetrics.lastFallbackReason = reason
    fallbackMetrics.lastFallbackTime = Date()

    // Log for debugging if metrics enabled
    if editor.featureFlags.reconcilerMetrics {
      editor.log(.reconciler, .warning, "Fallback to full reconciliation: \(reason)")
    }
  }
}

// MARK: - Supporting Types

internal enum FallbackDecision {
  case useOptimized
  case fallback(reason: String)
}

private enum FallbackCheck {
  case continueOptimization
  case fallback(String)
}

internal struct ReconcilerContext {
  let updateSource: String
  let nodeCount: Int
  let textStorageLength: Int
  let timestamp: Date

  init(updateSource: String, nodeCount: Int, textStorageLength: Int, timestamp: Date = Date()) {
    self.updateSource = updateSource
    self.nodeCount = nodeCount
    self.textStorageLength = textStorageLength
    self.timestamp = timestamp
  }
}

private struct FallbackMetrics {
  var consecutiveFailures: Int = 0
  var totalFailures: Int = 0
  var totalFallbacks: Int = 0
  var totalOptimizations: Int = 0
  var lastSuccessfulOptimization: Date = Date()
  var lastFailureTime: Date?
  var lastFailureReason: String?
  var lastFallbackTime: Date?
  var lastFallbackReason: String?

  mutating func recordSuccessfulOptimization() {
    consecutiveFailures = 0
    totalOptimizations += 1
    lastSuccessfulOptimization = Date()
  }
}
