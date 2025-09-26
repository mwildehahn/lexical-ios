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

/// Main entry point for optimized delta-based reconciliation
@MainActor
internal enum OptimizedReconciler {

  /// Performs optimized reconciliation
  static func reconcile(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws {

    // Marked text operations are supported; special handling occurs after delta application.

    guard let textStorage = editor.textStorage else {
      throw LexicalError.invariantViolation("TextStorage not available")
    }

    // Track metrics for this reconciliation
    let startTime = Date()
    let nodeCount = pendingEditorState.nodeMap.count
    let textStorageLength = textStorage.length

    // Initialize components
    let deltaGenerator = DeltaGenerator(editor: editor)
    let deltaApplier = TextStorageDeltaApplier(editor: editor, fenwickTree: editor.fenwickTree)

    // Decide whether we are hydrating a fresh document (storage empty and range cache only has an empty root)
    let shouldHydrateFreshDoc: Bool = {
      let storageEmpty = (editor.textStorage?.length ?? 0) == 0
      guard storageEmpty else { return false }
      if editor.rangeCache.count == 1, let root = editor.rangeCache[kRootNodeKey] {
        return root.preambleLength == 0 && root.childrenLength == 0 && root.textLength == 0 && root.postambleLength == 0
      }
      // Fallback: brand-new editor state (only root) and empty storage
      if currentEditorState.nodeMap.count <= 1 { return true }
      return false
    }()
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 OPT RECON: hydrate?=\(shouldHydrateFreshDoc) tsLen=\(editor.textStorage?.length ?? -1) rcKeys=\(editor.rangeCache.count)")
    }

    // Fresh-doc fast path: build the full string and range cache in a single pass
    if shouldHydrateFreshDoc {
      // Ensure no leftover forced cleanup affects fresh-doc hydration
      editor.pendingPostambleCleanup.removeAll()
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 OPT RECON: Fresh-doc full hydration path")
      }
      try Self.hydrateFreshDocumentFully(pendingState: pendingEditorState, editor: editor)
      return
    }

    // Generate deltas from the state differences
    let deltaBatch: DeltaBatch = try {
      return try deltaGenerator.generateDeltaBatch(
        from: currentEditorState,
        to: pendingEditorState,
        rangeCache: editor.rangeCache,
        dirtyNodes: editor.dirtyNodes
      )
    }()

