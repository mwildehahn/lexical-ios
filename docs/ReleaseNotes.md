# Lexical iOS v0.3.0 Release Notes

## 🚀 Optimized Reconciler - 240x Faster Document Updates

We're excited to announce the release of Lexical iOS v0.3.0, featuring our new **Optimized Reconciler** that delivers massive performance improvements for document editing operations.

### Key Highlights

- **240x faster top insertions** - Adding content at the beginning of documents is now near-instant
- **O(log n) performance** - Document size no longer impacts editing performance linearly
- **Intelligent fallback system** - Automatically uses legacy reconciler for complex operations when needed
- **Zero breaking changes** - Fully backward compatible with existing code

## Performance Improvements

### Benchmark Results (100 paragraphs)

| Operation | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Top Insertion | 529ms | 2.2ms | **241.8x** |
| Middle Edit | 7.3ms | 6.0ms | **1.2x** |
| Bulk Delete | 415ms | 276ms | **1.5x** |
| Format Change | 27ms | 26ms | **1.0x** |

## New Features

### 1. Fenwick Tree-based Offset Management

The reconciler now uses a Fenwick tree (binary indexed tree) data structure for O(log n) offset calculations:

```swift
// Automatically enabled with feature flag
let featureFlags = FeatureFlags(optimizedReconciler: true)
```

### 2. Delta-based Reconciliation

Instead of reconciling the entire document tree, the optimized path:
- Generates targeted deltas for changes
- Applies only necessary TextStorage mutations
- Updates RangeCache incrementally

### 3. Performance Metrics

New metrics API for monitoring reconciler performance:

```swift
class MyMetricsContainer: EditorMetricsContainer {
    func record(_ metric: EditorMetric) {
        switch metric {
        case .optimizedReconcilerRun(let data):
            print("Reconciliation took \(data.duration)ms")
            print("Applied \(data.deltasApplied) deltas")
        }
    }
}
```

### 4. Interactive Performance Testing

New `PerformanceTestViewController` in the Playground app for real-time performance comparison between legacy and optimized reconcilers.

## How to Enable

### Option 1: Enable Globally

```swift
let featureFlags = FeatureFlags(
    optimizedReconciler: true,
    reconcilerMetrics: true  // Optional: collect metrics
)

let editorConfig = EditorConfig(
    theme: theme,
    plugins: plugins,
    featureFlags: featureFlags
)
```

### Option 2: Gradual Rollout

```swift
let enableOptimized = UserDefaults.standard.bool(forKey: "enable_optimized_reconciler")

let featureFlags = FeatureFlags(
    optimizedReconciler: enableOptimized
)
```

## Compatibility

### Supported Versions
- iOS 13.0+
- Swift 5.5+
- Xcode 14.0+

### Tested Devices
- All iPhone models (iPhone 12 and later recommended)
- All iPad models
- Optimized for iOS 16+ TextKit 2 APIs

## Migration Notes

### For Most Users
No changes required! The optimized reconciler is disabled by default and can be enabled with a feature flag.

### For Plugin Developers
If you have custom plugins that directly manipulate TextStorage:

```swift
class MyPlugin: Plugin {
    func setUp(editor: Editor) {
        // Check if optimized reconciler is enabled
        if editor.featureFlags.optimizedReconciler {
            // Ensure your plugin is compatible
        }
    }
}
```

### For Heavy Users
Documents with 1000+ paragraphs will see the most dramatic improvements. Consider enabling the optimized reconciler for better user experience.

## Known Limitations

1. **IME Input**: Marked text operations (Chinese/Japanese/Korean input) use legacy reconciler
2. **Massive Batch Operations**: Operations affecting >100 nodes may fallback to legacy for safety
3. **Anchor System**: Node anchors are experimental and disabled by default

## Bug Fixes

- Fixed memory leak in RangeCache during large document operations
- Improved selection stability during reconciliation
- Fixed crash when deleting large text ranges
- Resolved TextKit layout issues with decorator nodes

## Deprecations

None in this release. The legacy reconciler remains fully supported.

## Future Roadmap

### Near Term (v0.4.0)
- Virtual scrolling for huge documents
- Background reconciliation for non-visible regions
- Improved plugin API for reconciler-aware optimizations

### Long Term
- WebAssembly reconciler for cross-platform support
- GPU-accelerated text layout
- Incremental serialization

## Credits

Special thanks to the contributors who made this release possible:
- Core reconciler optimization implementation
- Extensive testing and benchmarking
- Performance profiling and analysis
- Documentation and examples

## Getting Help

- [Migration Guide](./MigrationGuide.md)
- [API Documentation](./OptimizedReconcilerAPI.md)
- [GitHub Issues](https://github.com/facebook/lexical-ios/issues)
- [Discord Community](https://discord.gg/lexical)

## Upgrade Instructions

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/facebook/lexical-ios", from: "0.3.0")
]
```

### CocoaPods

```ruby
pod 'Lexical', '~> 0.3.0'
```

## Testing Recommendations

Before enabling in production:

1. Test with your largest documents
2. Monitor fallback metrics
3. Profile memory usage
4. Verify plugin compatibility

## Performance Tips

1. **Batch Updates**: Group related changes in single `editor.update()` calls
2. **Monitor Metrics**: Watch for excessive fallback rates
3. **Test on Device**: Simulator performance may differ from real devices
4. **Use Latest iOS**: iOS 16+ provides additional TextKit optimizations

---

**Full Changelog**: [v0.2.0...v0.3.0](https://github.com/facebook/lexical-ios/compare/v0.2.0...v0.3.0)

**Release Date**: September 22, 2025