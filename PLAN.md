# Lexical iOS Reconciler Performance Optimization Plan

## Current Architecture Analysis

### Core Problem
The reconciler has O(n) performance for all document edits because it:
1. **Walks the entire tree** on every update to recalculate string offsets (`Reconciler.swift:300-387`)
2. **Rebuilds the entire RangeCache** by copying and mutating during sweep (`RangeCache.swift:16-266`)
3. **Marks large regions dirty** through ancestor/sibling bubbling (`Utils.swift:78-139`)
4. **Performs multiple TextStorage operations** without batching or optimization

### Performance Impact
- **Top insertion lag**: Adding a newline at document start reconciles entire tree
- **Medium document slowdown**: 100+ paragraphs show noticeable lag
- **Large document issues**: 1000+ paragraphs become unusable

### Current Flow
```
Update → Dirty Marking → Full Tree Walk → Complete Range Rebuild → Multiple TextStorage Ops
```

## Proposed Solution: Fenwick Tree-based Incremental Reconciliation

### Architecture Overview
Replace full tree reconciliation with targeted updates using:
1. **Fenwick Tree** for O(log n) offset management
2. **Node Anchors** for direct node location in TextStorage
3. **Delta Reconciler** for incremental updates
4. **Feature Flags** for safe rollout

### Core Components

#### 1. FenwickTree Data Structure
```swift
class FenwickTree {
    private var tree: [Int]  // Cumulative text lengths

    func update(index: Int, delta: Int)  // O(log n)
    func query(index: Int) -> Int        // O(log n) prefix sum
    func rangeQuery(l: Int, r: Int) -> Int  // O(log n)
}
```

**Benefits:**
- Logarithmic offset updates after text changes
- Efficient range queries for node locations
- Minimal memory overhead

#### 2. Node Anchor System
**Implementation:**
- Zero-width spaces (`\u{200B}`) with custom attributes
- Attributes carry compressed NodeKey identifiers
- Inserted at node boundaries (preamble/postamble)

**Format:**
```swift
NSAttributedString.Key("LexicalNodeAnchor"): [
    "nodeKey": "compressed_key",
    "type": "preamble|postamble"
]
```

**Considerations:**
- Must not affect copy/paste behavior
- Maintain accessibility compliance
- Handle selection around anchors

#### 3. TextStorageDeltaApplier
```swift
class TextStorageDeltaApplier {
    func applyDelta(
        delta: ReconcilerDelta,
        textStorage: NSTextStorage,
        fenwickTree: FenwickTree
    ) {
        // 1. Locate anchors in TextStorage
        // 2. Apply targeted mutations
        // 3. Update Fenwick tree
        // 4. Adjust RangeCache deltas
    }
}
```

**Operations:**
- Text updates within nodes
- Node insertions/deletions
- Attribute changes
- Fallback triggers

#### 4. Incremental RangeCache Updates
Instead of rebuilding entire cache:
- Update only affected entries
- Use Fenwick tree for offset adjustments
- Maintain cache coherency incrementally

### Feature Flag System
```swift
class FeatureFlags {
    let optimizedReconciler: Bool = false
    let reconcilerMetrics: Bool = false
    let anchorBasedReconciliation: Bool = false
}
```

### Fallback Conditions
Full reconciliation triggers for:
- Structural transforms (list promotion/demotion)
- Large batch operations (>100 nodes affected)
- Anchor corruption detection
- Debug/diagnostic mode

## Implementation Phases

### Phase 1: Foundation Infrastructure (Week 1) ✅ COMPLETED
- [x] Create `FenwickTree.swift` with full implementation
- [x] Add feature flags to `FeatureFlags.swift`
- [x] Create `ReconcilerMetrics.swift` for performance tracking (extended existing EditorMetrics)
- [x] Set up benchmark test harness in `LexicalTests/`
- [x] Create large document generators for testing
- [x] **Unit Tests**: `FenwickTreeTests.swift` - test all operations (update, query, rangeQuery)
- [x] **Unit Tests**: `ReconcilerMetricsTests.swift` - verify metric collection
- [x] **Unit Tests**: `FeatureFlagsTests.swift` - test flag toggling and defaults
- [x] **All Tests Passing**: 244 tests passing successfully

