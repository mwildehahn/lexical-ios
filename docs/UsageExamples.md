# Optimized Reconciler Usage Examples

## Table of Contents
1. [Basic Setup](#basic-setup)
2. [Performance Monitoring](#performance-monitoring)
3. [A/B Testing](#ab-testing)
4. [Custom Metrics](#custom-metrics)
5. [Plugin Integration](#plugin-integration)
6. [Advanced Configurations](#advanced-configurations)
7. [Debugging](#debugging)
8. [Performance Benchmarking](#performance-benchmarking)

## Basic Setup

### Simple Enable

```swift
import Lexical
import UIKit

class MyViewController: UIViewController {
    var lexicalView: LexicalView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Enable optimized reconciler
        let featureFlags = FeatureFlags(optimizedReconciler: true)

        let editorConfig = EditorConfig(
            theme: Theme(),
            plugins: [ToolbarPlugin(), HistoryPlugin()],
            featureFlags: featureFlags
        )

        lexicalView = LexicalView(editorConfig: editorConfig)
        view.addSubview(lexicalView)
    }
}
```

### With Error Handling

```swift
class SafeEditorSetup {
    static func createOptimizedEditor() -> LexicalView {
        let featureFlags = FeatureFlags(
            optimizedReconciler: true,
            reconcilerMetrics: true
        )

        let editorConfig = EditorConfig(
            theme: Theme(),
            plugins: [],
            featureFlags: featureFlags
        )

        let lexicalView = LexicalView(editorConfig: editorConfig)

        // Handle potential fallbacks
        lexicalView.editor.registerUpdateListener { _ in
            // Editor updated successfully
        }

        return lexicalView
    }
}
```

## Performance Monitoring

### Basic Metrics Collection

```swift
class PerformanceMonitor: EditorMetricsContainer {
    private var metrics: [EditorMetric] = []

    func record(_ metric: EditorMetric) {
        metrics.append(metric)

        switch metric {
        case .optimizedReconcilerRun(let data):
            logOptimizedMetrics(data)
        case .reconcilerRun(let data):
            logLegacyMetrics(data)
        }
    }

    private func logOptimizedMetrics(_ data: OptimizedReconcilerMetric) {
        print("📊 Optimized Reconciler:")
        print("  Duration: \(data.duration)ms")
        print("  Deltas: \(data.deltasApplied)")
        print("  Fallback: \(data.didFallback)")

        if let fallbackReason = data.fallbackReason {
            print("  Fallback Reason: \(fallbackReason)")
        }
    }

    private func logLegacyMetrics(_ data: ReconcilerMetric) {
        print("📊 Legacy Reconciler:")
        print("  Duration: \(data.duration)ms")
        print("  Nodes: \(data.nodesProcessed)")
    }
}

// Usage
let monitor = PerformanceMonitor()
let editorConfig = EditorConfig(
    theme: Theme(),
    plugins: [],
    metricsContainer: monitor,
    featureFlags: FeatureFlags(
        optimizedReconciler: true,
        reconcilerMetrics: true
    )
)
```

### Advanced Metrics Dashboard

```swift
class MetricsDashboard: EditorMetricsContainer {
    struct PerformanceStats {
        var totalRuns = 0
        var totalDuration: TimeInterval = 0
        var fallbackCount = 0
        var averageDuration: TimeInterval {
            totalRuns > 0 ? totalDuration / Double(totalRuns) : 0
        }
        var fallbackRate: Double {
            totalRuns > 0 ? Double(fallbackCount) / Double(totalRuns) : 0
        }
    }

    private var optimizedStats = PerformanceStats()
    private var legacyStats = PerformanceStats()

    func record(_ metric: EditorMetric) {
        switch metric {
        case .optimizedReconcilerRun(let data):
            optimizedStats.totalRuns += 1
            optimizedStats.totalDuration += data.duration
            if data.didFallback {
                optimizedStats.fallbackCount += 1
            }

        case .reconcilerRun(let data):
            legacyStats.totalRuns += 1
            legacyStats.totalDuration += data.duration
        }
    }

    func printReport() {
        print("\n=== Performance Report ===")
        print("Optimized Reconciler:")
        print("  Runs: \(optimizedStats.totalRuns)")
        print("  Avg Duration: \(String(format: "%.2f", optimizedStats.averageDuration))ms")
        print("  Fallback Rate: \(String(format: "%.1f", optimizedStats.fallbackRate * 100))%")

        if legacyStats.totalRuns > 0 {
            print("\nLegacy Reconciler:")
            print("  Runs: \(legacyStats.totalRuns)")
            print("  Avg Duration: \(String(format: "%.2f", legacyStats.averageDuration))ms")

            let speedup = legacyStats.averageDuration / optimizedStats.averageDuration
            print("\nSpeedup: \(String(format: "%.1fx", speedup))")
        }
    }
}
```

## A/B Testing

### User Bucketing

```swift
class ABTestManager {
    enum TestGroup: String {
        case control = "legacy"
        case treatment = "optimized"
    }

    static func getUserGroup(userId: String) -> TestGroup {
        // Simple hash-based bucketing
        let hash = userId.hashValue
        let bucket = abs(hash) % 100

        // 50/50 split
        return bucket < 50 ? .control : .treatment
    }

    static func createEditorConfig(for userId: String) -> EditorConfig {
        let group = getUserGroup(userId: userId)

        let featureFlags = FeatureFlags(
            optimizedReconciler: group == .treatment,
            reconcilerMetrics: true
        )

        // Track group assignment
        Analytics.track("ab_test.assigned", properties: [
            "user_id": userId,
            "test_group": group.rawValue,
            "feature": "optimized_reconciler"
        ])

        return EditorConfig(
            theme: Theme(),
            plugins: [],
            featureFlags: featureFlags
        )
    }
}
```

### Remote Configuration

```swift
class RemoteFeatureFlags {
    static func fetchFlags(completion: @escaping (FeatureFlags) -> Void) {
        // Fetch from your remote config service
        RemoteConfig.fetch { config in
            let flags = FeatureFlags(
                optimizedReconciler: config["optimized_reconciler_enabled"] as? Bool ?? false,
                reconcilerMetrics: config["collect_metrics"] as? Bool ?? true
            )

            completion(flags)
        }
    }

    static func createEditorWithRemoteFlags(completion: @escaping (LexicalView) -> Void) {
        fetchFlags { flags in
            let editorConfig = EditorConfig(
                theme: Theme(),
                plugins: [],
                featureFlags: flags
            )

            let lexicalView = LexicalView(editorConfig: editorConfig)
            completion(lexicalView)
        }
    }
}
```

## Custom Metrics

### Performance Tracking

```swift
class CustomMetricsCollector: EditorMetricsContainer {
    func record(_ metric: EditorMetric) {
        switch metric {
        case .optimizedReconcilerRun(let data):
            trackOptimizedPerformance(data)
        case .reconcilerRun(let data):
            trackLegacyPerformance(data)
        }
    }

    private func trackOptimizedPerformance(_ data: OptimizedReconcilerMetric) {
        // Send to analytics
        Analytics.track("editor.reconciler.optimized", properties: [
            "duration_ms": data.duration,
            "deltas_applied": data.deltasApplied,
            "nodes_affected": data.nodesAffected,
            "did_fallback": data.didFallback,
            "fallback_reason": data.fallbackReason ?? "none",
            "fenwick_operations": data.fenwickOperations
        ])

        // Alert on performance regression
        if data.duration > 100 {
            Logger.warning("Slow reconciliation: \(data.duration)ms")
        }

        // Monitor fallback rate
        if data.didFallback {
            FallbackMonitor.recordFallback(reason: data.fallbackReason)
        }
    }

    private func trackLegacyPerformance(_ data: ReconcilerMetric) {
        Analytics.track("editor.reconciler.legacy", properties: [
            "duration_ms": data.duration,
            "nodes_processed": data.nodesProcessed,
            "ranges_updated": data.rangesUpdated
        ])
    }
}
```

## Plugin Integration

### Reconciler-Aware Plugin

```swift
class OptimizedPlugin: Plugin {
    private weak var editor: Editor?

    func setUp(editor: Editor) {
        self.editor = editor

        // Adapt behavior based on reconciler
        if editor.featureFlags.optimizedReconciler {
            setupOptimizedHandlers()
        } else {
            setupLegacyHandlers()
        }
    }

    private func setupOptimizedHandlers() {
        editor?.registerUpdateListener { update in
            // Optimized path - rely on deltas
            print("Update with optimized reconciler")
        }
    }

    private func setupLegacyHandlers() {
        editor?.registerUpdateListener { update in
            // Legacy path - full tree reconciliation
            print("Update with legacy reconciler")
        }
    }

    func tearDown() {
        // Cleanup
    }
}
```

## Advanced Configurations

### Custom Fallback Thresholds

```swift
extension ReconcilerFallbackDetector {
    // Override default thresholds (requires modifying source)
    struct CustomThresholds {
        static let maxDeltasPerBatch = 200  // Default: 100
        static let maxStructuralChanges = 100  // Default: 50
        static let maxConsecutiveFailures = 5  // Default: 3
    }
}
```

### Memory-Optimized Configuration

```swift
class MemoryOptimizedSetup {
    static func createEditor(for documentSize: DocumentSize) -> LexicalView {
        let featureFlags: FeatureFlags

        switch documentSize {
        case .small:  // < 100 paragraphs
            featureFlags = FeatureFlags(
                optimizedReconciler: true,
                reconcilerMetrics: true  // Can afford metrics for small docs
            )

        case .medium:  // 100-1000 paragraphs
            featureFlags = FeatureFlags(
                optimizedReconciler: true,
                reconcilerMetrics: false  // Save overhead
            )

        case .large:  // > 1000 paragraphs
            featureFlags = FeatureFlags(
                optimizedReconciler: true,
                reconcilerMetrics: false  // Reduce overhead
            )
            // Consider pagination or virtualization
        }

        let editorConfig = EditorConfig(
            theme: Theme(),
            plugins: [],
            featureFlags: featureFlags
        )

        return LexicalView(editorConfig: editorConfig)
    }

    enum DocumentSize {
        case small, medium, large
    }
}
```

## Debugging

### Debug Logging

```swift
class DebugReconciler {
    static func enableVerboseLogging(for editor: Editor) {
        // Enable all reconciler logs
        editor.logLevel = .verbose

        editor.registerUpdateListener { update in
            print("\n=== Update Debug Info ===")
            print("Dirty Nodes: \(update.dirtyElements.count)")
            print("Dirty Leaves: \(update.dirtyLeaves.count)")

            if let metrics = editor.lastReconcilerMetrics {
                print("Reconciler: \(editor.featureFlags.optimizedReconciler ? "Optimized" : "Legacy")")
                print("Duration: \(metrics.duration)ms")
            }
        }
    }
}
```

### Performance Comparison

```swift
class PerformanceComparator {
    static func compareReconcilers(with content: String) {
        let legacyView = createEditor(optimized: false)
        let optimizedView = createEditor(optimized: true)

        // Load same content
        [legacyView, optimizedView].forEach { view in
            try? view.editor.update {
                let root = getActiveEditorState()?.getRootNode()
                let paragraph = ParagraphNode()
                let text = TextNode(text: content)
                try? paragraph.append([text])
                try? root?.append([paragraph])
            }
        }

        // Measure performance
        let legacyTime = measurePerformance(of: legacyView)
        let optimizedTime = measurePerformance(of: optimizedView)

        print("Legacy: \(legacyTime)ms")
        print("Optimized: \(optimizedTime)ms")
        print("Improvement: \(legacyTime/optimizedTime)x")
    }

    private static func createEditor(optimized: Bool) -> LexicalView {
        let featureFlags = FeatureFlags(optimizedReconciler: optimized)
        let config = EditorConfig(theme: Theme(), plugins: [], featureFlags: featureFlags)
        return LexicalView(editorConfig: config)
    }

    private static func measurePerformance(of view: LexicalView) -> TimeInterval {
        let start = CACurrentMediaTime()

        try? view.editor.update {
            // Perform test operation
            if let root = getActiveEditorState()?.getRootNode(),
               let firstChild = root.getFirstChild() {
                try? firstChild.remove()
            }
        }

        return (CACurrentMediaTime() - start) * 1000  // Convert to ms
    }
}
```

## Performance Benchmarking

### Automated Benchmark Suite

```swift
class BenchmarkSuite {
    struct BenchmarkResult {
        let operation: String
        let legacyTime: TimeInterval
        let optimizedTime: TimeInterval
        var improvement: Double {
            legacyTime / optimizedTime
        }
    }

    static func runFullBenchmark() -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []

        // Test operations
        let operations = [
            ("Top Insertion", performTopInsertion),
            ("Middle Edit", performMiddleEdit),
            ("Bulk Delete", performBulkDelete),
            ("Format Change", performFormatChange)
        ]

        for (name, operation) in operations {
            let legacyTime = measureOperation(operation, optimized: false)
            let optimizedTime = measureOperation(operation, optimized: true)

            let result = BenchmarkResult(
                operation: name,
                legacyTime: legacyTime,
                optimizedTime: optimizedTime
            )

            results.append(result)
            print("\(name): \(String(format: "%.1fx", result.improvement)) improvement")
        }

        return results
    }

    private static func measureOperation(
        _ operation: (LexicalView) -> Void,
        optimized: Bool
    ) -> TimeInterval {
        let view = createTestEditor(optimized: optimized)
        generateTestDocument(in: view)

        let start = CACurrentMediaTime()
        operation(view)
        return (CACurrentMediaTime() - start) * 1000
    }

    private static func createTestEditor(optimized: Bool) -> LexicalView {
        let flags = FeatureFlags(optimizedReconciler: optimized)
        let config = EditorConfig(theme: Theme(), plugins: [], featureFlags: flags)
        return LexicalView(editorConfig: config)
    }

    private static func generateTestDocument(in view: LexicalView) {
        try? view.editor.update {
            guard let root = getActiveEditorState()?.getRootNode() else { return }
            for i in 0..<100 {
                let paragraph = ParagraphNode()
                let text = TextNode(text: "Paragraph \(i)")
                try? paragraph.append([text])
                try? root.append([paragraph])
            }
        }
    }

    private static func performTopInsertion(_ view: LexicalView) {
        try? view.editor.update {
            guard let root = getActiveEditorState()?.getRootNode() else { return }
            let newParagraph = ParagraphNode()
            let text = TextNode(text: "New top paragraph")
            try? newParagraph.append([text])
            if let firstChild = root.getFirstChild() {
                try? firstChild.insertBefore(nodeToInsert: newParagraph)
            }
        }
    }

    private static func performMiddleEdit(_ view: LexicalView) {
        try? view.editor.update {
            guard let root = getActiveEditorState()?.getRootNode() else { return }
            let children = root.getChildren()
            if children.count > 50,
               let paragraph = children[50] as? ParagraphNode,
               let textNode = paragraph.getFirstChild() as? TextNode {
                try? textNode.setText("Edited text")
            }
        }
    }

    private static func performBulkDelete(_ view: LexicalView) {
        try? view.editor.update {
            guard let root = getActiveEditorState()?.getRootNode() else { return }
            let children = root.getChildren()
            for i in 0..<min(25, children.count) {
                try? children[i].remove()
            }
        }
    }

    private static func performFormatChange(_ view: LexicalView) {
        try? view.editor.update {
            guard let root = getActiveEditorState()?.getRootNode() else { return }
            let children = root.getChildren()
            for i in 0..<min(10, children.count) {
                if let paragraph = children[i] as? ParagraphNode,
                   let textNode = paragraph.getFirstChild() as? TextNode {
                    try? textNode.setBold(true)
                }
            }
        }
    }
}
```