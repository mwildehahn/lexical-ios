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
    static func attemptOptimizedReconciliation(
        currentEditorState: EditorState,
        pendingEditorState: EditorState,
        editor: Editor,
        shouldReconcileSelection: Bool,
        markedTextOperation: MarkedTextOperation?
    ) throws -> Bool
}
```

**Parameters:**
- `currentEditorState`: The current state of the editor
- `pendingEditorState`: The new state to reconcile to
- `editor`: The editor instance
- `shouldReconcileSelection`: Whether to reconcile selection changes
- `markedTextOperation`: Optional marked text operation (IME)

**Returns:** `true` if optimized reconciliation was used, `false` if it fell back to legacy

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
    case attributeUpdate(nodeKey: NodeKey, attributes: [NSAttributedString.Key: Any], range: NSRange)
    case anchorUpdate(nodeKey: NodeKey, preambleLocation: Int, postambleLocation: Int)
}
```

#### 4. ReconcilerFallbackDetector
Determines when to fallback to legacy reconciliation for safety.

```swift
@MainActor
internal class ReconcilerFallbackDetector {
    func shouldFallbackToFullReconciliation(
        for deltas: [ReconcilerDelta],
        textStorage: NSTextStorage,
        context: ReconcilerContext
    ) -> FallbackDecision
}
```

**Fallback Triggers:**
- More than 100 deltas in a batch
- More than 50 structural changes
- Consecutive optimization failures
- Anchor corruption detected
- Memory pressure conditions

## Feature Flags

Enable/disable the optimized reconciler using feature flags:

```swift
let featureFlags = FeatureFlags(
    optimizedReconciler: true,        // Enable optimized path
    reconcilerMetrics: true,           // Collect performance metrics
    anchorBasedReconciliation: false   // Use node anchors (experimental)
)

let editorConfig = EditorConfig(
    theme: theme,
    plugins: plugins,
    featureFlags: featureFlags
)
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

### Custom Fallback Thresholds

The fallback detector uses these default thresholds:

```swift
struct FallbackThresholds {
    static let maxDeltasPerBatch = 100
    static let maxStructuralChanges = 50
    static let maxConsecutiveFailures = 3
}
```

To customize, modify `ReconcilerFallbackDetector.swift`.

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
editor.log(.reconciler, .info, "Reconciler message")
```

### Monitor Fallback Reasons

Check metrics for `OptimizedReconcilerMetric.fallbackReason` to understand why fallbacks occur.

### Performance Comparison

Use the `PerformanceTestViewController` in LexicalPlayground to compare legacy vs optimized performance with real-time metrics.

## Best Practices

1. **Start with Feature Flag Off**: Test thoroughly before enabling in production
2. **Monitor Metrics**: Watch for excessive fallbacks
3. **Batch Updates**: Group related changes in single `editor.update()` calls
4. **Avoid Massive Structural Changes**: These trigger fallback for safety
5. **Test with Large Documents**: Ensure performance scales as expected

## Limitations

- Marked text operations (IME) always use legacy path
- Very large batch operations (>100 nodes) trigger fallback
- Anchor-based reconciliation is experimental
- Some plugins may not be optimized-path aware

## Migration Guide

See [MigrationGuide.md](./MigrationGuide.md) for detailed migration instructions.