### Phase 2: Anchor System (Week 1-2) ✅ CORE IMPLEMENTATION COMPLETED
- [x] Implement anchor generation (integrated directly in `Reconciler.swift`)
- [x] Add anchor insertion to `Reconciler.swift`
- [x] Create `AnchorManager.swift` for anchor operations
- [x] Handle copy/paste in `CopyPasteHelpers.swift`
- [x] Validate selection behavior around anchors (implemented in TextView)
- [x] **Unit Tests**: `AnchorManagerTests.swift` - anchor creation, validation, extraction
- [x] **Unit Tests**: `AnchorCopyPasteTests.swift` - verify anchor stripping on copy
- [x] **Unit Tests**: `AnchorSelectionTests.swift` - selection around anchors

**Implementation Notes**:
- Core anchor system is fully implemented and integrated
- Anchors are generated using zero-width spaces (`\u{200B}`) with custom attributes
- Reconciler properly calculates lengths including anchors when feature flag enabled
- Copy/paste correctly strips anchors from copied content
- Selection automatically adjusts to skip over anchor positions
- Unit tests created and compile successfully
- AnchorType enum is Codable for metadata serialization
- Editor reference passed through ReconcilerState for anchor generation
- Tests should be run in Xcode for full iOS simulator environment

### Phase 3: Delta Reconciler (Week 2-3)
- [ ] Create `TextStorageDeltaApplier.swift`
- [ ] Implement `ReconcilerDelta` types
- [ ] Add incremental RangeCache updates
- [ ] Integrate Fenwick tree tracking
- [ ] Build fallback detection logic
- [ ] Create delta validation system
- [ ] **Unit Tests**: `TextStorageDeltaApplierTests.swift` - delta application correctness
- [ ] **Unit Tests**: `ReconcilerDeltaTests.swift` - delta generation from changes
- [ ] **Unit Tests**: `IncrementalRangeCacheTests.swift` - cache update accuracy
- [ ] **Unit Tests**: `FallbackDetectionTests.swift` - verify fallback triggers

### Phase 4: Integration (Week 3-4)
- [ ] Wire optimized path in `Editor.beginUpdate()`
- [ ] Add reconciler selection logic
- [ ] Implement metrics collection
- [ ] Create A/B testing infrastructure
- [ ] Add diagnostic tools
- [ ] Build performance dashboard
- [ ] **Unit Tests**: `OptimizedReconcilerTests.swift` - end-to-end optimized path
- [ ] **Unit Tests**: `ReconcilerSelectionTests.swift` - feature flag switching
- [ ] **Unit Tests**: `MetricsCollectionTests.swift` - verify metrics accuracy
- [ ] **Integration Tests**: Test both reconcilers produce identical output

### Phase 5: Testing & Validation (Week 4-5)
- [ ] Performance benchmarks vs legacy
- [ ] Edge case coverage
- [ ] Stress testing with large documents
- [ ] Memory profiling
- [ ] **Performance Tests**: `ReconcilerPerformanceTests.swift` - benchmark suite
- [ ] **Stress Tests**: `LargeDocumentTests.swift` - 10,000+ paragraph documents
- [ ] **Edge Case Tests**: `ReconcilerEdgeCaseTests.swift` - boundary conditions
- [ ] **Memory Tests**: Verify no memory leaks with Instruments

### Phase 6: Polish & Documentation (Week 5)
- [ ] API documentation
- [ ] Performance tuning
- [ ] Code review fixes
- [ ] Migration guide
- [ ] Release notes
- [ ] **Documentation Tests**: Verify all public APIs are documented
- [ ] **Example Tests**: Ensure all example code in docs compiles and runs

## Test Implementation

### Playground Test View
Create `PerformanceTestViewController.swift`:
```swift
class PerformanceTestViewController {
    // Two side-by-side LexicalViews
    @IBOutlet var legacyView: LexicalView!
    @IBOutlet var optimizedView: LexicalView!

    // Metrics display
    @IBOutlet var metricsLabel: UILabel!

    // Test scenarios
    func testTopInsertion()
    func testMiddleEdit()
    func testBulkOperations()
    func generateLargeDocument(_ paragraphs: Int)
}
```

