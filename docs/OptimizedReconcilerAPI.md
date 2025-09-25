# Optimized Reconciler API Documentation

## Overview

The Optimized Reconciler is a high-performance alternative to the legacy reconciliation system in Lexical iOS. It uses a Fenwick tree-based approach to achieve O(log n) performance for document updates, replacing the O(n) performance of the legacy system.

## Architecture

### Core Components

#### 1. OptimizedReconciler
The main entry point for optimized reconciliation.

```swift
@MainActor
internal enum OptimizedReconciler {
  static func reconcile(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws
}
```

The reconciler does not auto‑fallback; choose mode via `FeatureFlags.reconcilerMode` or use `.darkLaunch` to run optimized and legacy back‑to‑back in debug scenarios.

#### 2. FenwickTree
A binary indexed tree for efficient range sum queries and updates.

```swift
@MainActor
internal class FenwickTree {
    func update(index: Int, delta: Int)  // O(log n)
    func query(index: Int) -> Int        // O(log n) prefix sum
    func rangeQuery(left: Int, right: Int) -> Int  // O(log n)
    func findPosition(targetOffset: Int) -> Int?  // O(log n)
}
```

**Key Operations:**
- `update`: Adjusts the length at a specific index
- `query`: Gets cumulative length up to an index
- `rangeQuery`: Gets total length in a range
- `findPosition`: Finds index for a text offset

#### 3. ReconcilerDelta
Represents a single change to be applied to the text storage.

```swift
enum ReconcilerDeltaType {
  case textUpdate(nodeKey: NodeKey, newText: String, range: NSRange)
  case nodeInsertion(nodeKey: NodeKey, insertionData: NodeInsertionData, location: Int)
  case nodeDeletion(nodeKey: NodeKey, range: NSRange)
  case attributeChange(nodeKey: NodeKey, attributes: [NSAttributedString.Key: Any], range: NSRange)
}
```
Associated types:
- `NodeInsertionData(preamble: NSAttributedString, content: NSAttributedString, postamble: NSAttributedString, nodeKey: NodeKey)`
- `DeltaBatch(deltas: [ReconcilerDelta], batchMetadata: BatchMetadata)`
- `BatchMetadata(expectedTextStorageLength: Int, isFreshDocument: Bool)`

## Feature Flags

Preferred API (2025-09-25):

```swift
// New structured flags
let flags = FeatureFlags(
  reconcilerMode: .optimized, // .legacy, .optimized, .darkLaunch
  diagnostics: Diagnostics(
    selectionParity: false,   // gate parity-only diagnostics
    sanityChecks: false,      // invariants checker
    metrics: true,            // collect performance metrics
    verboseLogs: false        // verbose debug prints
  )
)

let editorConfig = EditorConfig(
  theme: theme,
  plugins: plugins,
  featureFlags: flags
)
```

Back‑compat initializer (still supported):

```swift
// Legacy convenience init (maps to reconcilerMode/diagnostics internally)
let flags = FeatureFlags(
  optimizedReconciler: true,
  reconcilerMetrics: true
)
```

Dark‑launch example (run optimized, then restore and run legacy invisibly):

```swift
let flags = FeatureFlags(reconcilerMode: .darkLaunch,
                         diagnostics: Diagnostics(metrics: true))
```

## Performance Characteristics

### Time Complexity
| Operation | Legacy | Optimized |
|-----------|--------|-----------|
| Top insertion | O(n) | O(log n) |
| Middle edit | O(n) | O(log n) |
| Range update | O(n) | O(log n) |
| Offset lookup | O(n) | O(log n) |

### Space Complexity
- Fenwick tree: O(n) additional memory where n = number of nodes
- Delta batch: O(k) where k = number of changes
- Anchor storage: O(n) when anchors enabled

## Usage Examples

### Basic Setup

```swift
// Create editor with optimized reconciler
let featureFlags = FeatureFlags(optimizedReconciler: true)
let editorConfig = EditorConfig(
    theme: Theme(),
    plugins: [],
    featureFlags: featureFlags
)
let lexicalView = LexicalView(editorConfig: editorConfig)
```

### Monitoring Performance

```swift
// Enable metrics collection
let metricsContainer = MyMetricsContainer()
let editorConfig = EditorConfig(
    theme: Theme(),
    plugins: [],
    metricsContainer: metricsContainer,
    featureFlags: FeatureFlags(
        optimizedReconciler: true,
        reconcilerMetrics: true
    )
)

// Metrics will be reported via EditorMetric enum:
// - .reconcilerRun(ReconcilerMetric)
// - .optimizedReconcilerRun(OptimizedReconcilerMetric)
```

### Delta Application

`TextStorageDeltaApplier` applies a batch of deltas and returns a result:

```swift
enum DeltaApplicationResult {
  case success(appliedDeltas: Int, fenwickTreeUpdates: Int)
  case partialSuccess(appliedDeltas: Int, failedDeltas: [ReconcilerDelta], reason: String)
  case failure(reason: String)
}

final class TextStorageDeltaApplier {
  func applyDeltaBatch(_ batch: DeltaBatch, to textStorage: NSTextStorage) -> DeltaApplicationResult
}
```

Notes:
- Fresh documents preserve generator order; otherwise deltas are applied in a stable order that avoids index drift.
- Fenwick updates reflect text content only (preamble/postamble excluded).

## Integration Points

### Editor Integration

The optimized reconciler integrates at these points:

1. **Editor.beginUpdate()**: Initializes Fenwick tree if needed
2. **Reconciler.updateEditorState()**: Chooses between optimized and legacy paths
3. **Editor metrics**: Reports performance data

### TextStorage Integration

The `TextStorageDeltaApplier` applies deltas directly to NSTextStorage:

```swift
class TextStorageDeltaApplier {
    func applyDelta(
        delta: ReconcilerDelta,
        textStorage: NSTextStorage,
        fenwickTree: FenwickTree
    )
}
```

## Debugging

### Enable Debug Logging

```swift
editor.log(.reconciler, .message, "Reconciler message")
```

### Diagnostics & Logging

- Enable metrics via `diagnostics.metrics` and read `EditorMetric` events.
- Verbose debug prints are gated by `diagnostics.verboseLogs`.
- Parity diagnostics are gated by `diagnostics.selectionParity` and should be used only in focused tests.

### Performance Comparison

Use the `PerformanceTestViewController` in LexicalPlayground to compare legacy vs optimized performance with real-time metrics.

## Best Practices

1. **Start with Feature Flag Off**: Test thoroughly before enabling in production
2. **Monitor Metrics**: Track durations and Fenwick ops; watch for outliers
3. **Batch Updates**: Group related changes in single `editor.update()` calls
4. **Large Changes**: Prefer chunking huge, unrelated structural mutations
5. **Test with Large Documents**: Ensure performance scales as expected

## Limitations

- Marked text operations (IME) are supported via `markedTextOperation` handling in reconcile().
- Ensure custom plugins that manipulate TextStorage directly are audited for optimized mode.

## Migration Guide

See [MigrationGuide.md](./MigrationGuide.md) for detailed migration instructions.
