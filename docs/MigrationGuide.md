# Optimized Reconciler Migration Guide

## Overview

This guide helps you migrate from the legacy reconciler to the optimized reconciler in Lexical iOS. The migration is designed to be gradual and safe with feature flags controlling the rollout.

## Migration Timeline

### Phase 1: Testing (Weeks 1-2)
- Enable optimized reconciler in development builds
- Run performance benchmarks
- Monitor metrics (durations, Fenwick ops) and correctness tests

### Phase 2: Beta Rollout (Weeks 3-4)
- Enable for 5% of beta users
- Collect performance data
- Address any issues

### Phase 3: Production Rollout (Weeks 5-6)
- Gradual rollout: 25% → 50% → 100%
- Monitor key metrics
- Keep rollback capability ready

## Step-by-Step Migration

### Step 1: Update Dependencies

Ensure you're using the latest version of Lexical iOS that includes the optimized reconciler:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/facebook/lexical-ios", from: "0.2.0")
]
```

### Step 2: Enable Feature Flags

Start with the optimized reconciler disabled:

```swift
let featureFlags = FeatureFlags(
    optimizedReconciler: false,  // Start disabled
    reconcilerMetrics: true       // Enable metrics collection
)

let editorConfig = EditorConfig(
    theme: theme,
    plugins: plugins,
    featureFlags: featureFlags
)
```

### Step 3: Set Up Metrics Collection

Implement a metrics container to track performance:

```swift
class MyMetricsContainer: EditorMetricsContainer {
    func record(_ metric: EditorMetric) {
        switch metric {
        case .reconcilerRun(let data):
            // Log legacy reconciler performance
            Analytics.track("reconciler.legacy", properties: [
                "duration": data.duration,
                "nodesProcessed": data.nodesProcessed
            ])

        case .optimizedReconcilerRun(let data):
            // Log optimized reconciler performance
            Analytics.track("reconciler.optimized", properties: [
                "duration": data.duration,
                "deltasApplied": data.deltasApplied,
                "fallback": data.didFallback
            ])
        }
    }
}

let editorConfig = EditorConfig(
    theme: theme,
    plugins: plugins,
    metricsContainer: MyMetricsContainer(),
    featureFlags: featureFlags
)
```

### Step 4: A/B Testing Setup

Implement controlled rollout:

```swift
class FeatureFlagManager {
    static func shouldUseOptimizedReconciler() -> Bool {
        // Start with percentage-based rollout
        let rolloutPercentage = RemoteConfig.getValue("optimized_reconciler_rollout") ?? 0
        let userBucket = getUserBucket() // Hash of user ID
        return userBucket < rolloutPercentage
    }

    static func createFeatureFlags() -> FeatureFlags {
        // New API
        return FeatureFlags(
          reconcilerMode: shouldUseOptimizedReconciler() ? .optimized : .legacy,
          diagnostics: Diagnostics(metrics: true)
        )
    }
}
```

### Step 5: Enable Optimized Reconciler

Once testing is complete, enable the optimized path:

```swift
let featureFlags = FeatureFlags(
    optimizedReconciler: true,
    reconcilerMetrics: true
)
```

## Performance Benchmarking

### Before Migration

Collect baseline metrics:

```swift
class BaselineMetrics {
    static func measurePerformance() {
        let startTime = CACurrentMediaTime()

        // Perform typical operations
        editor.update {
            // Insert at top
            // Edit middle
            // Delete bulk
            // Format text
        }

        let duration = CACurrentMediaTime() - startTime
        Analytics.track("baseline.performance", duration: duration)
    }
}
```

### After Migration

Compare performance:

```swift
class PerformanceComparison {
    static func compareReconcilers() {
        // Test with legacy
        let legacyDuration = measureWithLegacy()

        // Test with optimized
        let optimizedDuration = measureWithOptimized()

        let improvement = legacyDuration / optimizedDuration
        print("Performance improvement: \(improvement)x")
    }
}
```

## Common Issues and Solutions

### Issue 1: Large batch performance regressions

**Symptom:** Slow reconciliations on very large, unrelated batches

**Solution:** Chunk the batch into smaller updates
```swift
// Check for large batch operations
if nodes.count > 50 {
    // Split into smaller batches
    for batch in nodes.chunked(into: 20) {
        editor.update {
            // Process batch
        }
    }
}
```

### Issue 2: Plugin Compatibility

**Symptom:** Custom plugins not working correctly

**Solution:**
```swift
class MyPlugin: Plugin {
    func setUp(editor: Editor) {
        // Check for optimized reconciler
        if editor.featureFlags.optimizedReconciler {
            // Use optimized-aware code path
        } else {
            // Use legacy code path
        }
    }
}
```

### Issue 3: Memory Usage

**Symptom:** Increased memory with large documents

**Solution:**
```swift
// Monitor Fenwick tree size
if editor.fenwickTree.nodeCount > 10000 {
    // Consider pagination or virtualization
}
```

## Rollback Procedure

If issues arise, rollback immediately:

```swift
// 1. Disable via feature flag
RemoteConfig.setValue("optimized_reconciler_enabled", false)

// 2. Force app to reload configuration
NotificationCenter.default.post(name: .reloadFeatureFlags, object: nil)

// 3. Monitor metrics to confirm rollback
Analytics.track("reconciler.rollback", properties: [
    "reason": rollbackReason,
    "timestamp": Date()
])
```

## Monitoring Dashboard

Key metrics to monitor:

1. **Performance Metrics**
   - P50/P95/P99 reconciliation times
   - Fenwick operations per batch
   - Document size (nodes, storage length)

2. **Correctness / Error Metrics**
   - Reconciliation failures
   - Sanity check violations (if enabled)
   - Memory pressure events

## Testing Checklist

Before enabling in production:

- [ ] Run performance benchmarks
- [ ] Test with documents >1000 paragraphs
- [ ] Verify all plugins work correctly
- [ ] Test IME input (Chinese, Japanese, Korean)
- [ ] Verify undo/redo functionality
- [ ] Test copy/paste operations
- [ ] Validate accessibility (VoiceOver)
- [ ] Memory profiling under load
- [ ] Test on older devices (iPhone 12 and earlier)

## Support and Resources

- [API Documentation](./OptimizedReconcilerAPI.md)
- [Performance Test Results](../PLAN.md#performance-targets-vs-actual-results)
- [GitHub Issues](https://github.com/facebook/lexical-ios/issues)
- [Community Discord](https://discord.gg/lexical)

## FAQ

**Q: Is the optimized reconciler backward compatible?**
A: Yes, it's fully backward compatible. The feature flag allows seamless switching.

**Q: What's the performance improvement?**
A: Top insertion operations see up to 240x improvement. Typical edits are 2-10x faster.

**Q: When should I not use the optimized reconciler?**
A: If you have custom TextStorage modifications or depend on specific reconciliation order.

**Q: How do I debug reconciliation issues?**
A: Enable debug logging and use the PerformanceTestViewController for side-by-side comparison.
Preferred flags API (structured):

```swift
// Recommended starting point using the new API
let flags = FeatureFlags(
  reconcilerMode: .legacy,                   // start disabled
  diagnostics: Diagnostics(metrics: true)    // collect metrics from day one
)
```