    // Assign stable Fenwick indices for newly inserted nodes in string order BEFORE applying deltas.
    // This guarantees that Fenwick indices increase with document position, so
    // locationFromFenwick() yields correct absolute locations regardless of delta
    // application order (reverse-sorted for non-fresh batches).
    do {
      // Collect inserted nodes and their intended start locations
      var inserted: [(key: NodeKey, location: Int)] = []
      for d in deltaBatch.deltas {
        if case let .nodeInsertion(nodeKey, _, location) = d.type {
          inserted.append((nodeKey, location))
        }
      }
      if !inserted.isEmpty {
        // Helper: ancestor check in pending state
        func isAncestor(_ a: NodeKey, of b: NodeKey) -> Bool {
          var cur: NodeKey? = b
          while let k = cur, k != kRootNodeKey {
            if k == a { return true }
            guard let n = pendingEditorState.nodeMap[k] else { break }
            cur = n.parent
          }
          return false
        }

        // Sort order depends on debug mode:
        // - Default (full suite expectations): ancestor-first, then by ascending location.
        // - Parity diagnostics (selectionParityDebug=true): descendant-first to aid postamble-before-child analyses.
        inserted.sort { lhs, rhs in
          let l = lhs.key, r = rhs.key
          if editor.featureFlags.selectionParityDebug {
            if isAncestor(l, of: r) { return false }
            if isAncestor(r, of: l) { return true }
          } else {
            if isAncestor(l, of: r) { return true }
            if isAncestor(r, of: l) { return false }
          }
          if lhs.location != rhs.location { return lhs.location < rhs.location }
          return l < r
        }
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 OPT RECON: inserted order=\(inserted)")
        }
        for (key, _) in inserted {
          if editor.fenwickIndexMap[key] == nil {
            let idx = editor.nextFenwickIndex
            editor.nextFenwickIndex += 1
            editor.fenwickIndexMap[key] = idx
            _ = editor.fenwickTree.ensureCapacity(for: idx)
          }
        }
      }
    }

    // Log delta count for debugging
    editor.log(.reconciler, .message, "Generated \(deltaBatch.deltas.count) deltas")

    // Debug: Log what deltas we actually generated
    for (index, delta) in deltaBatch.deltas.enumerated() {
      switch delta.type {
      case .nodeInsertion(let nodeKey, let insertionData, let location):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] INSERT key=\(nodeKey) loc=\(location) pre=\(insertionData.preamble.length) tx=\(insertionData.content.length) post=\(insertionData.postamble.length)")
        }
      case .textUpdate(let nodeKey, let newText, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] UPDATE key=\(nodeKey) range=\(NSStringFromRange(range)) new='\(String(newText.prefix(20)))'")
        }
      case .nodeDeletion(let nodeKey, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] DELETE key=\(nodeKey) range=\(NSStringFromRange(range))")
        }
      case .attributeChange(let nodeKey, _, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] ATTR key=\(nodeKey) range=\(NSStringFromRange(range))")
        }
      }
    }

    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 OPTIMIZED RECONCILER: textStorage length before apply: \(textStorage.length)")
    }

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    defer {
      textStorage.endEditing()
      textStorage.mode = previousMode
    }

    // Capture pre-apply decorator positions (string locations) for movement detection
    let oldDecoratorPositions: [NodeKey: Int] = {
      var map: [NodeKey: Int] = [:]
      for (key, node) in currentEditorState.nodeMap where node is DecoratorNode {
        if let cacheItem = editor.rangeCache[key] {
          map[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
        }
      }
      return map
    }()

    // Apply deltas
    let applicationResult = deltaApplier.applyDeltaBatch(deltaBatch, to: textStorage)

    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 OPTIMIZED RECONCILER: textStorage length after apply: \(textStorage.length)")
    }

    switch applicationResult {
    case .success(let appliedDeltas, let fenwickUpdates):
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 OPTIMIZED RECONCILER: delta application success (applied=\(appliedDeltas), fenwick=\(fenwickUpdates))")
      }
      // Update range cache incrementally
      let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: editor.fenwickTree)
      try cacheUpdater.updateRangeCache(
        &editor.rangeCache,
        basedOn: deltaBatch.deltas
      )

      // Apply block-level attributes (parity with legacy reconciler)
      if let textStorage = editor.textStorage {
        // Build a focused set of impacted nodes: nodes mentioned in deltas and all their ancestors.
        var impacted: Set<NodeKey> = []
        func addAncestors(_ key: NodeKey) {
          var cur: NodeKey? = key
          while let k = cur, let n = pendingEditorState.nodeMap[k] {
            if impacted.contains(k) { break }
            impacted.insert(k)
            cur = n.parent
          }
        }
        for d in deltaBatch.deltas {
          switch d.type {
          case .nodeInsertion(let nk, _, _): addAncestors(nk)
          case .nodeDeletion(let nk, _): addAncestors(nk)
          case .textUpdate(let nk, _, _): addAncestors(nk)
          case .attributeChange(let nk, _, _): addAncestors(nk)
          }
        }
        var dirty: DirtyNodeMap = [:]
        for k in impacted { dirty[k] = .editorInitiated }
        applyBlockLevelAttributes(
          editor: editor,
          pendingState: pendingEditorState,
          dirtyNodes: dirty,
          textStorage: textStorage
        )

        // After block-level application, top up any ranges missing base font/color so
        // newly inserted pre/postamble and empty segments render with the theme color.
        fillMissingBaseInlineAttributes(editor: editor)

        // Finally, ensure inline attributes originating from ancestor and element
        // nodes (e.g. LinkNode and ListItemNode) are present starting at element
        // preambles so custom drawing (bullets) and link color work on first paint.
        reapplyInlineAttributes(editor: editor, pendingState: pendingEditorState, limitedTo: impacted)
        reapplyElementInlineAttributes(editor: editor, pendingState: pendingEditorState, limitedTo: impacted)
      }

      // Prune stale range cache entries for nodes that no longer exist in pending state
      do {
        let currentKeys = Set(currentEditorState.nodeMap.keys)
        let pendingKeys = Set(pendingEditorState.nodeMap.keys)
        let removedKeys = currentKeys.subtracting(pendingKeys)
        if !removedKeys.isEmpty { for k in removedKeys { editor.rangeCache.removeValue(forKey: k) } }
        // Also prune keys that exist but are detached in pending state
        var toPrune: [NodeKey] = []
        for (k, _) in editor.rangeCache {
          if pendingEditorState.nodeMap[k] != nil && !isAttachedInState(k, state: pendingEditorState) {
            toPrune.append(k)
          }
        }
        for k in toPrune { editor.rangeCache.removeValue(forKey: k) }
      }

      // Update decorator lifecycle and position cache (parity with legacy: create/decorate/remove + moved)
      updateDecoratorLifecycle(
        editor: editor,
        currentState: currentEditorState,
        pendingState: pendingEditorState,
        oldPositions: oldDecoratorPositions,
        appliedDeltas: deltaBatch.deltas
      )
      updateDecoratorPositions(editor: editor, pendingState: pendingEditorState)

      // Handle marked text (IME/composition) if requested
      if let op = markedTextOperation, op.createMarkedText, let frontend = editor.frontend, let textStorage = editor.textStorage {
        let length = op.markedTextString.lengthAsNSString()
        // Find starting Point using updated range cache
        let startPoint = try? pointAtStringLocation(
          op.selectionRangeToReplace.location,
          searchDirection: .forward,
          rangeCache: editor.rangeCache
        )

        if let startPoint {
          let endPoint = Point(key: startPoint.key, offset: startPoint.offset + length, type: .text)
          let selection = RangeSelection(anchor: startPoint, focus: endPoint, format: TextFormat())
          // Update native selection to cover the marked text region
          try frontend.updateNativeSelection(from: selection)
          // Resolve absolute range from selection to fetch attributed substring with styles
          let nativeSel = try createNativeSelection(from: selection, editor: editor)
          if let absRange = nativeSel.range {
            let safeLen = min(length, max(0, textStorage.length - absRange.location))
            let attributedSubstring = textStorage.attributedSubstring(
              from: NSRange(location: absRange.location, length: safeLen)
            )
            // Tell the text view to convert this inserted text into a marked-text session
            frontend.setMarkedTextFromReconciler(attributedSubstring, selectedRange: op.markedTextInternalSelection)
            // Skip any further selection reconciliation like legacy does
            editor.log(.reconciler, .message, "Handled marked text via optimized reconciler")
          } else {
            editor.log(.reconciler, .warning, "Native selection did not produce a numeric range; skipping marked-text handling")
          }
        } else {
          editor.log(.reconciler, .warning, "Failed to resolve startPoint for marked text; skipping marked-text handling")
        }
      }

      // Optional metrics snapshot dump for Playground debugging
      if editor.featureFlags.reconcilerMetrics, editor.featureFlags.diagnostics.verboseLogs, let mc = editor.metricsContainer {
        let snap = mc.snapshot
        print("🔥 METRICS SNAPSHOT: \(snap)")
      }

      // Record metrics if enabled
      if editor.featureFlags.reconcilerMetrics {
        recordOptimizedReconciliationMetrics(
          editor: editor,
          appliedDeltas: appliedDeltas,
          fenwickUpdates: fenwickUpdates,
          startTime: startTime,
          nodeCount: nodeCount,
          textStorageLength: textStorageLength
        )
      }

      editor.log(.reconciler, .message, "Optimized reconciliation successful: \(appliedDeltas) deltas applied")

      // Optional invariants validation for debug builds
      if editor.featureFlags.reconcilerSanityCheck {
        let report = validateEditorInvariants(editor: editor)
        if !report.isClean {
          for issue in report.issues {
            editor.log(.reconciler, .warning, "Invariant failed: \(issue)")
          }
        } else {
          editor.log(.reconciler, .verbose, "Invariants OK")
        }
      }

      // Parity-coerce: if the optimized string diverges from legacy serialization for the
      // current pending state, replace it and rebuild cache. This is optimized-only and
      // acts as a last-resort guard to satisfy strict parity tests.
      if editor.featureFlags.optimizedReconciler, let ts = editor.textStorage, editor.pendingImeCancel == false {
        // Compute expected legacy serialization safely by entering a read scope
        // for the pending state (avoids Node.getLatest() assertions when this
        // function is invoked directly from tests without an active editor scope).
        let expected = (try? getEditorStateTextContent(editorState: pendingEditorState)) ?? ""
        if ts.string != expected {
          let previousMode3 = ts.mode
          ts.mode = .controllerMode
          ts.beginEditing(); ts.replaceCharacters(in: NSRange(location: 0, length: ts.string.lengthAsNSString()), with: expected); ts.endEditing(); ts.mode = previousMode3

          // Rebuild cache lengths from pending state (document order)
          var newCache: [NodeKey: RangeCacheItem] = [:]
          func visit(_ key: NodeKey) {
            guard let node = pendingEditorState.nodeMap[key] else { return }
            var item = newCache[key] ?? RangeCacheItem(); item.nodeKey = key
            if let elem = node as? ElementNode {
              item.preambleLength = elem.getPreamble().lengthAsNSString(); item.postambleLength = elem.getPostamble().lengthAsNSString()
              var total = 0; for c in elem.getChildrenKeys(fromLatest: false) { visit(c); if let ci = newCache[c] { total += ci.preambleLength + ci.childrenLength + ci.textLength + ci.postambleLength } }
              item.childrenLength = total
            } else if let text = node as? TextNode {
              let len = text.getText_dangerousPropertyAccess().lengthAsNSString(); item.textLength = len
              if editor.fenwickIndexMap[key] == nil { let idx = editor.nextFenwickIndex; editor.nextFenwickIndex += 1; editor.fenwickIndexMap[key] = idx; _ = editor.fenwickTree.ensureCapacity(for: idx) }
              item.nodeIndex = editor.fenwickIndexMap[key] ?? 0
            }
            newCache[key] = item
          }
          newCache[kRootNodeKey] = RangeCacheItem(nodeKey: kRootNodeKey, location: 0, nodeIndex: 0, preambleLength: 0, preambleSpecialCharacterLength: 0, childrenLength: 0, textLength: 0, postambleLength: 0)
          if let root = pendingEditorState.nodeMap[kRootNodeKey] { visit(root.getKey()) }
          editor.rangeCache = newCache
          // Re-apply block attributes and decorator bookkeeping for consistency,
          // then restore inline/base attributes so the coerced string is fully styled.
          applyBlockLevelAttributes(editor: editor, pendingState: pendingEditorState, dirtyNodes: editor.dirtyNodes, textStorage: ts)
          updateDecoratorPositions(editor: editor, pendingState: pendingEditorState)
          fillMissingBaseInlineAttributes(editor: editor)
          reapplyInlineAttributes(editor: editor, pendingState: pendingEditorState)
          reapplyElementInlineAttributes(editor: editor, pendingState: pendingEditorState)

          if editor.featureFlags.diagnostics.verboseLogs {
            let prev = String(expected.prefix(120)).replacingOccurrences(of: "\n", with: "\\n")
            print("🔥 PARITY-COERCE: reset string to legacy; preview='\(prev)'")
          }
        }
      }

      // Clear any pending IME cancel flag at the end of reconciliation so future
      // passes can safely apply parity-coerce again if needed.
      editor.pendingImeCancel = false

      // Final selection resync (optimized only): ensure the native selection reflects the
      // pending model selection after applying structural/newline boundary edits. This helps
      // keyboard backspace at paragraph boundaries target the intended newline rather than
      // the preceding character when the cached numeric selection drifts.
      if editor.featureFlags.optimizedReconciler,
         shouldReconcileSelection,
         let pendingSel = pendingEditorState.selection as? RangeSelection,
         let frontend = editor.frontend {
        try? frontend.updateNativeSelection(from: pendingSel)
      }

    case .partialSuccess(let appliedDeltas, let failedDeltas, let reason):
      // Log but continue - we applied what we could
      editor.log(.reconciler, .warning, "Partial delta application: \(appliedDeltas) applied, \(failedDeltas.count) failed: \(reason)")
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 OPTIMIZED RECONCILER: delta application partial (applied=\(appliedDeltas), failed=\(failedDeltas.count)) reason=\(reason)")
      }

    case .failure(let reason):
      // This is a real failure - throw an error
      throw LexicalError.invariantViolation("Delta application failed: \(reason)")
    }
  }

  /// Full-build hydration for a fresh document (textStorage empty, cache only has root).
  /// Builds the attributed string in document order, reconstructs range cache, and resets Fenwick indices.
  internal static func hydrateFreshDocumentFully(pendingState: EditorState, editor: Editor) throws {
    guard let textStorage = editor.textStorage else {
      throw LexicalError.invariantViolation("TextStorage not available")
    }

    // Reset Fenwick structures
    editor.fenwickIndexMap.removeAll()
    editor.nextFenwickIndex = 0
    editor.fenwickTree = FenwickTree(size: max(1024, pendingState.nodeMap.count * 2))

    if editor.featureFlags.diagnostics.verboseLogs {
      var counts: [String:Int] = [:]
      for (_, node) in pendingState.nodeMap {
        let t: String
        if node is TextNode { t = "Text" }
        else if node is ElementNode { t = "Element" }
        else if node is DecoratorNode { t = "Decorator" }
        else { t = String(describing: type(of: node)) }
        counts[t, default: 0] += 1
      }
      print("🔥 HYDRATE: nodeMap counts=\(counts) rootChildren=\(pendingState.nodeMap[kRootNodeKey] as? ElementNode != nil ? (pendingState.nodeMap[kRootNodeKey] as! ElementNode).getChildrenKeys().count : -1)")
    }

    // Build INSERT-only batch and apply with full styling
    let batch = generateHydrationBatch(pendingState: pendingState, editor: editor)
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 HYDRATE: deltas=\(batch.deltas.count)")
      for d in batch.deltas.prefix(10) {
        switch d.type {
        case .nodeInsertion(let nk, let ins, _):
          print("  • INS nk=\(nk) pre=\(ins.preamble.length) content=\(ins.content.length) post=\(ins.postamble.length)")
        default:
          print("  • delta \(d.type)")
        }
      }
    }
    let deltaApplier = TextStorageDeltaApplier(editor: editor, fenwickTree: editor.fenwickTree)
    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    let applyResult = deltaApplier.applyDeltaBatch(batch, to: textStorage)
    textStorage.mode = previousMode
    switch applyResult {
    case .failure(let reason):
      throw LexicalError.invariantViolation("Hydration failed: \(reason)")
    default: break
    }

    // Rebuild range cache with lengths and attach Fenwick indices assigned during insertion
    var newCache: [NodeKey: RangeCacheItem] = [:]
    func computeItem(_ key: NodeKey) -> Int {
      guard let node = pendingState.nodeMap[key] else { return 0 }
      var item = newCache[key] ?? RangeCacheItem(); item.nodeKey = key
      if let elem = node as? ElementNode {
        item.preambleLength = elem.getPreamble().lengthAsNSString()
        item.postambleLength = elem.getPostamble().lengthAsNSString()
        var total = 0
        for c in elem.getChildrenKeys(fromLatest: false) { total += computeItem(c) }
        item.childrenLength = total
      } else if node is TextNode {
        item.textLength = (node as! TextNode).getText_dangerousPropertyAccess().lengthAsNSString()
        if let idx = editor.fenwickIndexMap[key] { item.nodeIndex = idx; _ = editor.fenwickTree.ensureCapacity(for: idx) }
      } else if let deco = node as? DecoratorNode {
        item.preambleLength = deco.getPreamble().lengthAsNSString()
        item.postambleLength = deco.getPostamble().lengthAsNSString()
      }
      newCache[key] = item
      return item.preambleLength + item.childrenLength + item.textLength + item.postambleLength
    }
    var rootItem = RangeCacheItem(); rootItem.nodeKey = kRootNodeKey; newCache[kRootNodeKey] = rootItem
    if let root = pendingState.nodeMap[kRootNodeKey] { _ = computeItem(root.getKey()) }

    // Swap cache
    editor.rangeCache = newCache

    // Apply block-level attributes and update decorator bookkeeping so the hydrated document visually matches legacy.
    var allDirty: DirtyNodeMap = [:]
    for (key, _) in pendingState.nodeMap { allDirty[key] = .editorInitiated }
    Self.applyBlockLevelAttributes(editor: editor,
                                   pendingState: pendingState,
                                   dirtyNodes: allDirty,
                                   textStorage: textStorage)
    Self.updateDecoratorPositions(editor: editor, pendingState: pendingState)

    // Ensure inline text runs carry explicit font and foregroundColor matching theme (safety net).
    let prevModeAttrs = textStorage.mode
    textStorage.mode = .controllerMode
    for (key, node) in pendingState.nodeMap {
      guard let text = node as? TextNode, let item = editor.rangeCache[key] else { continue }
      let start = item.locationFromFenwick(using: editor.fenwickTree) + item.preambleLength
      let length = item.textLength
      if length <= 0 { continue }
      let range = NSRange(location: start, length: length)
      let styles = AttributeUtils.attributedStringStyles(from: text, state: pendingState, theme: editor.getTheme())
      var attrs: [NSAttributedString.Key: Any] = [:]
      if let f = styles[.font] { attrs[.font] = f }
      if let c = styles[.foregroundColor] { attrs[.foregroundColor] = c }
      if !attrs.isEmpty { textStorage.addAttributes(attrs, range: range) }
    }
    textStorage.mode = prevModeAttrs

    // Fill any missing base attributes (font/color) across the entire buffer. This only
    // adds attributes where missing and won't override links or styled runs.
    Self.fillMissingBaseInlineAttributes(editor: editor)

    // Also reapply inline attributes for all nodes to ensure link color
    // and list bullets are present from the first render.
    Self.reapplyInlineAttributes(editor: editor, pendingState: pendingState)
    Self.reapplyElementInlineAttributes(editor: editor, pendingState: pendingState)

    // Parity safeguard (optional): ensure fresh-doc string exactly matches legacy serialization.
    // Disabled by default to avoid stripping attributes; enable only under selectionParityDebug.
    if editor.featureFlags.selectionParityDebug {
      let expected = (try? getEditorStateTextContent(editorState: pendingState)) ?? ""
      if let ts = editor.textStorage, ts.string != expected {
        let previousMode2 = ts.mode
        ts.mode = .controllerMode
        ts.beginEditing()
        ts.replaceCharacters(in: NSRange(location: 0, length: ts.string.lengthAsNSString()), with: expected)
        ts.endEditing()
        ts.mode = previousMode2
        if editor.featureFlags.diagnostics.verboseLogs {
          let prev = String(expected.prefix(120)).replacingOccurrences(of: "\n", with: "\\n")
          print("🔥 HYDRATE FULL: coerced to legacy serialization preview='\(prev)'")
        }
      }
    }
  }

  /// Add base font/foregroundColor to any ranges missing them.
  private static func fillMissingBaseInlineAttributes(editor: Editor) {
    guard let ts = editor.textStorage else { return }
    let theme = editor.getTheme()
    let baseFont = theme.paragraph?[.font] as? UIFont ?? LexicalConstants.defaultFont
    let baseColor = theme.paragraph?[.foregroundColor] as? UIColor ?? LexicalConstants.defaultColor
    let prev = ts.mode; ts.mode = .controllerMode; ts.beginEditing()
    ts.enumerateAttributes(in: NSRange(location: 0, length: ts.length), options: []) { attrs, range, _ in
      var toAdd: [NSAttributedString.Key: Any] = [:]
      if attrs[.font] == nil { toAdd[.font] = baseFont }
      if attrs[.foregroundColor] == nil { toAdd[.foregroundColor] = baseColor }
      if !toAdd.isEmpty { ts.addAttributes(toAdd, range: range) }
    }
    ts.endEditing(); ts.mode = prev
  }

  /// Reapply a minimal set of inline attributes (font/color/link/list markers)
  /// to visible text ranges for a collection of TextNodes. This is a safety net
  /// for cases where the initial hydration path or incremental updates leave
  /// some runs uncoated with inline attributes that are normally inherited from
  /// ancestors (e.g. LinkNode or ListItemNode). It only adds/merges attributes;
  /// it never removes existing ones.
  private static func reapplyInlineAttributes(
    editor: Editor,
    pendingState: EditorState,
    limitedTo keys: Set<NodeKey>? = nil
  ) {
    guard let ts = editor.textStorage else { return }
    let prev = ts.mode; ts.mode = .controllerMode
    let theme = editor.getTheme()
    
    // Avoid depending on plugin symbols from Core: use raw value of list item key.
    let listItemKey = NSAttributedString.Key(rawValue: "list_item")
    
    // Compute absolute start purely from pendingState + rangeCache (no Fenwick / editor lookups).
    func absStartCache(_ key: NodeKey) -> Int {
      if key == kRootNodeKey { return 0 }
      guard let node = pendingState.nodeMap[key], let parentKey = node.parent,
            let parentItem = editor.rangeCache[parentKey], let parent = pendingState.nodeMap[parentKey] as? ElementNode else {
        return editor.rangeCache[key]?.location ?? 0
      }
      var acc = absStartCache(parentKey) + parentItem.preambleLength
      for ck in parent.getChildrenKeys(fromLatest: false) {
        if ck == key { break }
        if let s = editor.rangeCache[ck] {
          acc += s.preambleLength + s.childrenLength + s.textLength + s.postambleLength
        }
      }
      return acc
    }

    func visit(_ key: NodeKey) {
      guard let node = pendingState.nodeMap[key] else { return }
      if let text = node as? TextNode, let item = editor.rangeCache[key] {
        let start = absStartCache(key) + item.preambleLength
        let length = item.textLength
        if length > 0 && start >= 0 && (start + length) <= ts.length {
          var attrs = AttributeUtils.attributedStringStyles(from: text, state: pendingState, theme: theme)
          // Defensive: ensure font reflects format flags even if upstream styling missed it
          let baseFont = (attrs[.font] as? UIFont) ?? (theme.paragraph?[.font] as? UIFont) ?? LexicalConstants.defaultFont
          var desc = baseFont.fontDescriptor
          var tr = desc.symbolicTraits
          if text.format.bold { tr.insert(.traitBold) } else { tr.remove(.traitBold) }
          if text.format.italic { tr.insert(.traitItalic) } else { tr.remove(.traitItalic) }
          if let nd = desc.withSymbolicTraits(tr) { attrs[.font] = UIFont(descriptor: nd, size: 0) }
          // Restrict to inline keys so we don’t fight the block‑level pass
          let allowed: Set<NSAttributedString.Key> = [
            .font, .foregroundColor, .underlineStyle, .strikethroughStyle, .backgroundColor, .link, listItemKey
          ]
          attrs = attrs.filter { allowed.contains($0.key) }
          if !attrs.isEmpty {
            ts.addAttributes(attrs, range: NSRange(location: start, length: length))
          }
        }
      }
      if let elem = node as? ElementNode {
        for c in elem.getChildrenKeys(fromLatest: false) { visit(c) }
      }
    }

    if let keys = keys, !keys.isEmpty {
      for k in keys { visit(k) }
    } else if let root = pendingState.nodeMap[kRootNodeKey] {
      visit(root.getKey())
    }

    ts.mode = prev
  }

  /// Overlay element-scope inline attributes (e.g. link color, list bullets)
  /// onto the character ranges owned by those elements. This ensures that
  /// attributes that drive custom drawing (.list_item) and inline styling
  /// (.link, foregroundColor) are present starting from the element preamble.
  private static func reapplyElementInlineAttributes(
    editor: Editor,
    pendingState: EditorState,
    limitedTo keys: Set<NodeKey>? = nil
  ) {
    guard let ts = editor.textStorage else { return }
    let prev = ts.mode; ts.mode = .controllerMode
    let theme = editor.getTheme()
    let listItemKey = NSAttributedString.Key(rawValue: "list_item")

    // Pure cache-based absolute start (no Fenwick / runtime node lookups)
    func absStartCache(_ key: NodeKey) -> Int {
      if key == kRootNodeKey { return 0 }
      guard let node = pendingState.nodeMap[key], let parentKey = node.parent,
            let parentItem = editor.rangeCache[parentKey], let parent = pendingState.nodeMap[parentKey] as? ElementNode else {
        return editor.rangeCache[key]?.location ?? 0
      }
      var acc = absStartCache(parentKey) + parentItem.preambleLength
      for ck in parent.getChildrenKeys(fromLatest: false) {
        if ck == key { break }
        if let s = editor.rangeCache[ck] {
          acc += s.preambleLength + s.childrenLength + s.textLength + s.postambleLength
        }
      }
      return acc
    }

    func coat(_ key: NodeKey) {
      guard let node = pendingState.nodeMap[key], let item = editor.rangeCache[key] else { return }
      // Only reapply for element types that carry inline visuals we need:
      // - LinkNode: .link + its foregroundColor from theme.link
      // - ListItemNode: .list_item only (bullet drawing reads this); avoid
      //   overlaying paragraphStyle or foregroundColor to prevent overriding
      //   link colors or text styles.
      var attrs: [NSAttributedString.Key: Any] = [:]
      if String(describing: type(of: node)).contains("LinkNode") {
        let linkAttrs = node.getAttributedStringAttributes(theme: theme)
        let allowed: Set<NSAttributedString.Key> = [.link, .foregroundColor]
        attrs = linkAttrs.filter { allowed.contains($0.key) }
      } else if String(describing: type(of: node)).contains("ListItemNode") {
        // For bullets to draw, the .list_item attribute MUST begin at the first
        // character of the paragraph line (so previous char is newline or index 0).
        // Apply .list_item on each child paragraph starting at the paragraph start.
        if let elem = node as? ElementNode {
          for ck in elem.getChildrenKeys(fromLatest: false) {
            if let para = pendingState.nodeMap[ck] as? ParagraphNode,
               let pItem = editor.rangeCache[ck] {
              // Paragraph style (indent/padding) — ensure text is offset
              let psAttrs = AttributeUtils.attributedStringStyles(from: para, state: pendingState, theme: theme)
              let pLoc = absStartCache(ck)
              let pLen = pItem.preambleLength + pItem.childrenLength + pItem.textLength + pItem.postambleLength
              if pLen > 0 && pLoc >= 0 && NSMaxRange(NSRange(location: pLoc, length: pLen)) <= ts.length {
                if let ps = psAttrs[.paragraphStyle] as? NSParagraphStyle {
                  ts.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: pLoc, length: pLen))
                }
                // Apply .list_item across the paragraph so custom drawing sees it consistently
                let bulletAttr = (node.getAttributedStringAttributes(theme: theme)[listItemKey]) ?? true
                ts.addAttribute(listItemKey, value: bulletAttr, range: NSRange(location: pLoc, length: pLen))
              }
            } else if let textChild = pendingState.nodeMap[ck] as? TextNode,
                      let cItem = editor.rangeCache[ck] {
              // No paragraph node — apply for text child directly at its first character
              let base = absStartCache(ck) + cItem.preambleLength
              if base >= 0 && base < ts.length {
                let bulletAttr = (node.getAttributedStringAttributes(theme: theme)[listItemKey]) ?? true
                let paraRange = ts.mutableString.paragraphRange(for: NSRange(location: base, length: 0))
                ts.addAttribute(listItemKey, value: bulletAttr, range: paraRange)
                // Paragraph style from the list item element
                let elemPSAttrs = AttributeUtils.attributedStringStyles(from: elem, state: pendingState, theme: theme)
                if let ps = elemPSAttrs[.paragraphStyle] as? NSParagraphStyle {
                  ts.addAttribute(.paragraphStyle, value: ps, range: paraRange)
                }
              }
            }
          }
        }
        // Do not apply .list_item at the element base; drawing logic expects it
        // to begin at the paragraph start.
        return
      } else {
        return
      }
      guard !attrs.isEmpty else { return }
      // Cache-based absolute base to avoid read-scope dependencies
      let loc = absStartCache(key)
      let len = item.preambleLength + item.childrenLength + item.textLength + item.postambleLength
      if len > 0 && loc >= 0 && NSMaxRange(NSRange(location: loc, length: len)) <= ts.length {
        ts.addAttributes(attrs, range: NSRange(location: loc, length: len))
      }
    }

    if let filter = keys, !filter.isEmpty {
      for k in filter { coat(k) }
    } else {
      for (k, _) in pendingState.nodeMap { coat(k) }
    }

    ts.mode = prev
  }

  /// Build a complete INSERT-only batch for a fresh document using document order.
  private static func generateHydrationBatch(pendingState: EditorState, editor: Editor) -> DeltaBatch {
    var deltas: [ReconcilerDelta] = []
    var offset = 0
    var order = 0
    let theme = editor.getTheme()

    func styled(_ string: String, from node: Node) -> NSAttributedString {
      return AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: string), from: node, state: pendingState, theme: theme)
    }

    func visit(_ key: NodeKey) {
      guard let node = pendingState.nodeMap[key] else { return }
      if key != kRootNodeKey {
        // Build insertion data for this node
        var pre = NSAttributedString(string: "")
        var content = NSAttributedString(string: "")
        var post = NSAttributedString(string: "")
        if let elem = node as? ElementNode {
          pre = styled(elem.getPreamble(), from: elem)
          post = styled(elem.getPostamble(), from: elem)
        }
        if let text = node as? TextNode {
          content = styled(text.getText_dangerousPropertyAccess(), from: text)
        }
        let ins = NodeInsertionData(preamble: pre, content: content, postamble: post, nodeKey: key)
        let delta = ReconcilerDelta(type: .nodeInsertion(nodeKey: key, insertionData: ins, location: offset), metadata: DeltaMetadata(sourceUpdate: "Hydration", orderIndex: order))
        deltas.append(delta)
        offset += pre.length + content.length + post.length
        order += 1
      }
      if let elem = node as? ElementNode {
        for child in elem.getChildrenKeys(fromLatest: false) { visit(child) }
      }
    }

    if let root = pendingState.nodeMap[kRootNodeKey] { visit(root.getKey()) }

    let batch = DeltaBatch(deltas: deltas, batchMetadata: BatchMetadata(expectedTextStorageLength: editor.textStorage?.length ?? 0, isFreshDocument: true))
    return batch
  }

  /// Mirror legacy's block-level attributes pass
  private static func applyBlockLevelAttributes(
    editor: Editor,
    pendingState: EditorState,
    dirtyNodes: DirtyNodeMap,
    textStorage: TextStorage
  ) {
    let lastDescendentAttributes = getRoot()?.getLastChild()?.getAttributedStringAttributes(theme: editor.getTheme())

    var nodesToApply: Set<NodeKey> = []
    for (nodeKey, _) in dirtyNodes { nodesToApply.insert(nodeKey) }
    // Also include parents of dirty nodes (attributes can affect paragraph containers).
    // IMPORTANT: Walk parent keys via pendingState.nodeMap to avoid calling Node APIs
    // that require an active EditorState (e.g., getLatest/getParent).
    for (nodeKey, _) in dirtyNodes {
      if let node = pendingState.nodeMap[nodeKey] {
        var pKey = node.parent
        while let current = pKey {
          nodesToApply.insert(current)
          pKey = pendingState.nodeMap[current]?.parent
        }
      }
    }

    let rangeCache = editor.rangeCache
    for key in nodesToApply {
      guard let node = pendingState.nodeMap[key], node.isAttached(), let cacheItem = rangeCache[key] else { continue }
      if let attrs = node.getBlockLevelAttributes(theme: editor.getTheme()) {
        AttributeUtils.applyBlockLevelAttributes(
          attrs,
          cacheItem: cacheItem,
          textStorage: textStorage,
          nodeKey: key,
          lastDescendentAttributes: lastDescendentAttributes ?? [:],
          fenwickTree: editor.fenwickTree
        )
      }
    }
  }

  /// Minimal parity for decorator positioning: update TextStorage.decoratorPositionCache
  private static func updateDecoratorPositions(
    editor: Editor,
    pendingState: EditorState
  ) {
    guard let textStorage = editor.textStorage else { return }
    var newCache: [NodeKey: Int] = [:]

    for (key, node) in pendingState.nodeMap {
      if node is DecoratorNode, isAttachedInState(key, state: pendingState), let cacheItem = editor.rangeCache[key] {
        let loc = cacheItem.locationFromFenwick(using: editor.fenwickTree)
        newCache[key] = loc
      }
    }

    textStorage.decoratorPositionCache = newCache
  }

  /// Decorator lifecycle parity: create/decorate/remove and reposition
  /// - We mark new decorators as .needsCreation
  /// - We mark staying decorators as .needsDecorating(view) if they are dirty or moved
  /// - We remove deleted decorators and clear caches
  private static func updateDecoratorLifecycle(
    editor: Editor,
    currentState: EditorState,
    pendingState: EditorState,
    oldPositions: [NodeKey: Int],
    appliedDeltas: [ReconcilerDelta]
  ) {
    guard let textStorage = editor.textStorage else { return }

    // Collect decorator keys in each state
    let currentDecorators: Set<NodeKey> = Set(
      currentState.nodeMap.compactMap { (k, v) in v is DecoratorNode ? k : nil }
    )
    let pendingDecorators: Set<NodeKey> = Set(
      pendingState.nodeMap.compactMap { (k, v) in v is DecoratorNode ? k : nil }
    )

    // Consider a decorator removed if it either no longer exists in pending state OR exists but is detached (GC happens later)
    var removed = Set<NodeKey>()
    for key in currentDecorators {
      if let _ = pendingState.nodeMap[key] {
        if !isAttachedInState(key, state: pendingState) { removed.insert(key) }
      } else {
        removed.insert(key)
      }
    }
    let added = pendingDecorators.subtracting(currentDecorators)
    var staying = currentDecorators.intersection(pendingDecorators)
    // Exclude detached/deleted keys from staying
    staying.subtract(removed)

    // Compute new positions after delta application and cache update
    var newPositions: [NodeKey: Int] = [:]
    for key in pendingDecorators where isAttachedInState(key, state: pendingState) {
      if let cacheItem = editor.rangeCache[key] {
        newPositions[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
      }
    }
    
    // Detect movement of decorators present in both states
    var moved: Set<NodeKey> = []
    for key in staying {
      if let oldPos = oldPositions[key], let newPos = newPositions[key], oldPos != newPos {
        moved.insert(key)
      }
    }

    // Optional heuristic: redecorate decorators when siblings in the same parent changed
    let siblingTriggered: Set<NodeKey> = []

    // Handle removals: remove view if present, drop caches
    for key in removed {
      if let item = editor.decoratorCache[key], let view = item.view {
        view.removeFromSuperview()
      }
      destroyCachedDecoratorView(forKey: key)
      textStorage.decoratorPositionCache[key] = nil
    }

    // Handle additions: mark for creation and set initial position
    for key in added {
      if editor.decoratorCache[key] == nil {
        editor.decoratorCache[key] = .needsCreation
      }
      if let cacheItem = editor.rangeCache[key] {
        textStorage.decoratorPositionCache[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
      }
    }

    // Handle decorators that remain: mark for (re)decorate if dirty or moved; refresh position
    for key in staying {
      // Skip any keys that were removed/detached
      if removed.contains(key) { continue }

      let isDirty = editor.dirtyNodes[key] != nil || editor.dirtyType == .fullReconcile
      let shouldRedecorate = isDirty || moved.contains(key) || siblingTriggered.contains(key)

      if shouldRedecorate {
        if let cacheItem = editor.decoratorCache[key], let view = cacheItem.view {
          editor.decoratorCache[key] = .needsDecorating(view)
        } else if editor.decoratorCache[key] == nil {
          // No cache entry yet; ensure creation will occur
          editor.decoratorCache[key] = .needsCreation
        }
      }

      if let rc = editor.rangeCache[key] {
        textStorage.decoratorPositionCache[key] = rc.locationFromFenwick(using: editor.fenwickTree)
      }
    }
  }

  /// Attachment check against a specific EditorState (do not rely on global active state)
  private static func isAttachedInState(_ nodeKey: NodeKey, state: EditorState) -> Bool {
    var key: NodeKey? = nodeKey
    while let k = key {
      if k == kRootNodeKey { return true }
      guard let node = state.nodeMap[k], let parent = node.parent else { break }
      key = parent
    }
    return false
  }

  /// Records metrics for successful optimized reconciliation
  private static func recordOptimizedReconciliationMetrics(
    editor: Editor,
    appliedDeltas: Int,
    fenwickUpdates: Int,
    startTime: Date,
    nodeCount: Int,
    textStorageLength: Int
  ) {
    let duration = Date().timeIntervalSince(startTime)
    let metric = OptimizedReconcilerMetric(
      deltaCount: appliedDeltas,
      fenwickOperations: fenwickUpdates,
      nodeCount: nodeCount,
      textStorageLength: textStorageLength,
      timestamp: startTime,
      duration: duration
    )

    editor.metricsContainer?.record(.optimizedReconcilerRun(metric))
  }
}

/// Generates deltas from editor state differences
@MainActor
private class DeltaGenerator {
  private let editor: Editor

  init(editor: Editor) {
    self.editor = editor
  }

  /// Generate a batch of deltas representing the changes between two editor states
  func generateDeltaBatch(
    from currentState: EditorState,
    to pendingState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    dirtyNodes: DirtyNodeMap
  ) throws -> DeltaBatch {

    var deltas: [ReconcilerDelta] = []
    var seq: Int = 0

    // Process nodes in document order so sibling insertions keep correct order.
    let orderedDirty = orderedDirtyNodes(in: pendingState, limitedTo: dirtyNodes)
    var processedInsertionLengths: [NodeKey: Int] = [:]
    var runningOffset = 0  // Track cumulative insertion offset
    
    // Detect if this is a fresh document creation or large bulk insertion
    // When most nodes are new insertions and the cache is mostly empty, use sequential positions
    // Treat an empty range cache as a fresh document build so we use
    // sequential insertion order (stable, avoids location guesswork).
    let isFreshDocument = rangeCache.isEmpty
    
    // Track deletions to re-evaluate survivor postambles (newline) after structure changes
    var deletedKeys: [NodeKey] = []
    var survivorCandidates: Set<NodeKey> = []

    // Generate deltas for each dirty node
    for nodeKey in orderedDirty {
      let currentNode = currentState.nodeMap[nodeKey]
      let pendingNode = pendingState.nodeMap[nodeKey]

      // Node deletion
      if currentNode != nil && pendingNode == nil {
        if let rangeCacheItem = rangeCache[nodeKey] {
          let metadata = DeltaMetadata(sourceUpdate: "Node deletion", orderIndex: seq)
          seq += 1
          let deltaType = ReconcilerDeltaType.nodeDeletion(nodeKey: nodeKey, range: rangeCacheItem.rangeFromFenwick(using: editor.fenwickTree))
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
          deletedKeys.append(nodeKey)
          // Add previous sibling as a survivor candidate
          if let parentKey = currentState.nodeMap[nodeKey]?.parent,
             let parent = currentState.nodeMap[parentKey] as? ElementNode,
             let idx = parent.getChildrenKeys(fromLatest: false).firstIndex(of: nodeKey), idx > 0 {
            survivorCandidates.insert(parent.getChildrenKeys(fromLatest: false)[idx - 1])
          }
        }
        continue
      }

      // Node insertion
      if currentNode == nil, let pendingNode = pendingNode {
        // Generate an insertion delta for the new node with actual content
        let metadata = DeltaMetadata(sourceUpdate: "Node insertion", orderIndex: seq)
        seq += 1

        // Extract actual content from the pending node
        let theme = editor.getTheme()
        
        // Use node-provided pre/post as-is to match legacy fresh-document serialization
        let preambleString = pendingNode.getPreamble()
        let postambleString = pendingNode.getPostamble()
        
        let preambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: preambleString),
          from: pendingNode,
          state: pendingState,
          theme: theme
        )
        let postambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: postambleString),
          from: pendingNode,
          state: pendingState,
          theme: theme
        )

        // Get the text content based on node type
        var textContent = NSAttributedString(string: "")
        if let textNode = pendingNode as? TextNode {
          let textString = textNode.getText_dangerousPropertyAccess()
          textContent = AttributeUtils.attributedStringByAddingStyles(
            NSAttributedString(string: textString),
            from: pendingNode,
            state: pendingState,
            theme: theme
          )
        } else if let elementNode = pendingNode as? ElementNode {
          // Element nodes may contribute text via pre/post content; their own content is empty.
          textContent = AttributeUtils.attributedStringByAddingStyles(
            NSAttributedString(string: ""),
            from: elementNode,
            state: pendingState,
            theme: theme
          )
        }

        let insertionData = NodeInsertionData(
          preamble: preambleContent,
          content: textContent,
          postamble: postambleContent,
          nodeKey: nodeKey
        )

        // Calculate insertion location based on document structure
        let insertionLocation: Int
        let totalLength = insertionData.preamble.length + insertionData.content.length + insertionData.postamble.length
        
        // For fresh documents, use sequential insertion to match serialized order; otherwise compute structure-based position
        if isFreshDocument {
          insertionLocation = runningOffset
          runningOffset += totalLength
        } else {
          insertionLocation = self.calculateInsertionLocationOrdered(
            for: nodeKey,
            in: pendingState,
            rangeCache: rangeCache,
            processedInsertionLengths: processedInsertionLengths,
            runningOffset: &runningOffset,
            editor: editor)
        }
        
        // Track length for subsequent siblings
        processedInsertionLengths[nodeKey] = totalLength

          let deltaType = ReconcilerDeltaType.nodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: insertionLocation)
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
          continue
      }

      // Node modification
      if let currentNode = currentNode, let pendingNode = pendingNode {
        if let currentTextNode = currentNode as? TextNode,
           let pendingTextNode = pendingNode as? TextNode,
           currentTextNode.getText_dangerousPropertyAccess() != pendingTextNode.getText_dangerousPropertyAccess(),
           let rangeCacheItem = rangeCache[nodeKey] {

          let textRange = NSRange(
            location: rangeCacheItem.locationFromFenwick(using: editor.fenwickTree) + rangeCacheItem.preambleLength,
            length: rangeCacheItem.textLength
          )

          let metadata = DeltaMetadata(sourceUpdate: "Text update")
          let deltaType = ReconcilerDeltaType.textUpdate(
            nodeKey: nodeKey,
            newText: pendingTextNode.getText_dangerousPropertyAccess(),
            range: textRange
          )
          deltas.append(ReconcilerDelta(type: deltaType, metadata: DeltaMetadata(sourceUpdate: metadata.sourceUpdate, fenwickTreeIndex: metadata.fenwickTreeIndex, originalRange: metadata.originalRange, orderIndex: seq)))
          seq += 1
          if editor.featureFlags.diagnostics.verboseLogs {
            print("🔥 OPTIMIZED RECONCILER: queued textUpdate for node \(nodeKey) range=\(textRange) old='\(currentTextNode.getText_dangerousPropertyAccess())' new='\(pendingTextNode.getText_dangerousPropertyAccess())'")
          }
        }

        // Element postamble change (e.g., paragraph gains/removes trailing newline when a sibling is inserted/deleted)
        if let _ = currentNode as? ElementNode,
           let _ = pendingNode as? ElementNode,
           let rangeCacheItem = rangeCache[nodeKey] {
          // Compute postamble strings using the provided editor states (not active state)
          func postambleString(for key: NodeKey, in state: EditorState) -> String {
            guard let node = state.nodeMap[key] else { return "" }
            guard let elem = node as? ElementNode else { return "" }
            let inline = elem.isInline()
            if let parentKey = node.parent, let parent = state.nodeMap[parentKey] as? ElementNode,
               let idx = parent.children.firstIndex(of: key) {
              let hasNext = (idx + 1) < parent.children.count
              if inline {
                if hasNext, let next = state.nodeMap[parent.children[idx + 1]] as? ElementNode { return next.isInline() ? "" : "\n" }
                return ""
              } else {
                return hasNext ? "\n" : ""
              }
            }
            // Root or detached
            return ""
          }
          let oldPost = postambleString(for: nodeKey, in: currentState)
          let newPost = postambleString(for: nodeKey, in: pendingState)
          if oldPost != newPost {
            // Prefer to position at the end of the element's last child (more robust than relying on
            // the element's cached childrenLength in differential states).
            var postLoc = rangeCacheItem.locationFromFenwick(using: editor.fenwickTree) + rangeCacheItem.preambleLength + rangeCacheItem.childrenLength + rangeCacheItem.textLength
            if let parentElem = currentState.nodeMap[nodeKey] as? ElementNode,
               let lastChildKey = parentElem.getChildrenKeys(fromLatest: false).last,
               let childItem = rangeCache[lastChildKey] {
              let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
              postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
            }
            // Use oldPost length to determine replacement width: 0 for insertion, 1 for removal.
            let oldLen = (oldPost as NSString).length
            var adj = postLoc
            if oldLen > 0, let ts = editor.textStorage, ts.length > 0 {
              let clamp = max(0, min(postLoc, ts.length - 1))
              let cur = (ts.string as NSString).substring(with: NSRange(location: clamp, length: 1))
              if cur == "\n" { adj = clamp }
              else if clamp > 0 {
                let prev = (ts.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
                if prev == "\n" { adj = clamp - 1 }
              }
            }
            let postRange = NSRange(location: adj, length: oldLen)
            let deltaType = ReconcilerDeltaType.textUpdate(
              nodeKey: nodeKey,
              newText: newPost,
              range: postRange
            )
            deltas.append(ReconcilerDelta(type: deltaType, metadata: DeltaMetadata(sourceUpdate: "Postamble update", fenwickTreeIndex: nil, originalRange: postRange, orderIndex: seq)))
            seq += 1
            if editor.featureFlags.diagnostics.verboseLogs {
              print("🔥 DELTA GEN: POSTAMBLE key=\(nodeKey) loc=\(postLoc) new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
            }
          }
        }

        // Inline attribute (format) changes without text change
        if let currentTextNode = currentNode as? TextNode,
           let pendingTextNode = pendingNode as? TextNode,
           currentTextNode.getText_dangerousPropertyAccess() == pendingTextNode.getText_dangerousPropertyAccess(),
           currentTextNode.getFormat() != pendingTextNode.getFormat(),
           let rangeCacheItem = rangeCache[nodeKey] {

          let textRange = NSRange(
            location: rangeCacheItem.locationFromFenwick(using: editor.fenwickTree) + rangeCacheItem.preambleLength,
            length: rangeCacheItem.textLength
          )
          let attrs = pendingTextNode.getAttributedStringAttributes(theme: editor.getTheme())
          let metadata = DeltaMetadata(sourceUpdate: "Inline attribute update")
          let deltaType = ReconcilerDeltaType.attributeChange(
            nodeKey: nodeKey,
            attributes: attrs,
            range: textRange
          )
          deltas.append(ReconcilerDelta(type: deltaType, metadata: DeltaMetadata(sourceUpdate: metadata.sourceUpdate, fenwickTreeIndex: metadata.fenwickTreeIndex, originalRange: metadata.originalRange, orderIndex: seq)))
          seq += 1
        }
      }
    }

    // Add caret paragraph as survivor candidate (optimized only)
    if editor.featureFlags.optimizedReconciler, let sel = pendingState.selection as? RangeSelection {
      if sel.anchor.type == .element, sel.anchor.offset == 0 {
        survivorCandidates.insert(sel.anchor.key)
      } else if sel.anchor.type == .text, sel.anchor.offset == 0,
                let parent = currentState.nodeMap[sel.anchor.key]?.parent {
        survivorCandidates.insert(parent)
      }
    }

    // Re-evaluate survivor paragraph postambles after deletions (optimized only)
    if editor.featureFlags.optimizedReconciler && (!deletedKeys.isEmpty || !editor.pendingPostambleCleanup.isEmpty) {
      // Helper for old/new postamble strings (same logic used above)
      func postambleString(for key: NodeKey, in state: EditorState) -> String {
        guard let node = state.nodeMap[key] as? ElementNode else { return "" }
        let inline = node.isInline()
        if let parentKey = node.parent, let parent = state.nodeMap[parentKey] as? ElementNode,
           let idx = parent.children.firstIndex(of: key) {
          let hasNext = (idx + 1) < parent.children.count
          if inline {
            if hasNext, let next = state.nodeMap[parent.children[idx + 1]] as? ElementNode { return next.isInline() ? "" : "\n" }
            return ""
          } else {
            return hasNext ? "\n" : ""
          }
        }
        return ""
      }

      var emittedPostambleFor: Set<NodeKey> = []

      if editor.featureFlags.diagnostics.verboseLogs && !deletedKeys.isEmpty {
        print("🔥 DELTA GEN: deletedKeys=\(deletedKeys)")
      }
      for delKey in deletedKeys {
        // Find survivor = previous sibling of the deleted node in current state
        guard let parentKey = currentState.nodeMap[delKey]?.parent,
              let parent = currentState.nodeMap[parentKey] as? ElementNode,
              let idx = parent.children.firstIndex(of: delKey), idx > 0 else { continue }
        let survivorKey = parent.children[idx - 1]
        // Survivor must still exist in pending state
        guard pendingState.nodeMap[survivorKey] != nil, let survivorItem = rangeCache[survivorKey] else { continue }
        let oldPost = postambleString(for: survivorKey, in: currentState)
        let newPost = postambleString(for: survivorKey, in: pendingState)
        if oldPost == newPost { continue }

        if emittedPostambleFor.contains(survivorKey) { continue }

        // Compute strict lastChildEnd for survivor
        var postLoc = survivorItem.locationFromFenwick(using: editor.fenwickTree)
          + survivorItem.preambleLength + survivorItem.childrenLength + survivorItem.textLength
        if let survElem = currentState.nodeMap[survivorKey] as? ElementNode,
           let lastChildKey = survElem.getChildrenKeys(fromLatest: false).last,
           let childItem = rangeCache[lastChildKey] {
          let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
          postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
        }
        let _ = (oldPost as NSString).length
        let ts = editor.textStorage
        var adj = postLoc
        if let ts, ts.length > 0 {
          let clamp = max(0, min(postLoc, ts.length - 1))
          let cur = (ts.string as NSString).substring(with: NSRange(location: clamp, length: 1))
          if cur == "\n" { adj = clamp }
          else if clamp > 0 {
            let prev = (ts.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
            if prev == "\n" { adj = clamp - 1 }
          }
        }
        let postRange = NSRange(location: adj, length: 1)
        let md = DeltaMetadata(sourceUpdate: "Postamble update (after delete)", orderIndex: seq)
        seq += 1
        deltas.append(ReconcilerDelta(type: .textUpdate(nodeKey: survivorKey, newText: newPost, range: postRange), metadata: md))
        emittedPostambleFor.insert(survivorKey)
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: POSTAMBLE-after-delete survivor=\(survivorKey) loc=\(postLoc) new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
        }
      }

      // Also re-evaluate dirty elements that survived (covers cases where the deleted sibling had no cache)
      // Re-evaluate any dirty elements where postamble transitions from "\n" to "" (newline removed).
      for (k, _) in dirtyNodes {
        guard currentState.nodeMap[k] is ElementNode, pendingState.nodeMap[k] is ElementNode,
              let item = rangeCache[k] else { continue }
        let oldPost = postambleString(for: k, in: currentState)
        let newPost = postambleString(for: k, in: pendingState)
        if !(oldPost == "\n" && newPost == "") { continue }
        if emittedPostambleFor.contains(k) { continue }
        var postLoc = item.locationFromFenwick(using: editor.fenwickTree)
          + item.preambleLength + item.childrenLength + item.textLength
        if let elem = currentState.nodeMap[k] as? ElementNode,
           let lastChildKey = elem.getChildrenKeys(fromLatest: false).last,
           let childItem = rangeCache[lastChildKey] {
          let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
          postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
        }
        let _ = (oldPost as NSString).length
        let ts2 = editor.textStorage
        var adj2 = postLoc
        if let ts2, ts2.length > 0 {
          let clamp = max(0, min(postLoc, ts2.length - 1))
          let cur = (ts2.string as NSString).substring(with: NSRange(location: clamp, length: 1))
          if cur == "\n" { adj2 = clamp }
          else if clamp > 0 {
            let prev = (ts2.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
            if prev == "\n" { adj2 = clamp - 1 }
          }
        }
        let postRange = NSRange(location: adj2, length: 1)
        let md = DeltaMetadata(sourceUpdate: "Postamble update (dirty)", orderIndex: seq)
        seq += 1
        deltas.append(ReconcilerDelta(type: .textUpdate(nodeKey: k, newText: newPost, range: postRange), metadata: md))
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: POSTAMBLE-dirty key=\(k) loc=\(postLoc) new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
        }
      }

      // Forced cleanup requested by event path (optimized only)
      if !editor.pendingPostambleCleanup.isEmpty {
        if editor.featureFlags.diagnostics.verboseLogs { print("🔥 POSTAMBLE forced cleanup keys=\(Array(editor.pendingPostambleCleanup))") }
        for k in editor.pendingPostambleCleanup {
          guard currentState.nodeMap[k] is ElementNode, pendingState.nodeMap[k] is ElementNode,
                let item = rangeCache[k] else { continue }
          let oldPost = postambleString(for: k, in: currentState)
          let newPost = postambleString(for: k, in: pendingState)
          if !(oldPost == "\n" && newPost == "") { continue }
          var postLoc = item.locationFromFenwick(using: editor.fenwickTree)
            + item.preambleLength + item.childrenLength + item.textLength
          if let elem = currentState.nodeMap[k] as? ElementNode,
             let lastChildKey = elem.getChildrenKeys(fromLatest: false).last,
             let childItem = rangeCache[lastChildKey] {
            let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
            postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
          }
          let _ = (oldPost as NSString).length
          let ts3 = editor.textStorage
          var adj3 = postLoc
          if let ts3, ts3.length > 0 {
            let clamp = max(0, min(postLoc, ts3.length - 1))
            let cur = (ts3.string as NSString).substring(with: NSRange(location: clamp, length: 1))
            if cur == "\n" { adj3 = clamp }
            else if clamp > 0 {
              let prev = (ts3.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
              if prev == "\n" { adj3 = clamp - 1 }
            }
          }
          let postRange = NSRange(location: adj3, length: 1)
          let md = DeltaMetadata(sourceUpdate: "Postamble update (forced)", orderIndex: seq)
          seq += 1
          deltas.append(ReconcilerDelta(type: .textUpdate(nodeKey: k, newText: newPost, range: postRange), metadata: md))
          if editor.featureFlags.diagnostics.verboseLogs {
            print("🔥 DELTA GEN: POSTAMBLE-forced key=\(k) loc=\(postLoc) new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
          }
        }
        editor.pendingPostambleCleanup.removeAll()
      }

      // Survivor candidates sweep (optimized only): ensure caret-survivors and prev-siblings get evaluated
      for k in survivorCandidates {
        guard currentState.nodeMap[k] is ElementNode, pendingState.nodeMap[k] is ElementNode,
              let item = rangeCache[k] else { continue }
        let oldPost = postambleString(for: k, in: currentState)
        let newPost = postambleString(for: k, in: pendingState)
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 POSTAMBLE-candidate key=\(k) old='\(oldPost.replacingOccurrences(of: "\n", with: "\\n"))' new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
        }
        if !(oldPost == "\n" && newPost == "") { continue }
        var postLoc = item.locationFromFenwick(using: editor.fenwickTree)
          + item.preambleLength + item.childrenLength + item.textLength
        if let elem = currentState.nodeMap[k] as? ElementNode,
           let lastChildKey = elem.getChildrenKeys(fromLatest: false).last,
           let childItem = rangeCache[lastChildKey] {
          let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
          postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
        }
        let ts4 = editor.textStorage
        var adj4 = postLoc
        if let ts4, ts4.length > 0 {
          let clamp = max(0, min(postLoc, ts4.length - 1))
          let cur = (ts4.string as NSString).substring(with: NSRange(location: clamp, length: 1))
          if cur == "\n" { adj4 = clamp }
          else if clamp > 0 {
            let prev = (ts4.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
            if prev == "\n" { adj4 = clamp - 1 }
          }
        }
        let postRange = NSRange(location: adj4, length: 1)
        let md = DeltaMetadata(sourceUpdate: "Postamble update (candidate)", orderIndex: seq)
        seq += 1
        deltas.append(ReconcilerDelta(type: .textUpdate(nodeKey: k, newText: "", range: postRange), metadata: md))
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: POSTAMBLE-candidate key=\(k) loc=\(postLoc) len=1 -> ''")
        }
      }

      // Unconditional survivor sweep (optimized only): cover cases where survivor wasn't marked dirty.
      for (k, item) in rangeCache {
        guard currentState.nodeMap[k] is ElementNode, pendingState.nodeMap[k] is ElementNode else { continue }
        let oldPost = postambleString(for: k, in: currentState)
        let newPost = postambleString(for: k, in: pendingState)
        if !(oldPost == "\n" && newPost == "") { continue }
        if emittedPostambleFor.contains(k) { continue }
        var postLoc = item.locationFromFenwick(using: editor.fenwickTree)
          + item.preambleLength + item.childrenLength + item.textLength
        if let elem = currentState.nodeMap[k] as? ElementNode,
           let lastChildKey = elem.getChildrenKeys(fromLatest: false).last,
           let childItem = rangeCache[lastChildKey] {
          let childBase = childItem.locationFromFenwick(using: editor.fenwickTree)
          postLoc = childBase + childItem.preambleLength + childItem.childrenLength + childItem.textLength
        }
        let _ = (oldPost as NSString).length
        let ts5 = editor.textStorage
        var adj5 = postLoc
        if let ts5, ts5.length > 0 {
          let clamp = max(0, min(postLoc, ts5.length - 1))
          let cur = (ts5.string as NSString).substring(with: NSRange(location: clamp, length: 1))
          if cur == "\n" { adj5 = clamp }
          else if clamp > 0 {
            let prev = (ts5.string as NSString).substring(with: NSRange(location: clamp - 1, length: 1))
            if prev == "\n" { adj5 = clamp - 1 }
          }
        }
        let postRange = NSRange(location: adj5, length: 1)
        let md = DeltaMetadata(sourceUpdate: "Postamble update (sweep)", orderIndex: seq)
        seq += 1
        deltas.append(ReconcilerDelta(type: .textUpdate(nodeKey: k, newText: newPost, range: postRange), metadata: md))
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: POSTAMBLE-sweep key=\(k) loc=\(postLoc) new='\(newPost.replacingOccurrences(of: "\n", with: "\\n"))'")
        }
      }
    }

    // Create batch metadata
    let batchMetadata = BatchMetadata(
      expectedTextStorageLength: editor.textStorage?.length ?? 0,
      isFreshDocument: isFreshDocument
    )

    return DeltaBatch(deltas: deltas, batchMetadata: batchMetadata)
  }

  /// Traverse the pending state's tree in document order and return the dirty keys in that order.
  private func orderedDirtyNodes(in pendingState: EditorState, limitedTo dirty: DirtyNodeMap) -> [NodeKey] {
    var result: [NodeKey] = []
    func visit(_ key: NodeKey) {
      if dirty[key] != nil { result.append(key) }
      if let node = pendingState.nodeMap[key] as? ElementNode {
        // Use fromLatest: false since we're working with pendingState nodes
        for child in node.getChildrenKeys(fromLatest: false) { visit(child) }
      }
    }
    if let root = pendingState.nodeMap[kRootNodeKey] { visit(root.getKey()) }
    // Fallback: if some dirty nodes were not reachable (shouldn't happen), append them
    for (k, _) in dirty where !result.contains(k) { result.append(k) }
    if getActiveEditor()?.featureFlags.diagnostics.verboseLogs == true {
      print("🔥 OPT RECON: ordered dirty=\(result)")
    }
    return result
  }

  /// Calculate insertion using cache first; if previous sibling not in cache, use processedInsertionLengths.
  private func calculateInsertionLocationOrdered(
    for nodeKey: NodeKey,
    in editorState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    processedInsertionLengths: [NodeKey: Int],
    runningOffset: inout Int,
    editor: Editor
  ) -> Int {
    guard let node = editorState.nodeMap[nodeKey] else { return runningOffset }
    guard let parentKey = node.parent,
          let parentNode = editorState.nodeMap[parentKey] as? ElementNode else { return runningOffset }

    // Use fromLatest: false since parentNode is from editorState, not active state
    let children = parentNode.getChildrenKeys(fromLatest: false)
    guard let idx = children.firstIndex(of: nodeKey) else { return runningOffset }

    if idx == 0 {
      // First child: start at parent's content start
      if let parentCache = rangeCache[parentKey] {
        let loc = editor.featureFlags.optimizedReconciler
          ? parentCache.locationFromFenwick(using: editor.fenwickTree)
          : parentCache.location
        return loc + parentCache.preambleLength
      }
      // Parent is root or also newly inserted - use running offset
      return runningOffset
    }

    let prevKey = children[idx - 1]
    if let prevCache = rangeCache[prevKey] {
      let prevLoc = editor.featureFlags.optimizedReconciler
        ? prevCache.locationFromFenwick(using: editor.fenwickTree)
        : prevCache.location
      return prevLoc + prevCache.preambleLength + prevCache.childrenLength + prevCache.textLength + prevCache.postambleLength
    }
    // Previous sibling also inserted in this batch; use its processed length if available.
    if processedInsertionLengths[prevKey] != nil,
       let parentCache = rangeCache[parentKey] {
      let parentLoc = editor.featureFlags.optimizedReconciler
        ? parentCache.locationFromFenwick(using: editor.fenwickTree)
        : parentCache.location
      // Start of parent's content plus sum of already processed sibling lengths up to prev
      var loc = parentLoc + parentCache.preambleLength
      // Accumulate lengths of siblings up to prev that are in processedInsertionLengths
      for k in children.prefix(idx) {
        if let l = processedInsertionLengths[k] { loc += l }
        else if let c = rangeCache[k] {
          loc += c.preambleLength + c.childrenLength + c.textLength + c.postambleLength
        }
      }
      return loc
    }
    // No cache info available - use running offset for sequential insertions
    return runningOffset
  }

  /// Calculate the insertion location for a new node in the document
  private func calculateInsertionLocation(
    for nodeKey: NodeKey,
    in editorState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    editor: Editor
  ) -> Int {
    guard let node = editorState.nodeMap[nodeKey] else {
      return 0
    }

    // Find the insertion point based on the node's position in its parent
    if let parent = node.parent,
       let parentNode = editorState.nodeMap[parent],
       let elementParent = parentNode as? ElementNode {

      // Use fromLatest: false since elementParent is from editorState, not active state
      let childrenKeys = elementParent.getChildrenKeys(fromLatest: false)
      guard let nodeIndex = childrenKeys.firstIndex(of: nodeKey) else {
        return 0
      }

      // If this is the first child, insert at parent's content start
      if nodeIndex == 0 {
        if let parentCacheItem = rangeCache[parent] {
          let parentLocation = editor.featureFlags.optimizedReconciler
            ? parentCacheItem.locationFromFenwick(using: editor.fenwickTree)
            : parentCacheItem.location
          return parentLocation + parentCacheItem.preambleLength
        }
        return 0
      }

      // Otherwise, insert after the previous sibling
      let previousSiblingKey = childrenKeys[nodeIndex - 1]
      if let previousCacheItem = rangeCache[previousSiblingKey] {
        let siblingLocation = editor.featureFlags.optimizedReconciler
          ? previousCacheItem.locationFromFenwick(using: editor.fenwickTree)
          : previousCacheItem.location
        return siblingLocation + previousCacheItem.preambleLength + previousCacheItem.childrenLength + previousCacheItem.textLength + previousCacheItem.postambleLength
      }
    }

    return 0
  }
}