### Test Scenarios
1. **Top insertion**: Add paragraph at document start
2. **Middle edit**: Modify paragraph in document center
3. **Bottom append**: Add content at end
4. **Bulk delete**: Remove 50% of paragraphs
5. **Format changes**: Apply bold to multiple paragraphs
6. **List operations**: Convert paragraphs to list items

### Performance Targets
| Operation | Current | Target | Improvement |
|-----------|---------|--------|-------------|
| Top insertion (1000 paragraphs) | 150ms | 15ms | 10x |
| Middle edit (1000 paragraphs) | 120ms | 10ms | 12x |
| Format change (100 paragraphs) | 80ms | 8ms | 10x |
| Initial render (1000 paragraphs) | 500ms | 100ms | 5x |

## iOS 16+ SDK Improvements to Leverage

### TextKit 2 Features (iOS 15+)
- `NSTextContentManager`: Better text layout caching
- `NSTextLayoutFragment`: Incremental layout updates
- `NSTextLayoutManager`: Improved performance APIs

### iOS 16 Enhancements
- Improved `NSAttributedString` performance
- Better attribute coalescence
- Faster range operations
- Enhanced memory management

### Implementation Strategy
```swift
if #available(iOS 16.0, *) {
    // Use optimized TextKit 2 APIs
    textLayoutManager.ensureLayout(for: range)
} else {
    // Fall back to TextKit 1
    layoutManager.ensureLayout(for: range)
}
```

## Metrics & Monitoring

### Key Metrics
```swift
struct ReconcilerMetric {
    let duration: TimeInterval
    let nodesProcessed: Int
    let rangesUpdated: Int
    let textStorageMutations: Int
    let fenwickOperations: Int
    let fallbackTriggered: Bool
}
```

### Dashboard Display
- Real-time reconciliation time
- Node processing count
- Cache hit/miss ratio
- Fallback frequency
- Memory usage

## Rollout Strategy

### Phase 1: Internal Testing
- Feature flag disabled by default
- Manual testing by development team
- Performance profiling

### Phase 2: Beta Testing
- Enable for 5% of users
- Monitor metrics and crashes
- Gather performance data

### Phase 3: Gradual Rollout
- 25% → 50% → 100% over 2 weeks
- Monitor key metrics
- Quick rollback capability

### Phase 4: Legacy Removal
- After 30 days stable
- Remove legacy reconciler code
- Document migration

## Risk Mitigation

### Potential Issues
1. **Anchor corruption**: Validation and regeneration system
2. **Memory leaks**: Weak references and proper cleanup
3. **Selection bugs**: Comprehensive test coverage
4. **Copy/paste issues**: Anchor stripping on export
5. **Accessibility**: VoiceOver testing

### Rollback Plan
- Feature flag allows instant rollback
- Metrics trigger automatic rollback if thresholds exceeded
- Keep legacy code for 60 days post-launch

## Success Criteria

### Performance
- ✅ 10x improvement for top insertions
- ✅ <16ms for typical edits (60fps)
- ✅ Linear scaling with document size

### Correctness
- ✅ 100% test pass rate
- ✅ No regression in existing functionality
- ✅ Accessibility compliance maintained

### User Experience
- ✅ No visible lag for documents <5000 paragraphs
- ✅ Smooth typing experience
- ✅ Responsive formatting operations

## Future Enhancements

### Near Term (3-6 months)
- Virtual scrolling for huge documents
- Background reconciliation for non-visible regions
- Predictive pre-reconciliation

### Long Term (6-12 months)
- WebAssembly reconciler for cross-platform
- GPU-accelerated text layout
- Incremental serialization

## References
- [Fenwick Tree Algorithm](https://en.wikipedia.org/wiki/Fenwick_tree)
- [TextKit 2 Documentation](https://developer.apple.com/documentation/uikit/textkit)
- [Lexical JS Reconciler](https://github.com/facebook/lexical)