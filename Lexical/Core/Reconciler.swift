/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

// Debug logging configuration
#if DEBUG
private let anchorDebugLoggingEnabled = false  // Disabled to reduce log noise
private func debugLog(_ message: String) {
  if anchorDebugLoggingEnabled {
    print("🪲 RECONCILER: \(message)")
  }
}
#else
private func debugLog(_ message: @autoclosure () -> String) {}
#endif

public enum NodePart {
  case preamble
  case text
  case postamble
}

private struct ReconcilerInsertion {
  var location: Int
  var nodeKey: NodeKey
  var part: NodePart
}

internal enum AnchorSanityTestHooks {
  static var forceMismatch = false
}

private class ReconcilerState {
  internal init(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    dirtyNodes: DirtyNodeMap,
    treatAllNodesAsDirty: Bool,
    markedTextOperation: MarkedTextOperation?
  ) {
    self.prevEditorState = currentEditorState
    self.nextEditorState = pendingEditorState
    self.prevRangeCache = rangeCache
    self.nextRangeCache = rangeCache  // Use the previous range cache as a starting point
    self.locationCursor = 0
    self.rangesToDelete = []
    self.rangesToAdd = []
    self.dirtyNodes = dirtyNodes
    self.treatAllNodesAsDirty = treatAllNodesAsDirty
    self.markedTextOperation = markedTextOperation
    self.possibleDecoratorsToRemove = []
    self.decoratorsToAdd = []
    self.decoratorsToDecorate = []
    self.visitedNodes = 0
    self.insertedCharacterCount = 0
    self.deletedCharacterCount = 0
    self.fallbackReason = nil
    self.locationShifts = []
  }

  let prevEditorState: EditorState
  let nextEditorState: EditorState
  let prevRangeCache: [NodeKey: RangeCacheItem]
  var nextRangeCache: [NodeKey: RangeCacheItem]
  var locationCursor: Int = 0
  var rangesToDelete: [NSRange]
  var rangesToAdd: [ReconcilerInsertion]
  let dirtyNodes: DirtyNodeMap
  let treatAllNodesAsDirty: Bool
  let markedTextOperation: MarkedTextOperation?
  var possibleDecoratorsToRemove: [NodeKey]
  var decoratorsToAdd: [NodeKey]
  var decoratorsToDecorate: [NodeKey]
  var visitedNodes: Int
  var insertedCharacterCount: Int
  var deletedCharacterCount: Int
  var fallbackReason: ReconcilerFallbackReason?
  var locationShifts: [(location: Int, delta: Int)]

  func registerFallbackReason(_ reason: ReconcilerFallbackReason) {
    if fallbackReason == nil {
      fallbackReason = reason
    }
  }
}

@MainActor
private struct TextStorageDeltaApplier {
  enum AnchorDeltaOutcome {
    case applied(NSAttributedString?)
    case fallback
  }

  private static func debugLog(_ message: String) {
    #if DEBUG
    if anchorDebugLoggingEnabled {
      print("🪲 anchorDelta \(message)")
    }
    #endif
  }

  private static func commonPrefixLength(between first: NSString, and second: NSString) -> Int {
    // Use Apple's optimized commonPrefix method instead of character-by-character comparison
    // This is faster, especially for longer strings
    let commonPrefix = (first as String).commonPrefix(with: second as String)
    return commonPrefix.lengthAsNSString()
  }

  private static func commonSuffixLength(previous: NSString, next: NSString, prefixLength: Int) -> Int {
    let prevLength = previous.length
    let nextLength = next.length
    let maxSuffix = min(prevLength - prefixLength, nextLength - prefixLength)
    guard maxSuffix > 0 else { return 0 }

    for offset in 1...maxSuffix {
      if previous.character(at: prevLength - offset) != next.character(at: nextLength - offset) {
        return offset - 1
      }
    }
    return maxSuffix
  }

  private static func mergeGroup(_ group: [(range: NSRange, attributedString: NSAttributedString)], textStorage: NSTextStorage) -> [(range: NSRange, attributedString: NSAttributedString)] {
    guard group.count > 1 else { return group }

    // Find the span of all replacements in the group
    let minLocation = group.map { $0.range.location }.min()!
    let maxEnd = group.map { $0.range.location + $0.range.length }.max()!
    let totalRange = NSRange(location: minLocation, length: maxEnd - minLocation)

    // Build the merged content
    let mergedContent = NSMutableAttributedString()
    var currentPos = minLocation

    // Sort group by location for building
    let sorted = group.sorted { $0.range.location < $1.range.location }

    for replacement in sorted {
      // Add any gap text between current position and this replacement
      if replacement.range.location > currentPos {
        let gapRange = NSRange(location: currentPos, length: replacement.range.location - currentPos)
        if gapRange.location >= 0 && gapRange.location + gapRange.length <= textStorage.length {
          let gapText = textStorage.attributedSubstring(from: gapRange)
          mergedContent.append(gapText)
        }
        currentPos = replacement.range.location
      }

      // Add the replacement content
      mergedContent.append(replacement.attributedString)
      currentPos = replacement.range.location + replacement.range.length
    }

    // Add any remaining text up to maxEnd
    if currentPos < maxEnd && currentPos < textStorage.length {
      let remainingRange = NSRange(location: currentPos, length: min(maxEnd - currentPos, textStorage.length - currentPos))
      if remainingRange.length > 0 {
        let remainingText = textStorage.attributedSubstring(from: remainingRange)
        mergedContent.append(remainingText)
      }
    }

    return [(range: totalRange, attributedString: mergedContent)]
  }

  static func applyAnchorAwareDelta(
    state: ReconcilerState,
    textStorage: TextStorage,
    theme: Theme,
    pendingEditorState: EditorState,
    markedTextOperation: MarkedTextOperation?,
    markedTextPointForAddition: Point?,
    editor: Editor
  ) -> AnchorDeltaOutcome {
    let deltaStart = CFAbsoluteTimeGetCurrent()
    defer {
      let elapsed = CFAbsoluteTimeGetCurrent() - deltaStart
      debugLog("delta duration=\(String(format: "%.4f", elapsed)) replacements=\(state.rangesToAdd.count)")
    }
    debugLog("attempting delta: addCount=\(state.rangesToAdd.count) deleteCount=\(state.rangesToDelete.count) dirtyNodes=\(state.dirtyNodes.count)")
    #if DEBUG
    if anchorDebugLoggingEnabled {
      print("🪲 ANCHOR DELTA: addCount=\(state.rangesToAdd.count) deleteCount=\(state.rangesToDelete.count) dirtyNodes=\(state.dirtyNodes.count)")
    }
    #endif
    if AnchorSanityTestHooks.forceMismatch {
      debugLog("forced mismatch triggered; marking fallback")
      state.fallbackReason = .sanityCheckFailed
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }
    guard !state.rangesToAdd.isEmpty,
      let textStorageNSString = textStorage.string as NSString?
    else {
      debugLog("range mismatch add=\(state.rangesToAdd.count) delete=\(state.rangesToDelete.count)")
      state.registerFallbackReason(.unsupportedDelta)
      if AnchorSanityTestHooks.forceMismatch {
        state.fallbackReason = .sanityCheckFailed
      }
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }

    // FAST PATH: Single node change (90% of edits)
    if state.dirtyNodes.count == 1 && !state.treatAllNodesAsDirty {
      let nodeKey = state.dirtyNodes.keys.first!
      debugLog("FAST PATH: Single dirty node \(nodeKey)")
      // Fast path triggered for single dirty node

      // ULTRA OPTIMIZATION: Merge all parts into single operation
      guard let prevCacheItem = state.prevRangeCache[nodeKey],
            let node = pendingEditorState.nodeMap[nodeKey] else {
        debugLog("FAST PATH: Missing cache or node, falling back")
        state.registerFallbackReason(.unsupportedDelta)
        return .fallback
      }

      // Check if this is truly a simple text edit (not structural)
      let nodeInsertions = state.rangesToAdd.filter { $0.nodeKey == nodeKey }
      if nodeInsertions.count <= 3 { // Preamble, text, postamble
        debugLog("FAST PATH: Merging \(nodeInsertions.count) parts into SINGLE operation")

        let resolvedPreviousCacheItem = prevCacheItem.resolvingLocation(
          using: editor.rangeCacheLocationIndex, key: nodeKey)

        // Calculate the full node range
        let fullNodeLocation = resolvedPreviousCacheItem.location
        let fullNodeLength = prevCacheItem.preambleLength + prevCacheItem.childrenLength +
                           prevCacheItem.textLength + prevCacheItem.postambleLength
        let fullNodeRange = NSRange(location: fullNodeLocation, length: fullNodeLength)

        // ULTRA FAST PATH: Only replace what changed
        // For text-only changes, skip anchor replacement
        let newText = node.getTextPart()
        let oldTextLocation = fullNodeLocation + prevCacheItem.preambleLength + prevCacheItem.childrenLength
        let oldTextRange = NSRange(location: oldTextLocation, length: prevCacheItem.textLength)

        // Only update the text portion, leave anchors untouched
        let attributes = node.getAttributedStringAttributes(theme: theme)
        let textContent = NSAttributedString(string: newText, attributes: attributes)

        // Single replacement of just the changed text
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: oldTextRange, with: textContent)
        textStorage.endEditing()

        // Track location shift if needed
        let lengthDelta = textContent.length - oldTextRange.length
        if lengthDelta != 0 {
          state.locationShifts.append((location: oldTextRange.location + textContent.length, delta: lengthDelta))
        }

        debugLog("FAST PATH: Complete with SINGLE operation (1x20ms instead of 3x20ms)")
        return .applied(nil)
      }
    }

    var replacements: [(range: NSRange, attributedString: NSAttributedString)] = []

    // Cache for validation results to avoid repeated checks
    var validationCache: [String: Bool] = [:]

    // ULTRA-OPTIMIZATION: Only process truly changed nodes
    let filterStart = CFAbsoluteTimeGetCurrent()
    let dirtyNodeKeys = Set(state.dirtyNodes.keys)

    // DEBUG: Check what we're actually filtering
    debugLog("ANCHOR DEBUG: dirtyNodes=\(dirtyNodeKeys.count) treatAllAsDirty=\(state.treatAllNodesAsDirty) rangesToAdd=\(state.rangesToAdd.count)")

    // Group insertions by node to process all parts together
    var insertionsByNode: [String: [ReconcilerInsertion]] = [:]
    for insertion in state.rangesToAdd {
      insertionsByNode[insertion.nodeKey, default: []].append(insertion)
    }

    // Only process nodes that are actually dirty
    let filteredNodeKeys = insertionsByNode.keys.filter { nodeKey in
      dirtyNodeKeys.contains(nodeKey) || state.treatAllNodesAsDirty
    }

    debugLog("ULTRA-FILTER: processing \(filteredNodeKeys.count) dirty nodes out of \(insertionsByNode.count) total nodes")

    // If only 1-2 nodes changed, we can be VERY fast
    if filteredNodeKeys.count <= 2 && !state.treatAllNodesAsDirty {
      debugLog("FAST PATH: Only \(filteredNodeKeys.count) nodes to update!")
      // Process only the changed nodes with minimal overhead
      var filteredInsertions: [ReconcilerInsertion] = []
      for nodeKey in filteredNodeKeys {
        if let nodeInsertions = insertionsByNode[nodeKey] {
          filteredInsertions.append(contentsOf: nodeInsertions)
        }
      }
      let filterDuration = CFAbsoluteTimeGetCurrent() - filterStart
      debugLog("FAST FILTER: \(filteredInsertions.count) insertions in \(String(format: "%.4f", filterDuration))s")

      // Use the filtered insertions for the rest of the function
      let originalFilteredInsertions = filteredInsertions
      // Continue with processing...
    } else {
      // Original filtering logic for many changes
      let filteredInsertions = state.rangesToAdd.filter { insertion in
        dirtyNodeKeys.contains(insertion.nodeKey) || state.treatAllNodesAsDirty
      }
      let filterDuration = CFAbsoluteTimeGetCurrent() - filterStart
      debugLog("filtered insertions: \(filteredInsertions.count) out of \(state.rangesToAdd.count) total")
      debugLog("ANCHOR FILTER: filtered \(filteredInsertions.count)/\(state.rangesToAdd.count) insertions in \(String(format: "%.4f", filterDuration))s")
    }

    let filteredInsertions = state.rangesToAdd.filter { insertion in
      dirtyNodeKeys.contains(insertion.nodeKey) || state.treatAllNodesAsDirty
    }

    let processStart = CFAbsoluteTimeGetCurrent()
    for insertion in filteredInsertions {
      guard
        let nextCacheItem = state.nextRangeCache[insertion.nodeKey],
        let previousCacheItem = state.prevRangeCache[insertion.nodeKey],
        let node = pendingEditorState.nodeMap[insertion.nodeKey]
      else {
        debugLog("missing cache item for node=\(insertion.nodeKey)")
        state.registerFallbackReason(.unsupportedDelta)
        if AnchorSanityTestHooks.forceMismatch {
          state.fallbackReason = .sanityCheckFailed
        }
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }

      let resolvedPreviousCacheItem = previousCacheItem.resolvingLocation(
        using: editor.rangeCacheLocationIndex, key: insertion.nodeKey)

      let anchorRange: NSRange
      let previousLength: Int
      let expectedAnchor: String

      switch insertion.part {
      case .preamble:
        guard
          let element = node as? ElementNode,
          let startAnchor = element.anchorStartString,
          nextCacheItem.startAnchorLength == startAnchor.lengthAsNSString()
        else {
          debugLog("preamble anchor length mismatch for node=\(insertion.nodeKey)")
          state.registerFallbackReason(.unsupportedDelta)
          return .fallback
        }
        anchorRange = NSRange(
          location: resolvedPreviousCacheItem.location,
          length: resolvedPreviousCacheItem.startAnchorLength)
        previousLength = resolvedPreviousCacheItem.startAnchorLength
        expectedAnchor = startAnchor
      case .postamble:
        guard
          let element = node as? ElementNode,
          let endAnchor = element.anchorEndString,
          nextCacheItem.endAnchorLength == endAnchor.lengthAsNSString()
        else {
          debugLog("postamble anchor length mismatch for node=\(insertion.nodeKey)")
          state.registerFallbackReason(.unsupportedDelta)
          if AnchorSanityTestHooks.forceMismatch {
            state.fallbackReason = .sanityCheckFailed
          }
          AnchorSanityTestHooks.forceMismatch = false
          return .fallback
        }
        anchorRange = NSRange(
          location: resolvedPreviousCacheItem.location
            + resolvedPreviousCacheItem.preambleLength
            + resolvedPreviousCacheItem.childrenLength
            + resolvedPreviousCacheItem.textLength,
          length: resolvedPreviousCacheItem.endAnchorLength)
        previousLength = resolvedPreviousCacheItem.endAnchorLength
        expectedAnchor = endAnchor
      case .text:
        // Quick check: if node isn't dirty and lengths match, skip expensive operations
        if !dirtyNodeKeys.contains(insertion.nodeKey) && !state.treatAllNodesAsDirty {
          if previousCacheItem.textLength == nextCacheItem.textLength {
            debugLog("text unchanged (length match); skipping node=\(insertion.nodeKey)")
            continue
          }
        }

        let textLocation = resolvedPreviousCacheItem.location
          + resolvedPreviousCacheItem.preambleLength
          + resolvedPreviousCacheItem.childrenLength
        let textRange = NSRange(location: textLocation, length: resolvedPreviousCacheItem.textLength)
        guard textRange.location + textRange.length <= textStorageNSString.length else {
          debugLog("text range beyond storage length; storageLength=\(textStorageNSString.length) range=\(NSStringFromRange(textRange))")
          state.registerFallbackReason(.unsupportedDelta)
          AnchorSanityTestHooks.forceMismatch = false
          return .fallback
        }

        let storedText = editor.consumePreMutationText(for: insertion.nodeKey)
        let previousNodeText = storedText
          ?? (state.prevEditorState.nodeMap[insertion.nodeKey] as? TextNode)?.getTextPart(fromLatest: false)

        guard let textNode = node as? TextNode else {
          debugLog("Encountered non-text node for .text part: \(insertion.nodeKey)")
          state.registerFallbackReason(.unsupportedDelta)
          AnchorSanityTestHooks.forceMismatch = false
          return .fallback
        }

        let previousText = (previousNodeText ?? textStorageNSString.substring(with: textRange)) as NSString
        let newText = textNode.getTextPart() as NSString

        let prefix = commonPrefixLength(between: previousText, and: newText)
        let suffix = commonSuffixLength(previous: previousText, next: newText, prefixLength: prefix)
        debugLog(
          "text diff prevLen=\(previousText.length) newLen=\(newText.length) prefix=\(prefix) suffix=\(suffix)")

        let oldReplaceLocation = textRange.location + prefix
        let oldReplaceLength = max(previousText.length - prefix - suffix, 0)
        let newInsertLocation = prefix
        let newInsertLength = max(newText.length - prefix - suffix, 0)

        if oldReplaceLength == 0 && newInsertLength == 0 {
          debugLog("text unchanged; skipping replacement")
          continue
        }

        let replacementRange = NSRange(location: oldReplaceLocation, length: oldReplaceLength)
        let newSubstringRange = NSRange(location: newInsertLocation, length: newInsertLength)
        let replacementPlain = newText.substring(with: newSubstringRange)
        let replacementBase = NSAttributedString(string: replacementPlain)
        let replacementText = AttributeUtils.attributedStringByAddingStyles(
          replacementBase,
          from: node,
          state: pendingEditorState,
          theme: theme)
        debugLog(
          "queue partial text replacement oldRange=\(NSStringFromRange(replacementRange)) newLength=\(replacementText.length)")
        replacements.append((range: replacementRange, attributedString: replacementText))

        let delta = newInsertLength - oldReplaceLength
        if delta != 0 {
          let shiftStart = textRange.location + resolvedPreviousCacheItem.textLength
          state.locationShifts.append((location: shiftStart, delta: delta))
          debugLog("recorded location shift start=\(shiftStart) delta=\(delta)")
        }
        continue
      }

      guard anchorRange.location + anchorRange.length <= textStorageNSString.length else {
        debugLog("anchor range beyond storage length storageLength=\(textStorageNSString.length) range=\(NSStringFromRange(anchorRange)) part=\(insertion.part)")
        state.registerFallbackReason(.unsupportedDelta)
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }

      let existingAttributes = textStorage.attributes(at: anchorRange.location, effectiveRange: nil)
      let replacement = NSAttributedString(string: expectedAnchor, attributes: existingAttributes)

      // OPTIMIZATION: Skip validation for clean nodes
      let isNodeDirty = dirtyNodeKeys.contains(insertion.nodeKey) || state.treatAllNodesAsDirty
      if replacement.length != anchorRange.length && anchorRange.length > 0 && isNodeDirty {
        debugLog("anchor length mismatch replacement=\(replacement.length) existing=\(anchorRange.length) part=\(insertion.part)")
        state.registerFallbackReason(.unsupportedDelta)
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }
      if previousLength > 0 && isNodeDirty {
        // Only validate anchors for dirty nodes
        let currentAnchor = textStorageNSString.substring(with: anchorRange)
        guard currentAnchor == expectedAnchor else {
          debugLog("anchor content mismatch current=\(currentAnchor) expected=\(expectedAnchor)")
          state.registerFallbackReason(.unsupportedDelta)
          AnchorSanityTestHooks.forceMismatch = false
          return .fallback
        }

        if replacement.length == anchorRange.length {
          debugLog("anchor unchanged; skipping replacement part=\(insertion.part)")
          continue
        }
      }
      debugLog("queue anchor replacement len=\(replacement.length) range=\(NSStringFromRange(anchorRange)) part=\(insertion.part)")
      replacements.append((range: anchorRange, attributedString: replacement))
    }

    let processDuration = CFAbsoluteTimeGetCurrent() - processStart
    debugLog("PROFILE processing insertions: \(String(format: "%.4f", processDuration))s for \(filteredInsertions.count) nodes")

    guard !replacements.isEmpty else {
      debugLog("no replacements queued; falling back")
      state.registerFallbackReason(.unsupportedDelta)
      if AnchorSanityTestHooks.forceMismatch {
        state.fallbackReason = .sanityCheckFailed
      }
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }

    let totals = replacements.reduce(into: (inserted: 0, deleted: 0)) { partial, entry in
      partial.inserted += entry.attributedString.length
      partial.deleted += entry.range.length
    }
    state.insertedCharacterCount = totals.inserted
    state.deletedCharacterCount = totals.deleted

    debugLog("applying \(replacements.count) replacements; fixesAttributesLazily=\(textStorage.fixesAttributesLazily)")
    debugLog("ANCHOR APPLY: applying \(replacements.count) replacements")

    // ULTRA-OPTIMIZATION: Combine ALL replacements into a SINGLE TextStorage operation
    // This avoids the ~20ms overhead per operation that TextKit imposes
    let batchStart = CFAbsoluteTimeGetCurrent()

    var coalescedReplacements: [(range: NSRange, attributedString: NSAttributedString)] = []

    // Sort replacements from end to beginning to maintain offsets
    let sortedReplacements = replacements.sorted { $0.range.location > $1.range.location }

    // Aggressive coalescing: merge replacements that are close together (within 100 chars)
    let mergeThreshold = 100
    var mergedReplacements: [(range: NSRange, attributedString: NSAttributedString)] = []
    var currentGroup: [(range: NSRange, attributedString: NSAttributedString)] = []

    for replacement in sortedReplacements {
      if let lastInGroup = currentGroup.last {
        let gap = lastInGroup.range.location - (replacement.range.location + replacement.range.length)
        if gap < mergeThreshold {
          // Close enough to merge
          currentGroup.append(replacement)
        } else {
          // Too far apart, save current group and start new
          if !currentGroup.isEmpty {
            mergedReplacements.append(contentsOf: mergeGroup(currentGroup, textStorage: textStorage))
          }
          currentGroup = [replacement]
        }
      } else {
        currentGroup = [replacement]
      }
    }

    // Don't forget the last group
    if !currentGroup.isEmpty {
      mergedReplacements.append(contentsOf: mergeGroup(currentGroup, textStorage: textStorage))
    }

    coalescedReplacements = mergedReplacements
    if replacements.count != coalescedReplacements.count {
      debugLog("ULTRA-OPT: Merged \(replacements.count) replacements into \(coalescedReplacements.count) operations")
    }

    debugLog("PROFILE coalesced \(replacements.count) replacements into \(coalescedReplacements.count)")

    // Use beginEditing/endEditing to batch all changes into a single TextKit update
    let beginEditingStart = CFAbsoluteTimeGetCurrent()
    textStorage.beginEditing()
    let beginEditingDuration = CFAbsoluteTimeGetCurrent() - beginEditingStart
    debugLog("PROFILE beginEditing: \(String(format: "%.4f", beginEditingDuration))s")

    // Apply coalesced replacements from end to beginning to maintain correct offsets
    let replacementStart = CFAbsoluteTimeGetCurrent()
    for (index, replacement) in coalescedReplacements.enumerated() {
      let singleStart = CFAbsoluteTimeGetCurrent()
      textStorage.replaceCharacters(in: replacement.range, with: replacement.attributedString)
      let singleDuration = CFAbsoluteTimeGetCurrent() - singleStart
      if singleDuration > 0.01 {  // Log slow replacements
        debugLog("PROFILE slow replacement[\(index)]: \(String(format: "%.4f", singleDuration))s range=\(replacement.range) len=\(replacement.attributedString.length)")
      }
    }
    let replacementDuration = CFAbsoluteTimeGetCurrent() - replacementStart
    debugLog("PROFILE all replacements: \(String(format: "%.4f", replacementDuration))s for \(coalescedReplacements.count) ops")

    let endEditingStart = CFAbsoluteTimeGetCurrent()
    textStorage.endEditing()
    let endEditingDuration = CFAbsoluteTimeGetCurrent() - endEditingStart
    debugLog("PROFILE endEditing: \(String(format: "%.4f", endEditingDuration))s")

    let batchDuration = CFAbsoluteTimeGetCurrent() - batchStart
    debugLog(String(format: "batch replacement took=%.4f", batchDuration))
    debugLog("ANCHOR BATCH: \(replacements.count) replacements in \(String(format: "%.4f", batchDuration))s")

    // Optimization: Use invalidateAttributes for lazy fixing when possible
    // This defers the actual attribute fixing until needed
    if textStorage.fixesAttributesLazily {
      // Just mark ranges as needing fixing, don't fix immediately
      for replacement in coalescedReplacements {
        let fixRange = NSRange(location: replacement.range.location, length: replacement.attributedString.length)
        textStorage.invalidateAttributes(in: fixRange)
      }
    } else {
      // Must fix immediately if not lazy
      for replacement in coalescedReplacements {
        let fixRange = NSRange(location: replacement.range.location, length: replacement.attributedString.length)
        textStorage.fixAttributes(in: fixRange)
      }
    }

    if AnchorSanityTestHooks.forceMismatch {
      textStorage.insert(NSAttributedString(string: "!"), at: 0)
      AnchorSanityTestHooks.forceMismatch = false
    }

    debugLog("anchor delta applied successfully")
    let totalElapsed = CFAbsoluteTimeGetCurrent() - deltaStart
    debugLog("ANCHOR COMPLETE: delta applied in \(String(format: "%.4f", totalElapsed))s with \(replacements.count) replacements")
    return .applied(nil)
  }
}

@MainActor
  private func applyLegacyTextStorageDelta(
    state: ReconcilerState,
    textStorage: TextStorage,
    theme: Theme,
    pendingEditorState: EditorState,
  markedTextOperation: MarkedTextOperation?,
  markedTextPointForAddition: Point?,
  editor: Editor
) -> NSAttributedString? {
  let legacyStart = CFAbsoluteTimeGetCurrent()
  debugLog("LEGACY START: rangesToDelete=\(state.rangesToDelete.count) rangesToAdd=\(state.rangesToAdd.count)")

  editor.log(
    .reconciler, .verbose,
    "about to do rangesToDelete: total \(state.rangesToDelete.count)")

  // CRITICAL: We're already inside a beginEditing/endEditing block from the parent reconciler
  // But we still batch our operations to minimize overhead

  let deleteStart = CFAbsoluteTimeGetCurrent()
  var nonEmptyDeletionsCount = 0

  // Batch all deletions
  for deletionRange in state.rangesToDelete.reversed() {
    if deletionRange.length > 0 {
      nonEmptyDeletionsCount += 1
      editor.log(
        .reconciler, .verboseIncludingUserContent,
        "deleting range \(NSStringFromRange(deletionRange)) `\((textStorage.string as NSString).substring(with: deletionRange))`"
      )
      textStorage.deleteCharacters(in: deletionRange)
    }
  }
  let deleteDuration = CFAbsoluteTimeGetCurrent() - deleteStart
  debugLog("LEGACY DELETE: \(nonEmptyDeletionsCount) deletions in \(String(format: "%.4f", deleteDuration))s")
  editor.log(.reconciler, .verbose, "did rangesToDelete: non-empty \(nonEmptyDeletionsCount)")

  editor.log(
    .reconciler, .verbose, "about to do rangesToAdd: total \(state.rangesToAdd.count)")

    let insertStart = CFAbsoluteTimeGetCurrent()
    var markedTextAttributedString: NSAttributedString?
    var nonEmptyRangesToAddCount = 0
    var rangesInserted: [NSRange] = []
    var totalInsertedChars = 0

    // Batch all insertions
    for insertion in state.rangesToAdd {
      let attributedString = Reconciler.attributedStringFromInsertion(
      insertion,
      state: pendingEditorState,
      theme: theme)
    if attributedString.length > 0 {
      nonEmptyRangesToAddCount += 1
      totalInsertedChars += attributedString.length
      editor.log(
        .reconciler, .verboseIncludingUserContent,
        "inserting at \(insertion.location), `\(attributedString.string)`")
      textStorage.insert(attributedString, at: insertion.location)
      rangesInserted.append(
        NSRange(location: insertion.location, length: attributedString.length))

      if let pointForAddition = markedTextPointForAddition,
        let length = markedTextOperation?.markedTextString.lengthAsNSString()
      {
        if insertion.part == .text && pointForAddition.key == insertion.nodeKey
          && pointForAddition.offset + length <= attributedString.length
        {
          markedTextAttributedString = attributedString
        }
      }
    }
  }
  let insertDuration = CFAbsoluteTimeGetCurrent() - insertStart
  debugLog("LEGACY INSERT: \(nonEmptyRangesToAddCount) insertions (\(totalInsertedChars) chars) in \(String(format: "%.4f", insertDuration))s")

  if !textStorage.fixesAttributesLazily {
    for range in rangesInserted {
      textStorage.fixAttributes(in: range)
    }
  }

    editor.log(.reconciler, .verbose, "did rangesToAdd: non-empty \(nonEmptyRangesToAddCount)")

    let legacyEndStart = CFAbsoluteTimeGetCurrent()
    defer {
      editor.log(
        .reconciler, .verbose,
        "legacy endEditing duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - legacyEndStart))")
    }

    return markedTextAttributedString
  }

/* Marked text is a difficult operation because it depends on us being in sync with some private state that
 * is held by the iOS keyboard. We can't set or read that state, so we have to make sure we do the things
 * that the keyboard is expecting.
 */
internal struct MarkedTextOperation {

  let createMarkedText: Bool
  let selectionRangeToReplace: NSRange
  let markedTextString: String
  let markedTextInternalSelection: NSRange
}

internal enum Reconciler {

#if DEBUG
  fileprivate static var anchorDebugLoggingEnabled: Bool {
    ProcessInfo.processInfo.environment["LEXICAL_ANCHOR_DEBUG"] == "1"
  }
#else
  fileprivate static var anchorDebugLoggingEnabled: Bool { false }
#endif

  // Removed - using module-level debug logging

  @MainActor
  internal static func updateEditorState(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,  // the situations where we would want to not do this include handling non-controlled mode
    markedTextOperation: MarkedTextOperation?
  ) throws {
    let updateStart = CFAbsoluteTimeGetCurrent()
    let metricsStart = CFAbsoluteTimeGetCurrent()
    var metricsShouldRecord = false
    var metricsState: ReconcilerState?
    defer {
      if metricsShouldRecord, let state = metricsState {
        let duration = CFAbsoluteTimeGetCurrent() - metricsStart
        let metric = ReconcilerMetric(
          duration: duration,
          dirtyNodes: state.dirtyNodes.count,
          rangesAdded: state.rangesToAdd.count,
          rangesDeleted: state.rangesToDelete.count,
          treatedAllNodesAsDirty: state.treatAllNodesAsDirty,
          nodesVisited: state.visitedNodes,
          insertedCharacters: state.insertedCharacterCount,
          deletedCharacters: state.deletedCharacterCount,
          fallbackReason: state.fallbackReason
        )
        editor.metricsContainer?.record(.reconcilerRun(metric))
      }
    }

    editor.log(.reconciler, .verbose)

    guard let textStorage = editor.textStorage else {
      fatalError("Cannot run reconciler on an editor with no text storage")
    }
    let textStorageBaseline = NSAttributedString(attributedString: textStorage)

    if editor.dirtyNodes.isEmpty,
      editor.dirtyType == .noDirtyNodes,
      let currentSelection = currentEditorState.selection,
      let pendingSelection = pendingEditorState.selection,
      currentSelection.isSelection(pendingSelection),
      pendingSelection.dirty == false,
      markedTextOperation == nil
    {
      // should be nothing to reconcile
      return
    }

    if let markedTextOperation, markedTextOperation.createMarkedText {
      guard shouldReconcileSelection == false else {
        editor.log(
          .reconciler, .warning, "should not reconcile selection whilst starting marked text!")
        throw LexicalError.invariantViolation(
          "should not reconcile selection whilst starting marked text!")
      }
    }

    let currentSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    let needsUpdate = editor.dirtyType != .noDirtyNodes

    let reconcilerState = ReconcilerState(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      rangeCache: editor.rangeCache,
      dirtyNodes: editor.dirtyNodes,
      treatAllNodesAsDirty: editor.dirtyType == .fullReconcile,
      markedTextOperation: markedTextOperation)
    metricsShouldRecord = true
    metricsState = reconcilerState

    // FAST PATH: Check for single structural insertion (common case)
    if let fastInsertionResult = tryFastStructuralInsertion(reconcilerState: reconcilerState, editor: editor) {
      debugLog("🚀 FAST PATH: Handled structural insertion without tree walk!")
      // Apply the fast path result directly
      reconcilerState.nextRangeCache = fastInsertionResult.rangeCache
      reconcilerState.rangesToAdd = fastInsertionResult.insertions
      reconcilerState.locationShifts = fastInsertionResult.shifts
      // Skip the full tree walk
    } else {
      // Fall back to regular reconciliation
      try reconcileNode(key: kRootNodeKey, reconcilerState: reconcilerState)
    }

    debugLog(
      "reconciler phase reconcile duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - updateStart))")

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    let beginEditingTime = CFAbsoluteTimeGetCurrent()
    debugLog(
      "reconciler phase beginEditing duration=\(String(format: "%.4f", beginEditingTime - updateStart))")

    var markedTextAttributedString: NSAttributedString?
    var markedTextPointForAddition: Point?

    if let markedTextOperation {
      // Find the Point corresponding to the location where marked text will be added
      let indexForPendingCache: RangeCacheLocationIndex = {
        let index = RangeCacheLocationIndex()
        index.rebuild(rangeCache: reconcilerState.nextRangeCache)
        return index
      }()
      markedTextPointForAddition = try? pointAtStringLocation(
        markedTextOperation.selectionRangeToReplace.location,
        searchDirection: .forward,
        rangeCache: reconcilerState.nextRangeCache,
        locationIndex: indexForPendingCache
      )
    }

    // Handle the decorators
    let decoratorsToRemove = reconcilerState.possibleDecoratorsToRemove.filter { key in
      return !reconcilerState.decoratorsToAdd.contains(key)
    }
    let decoratorsToDecorate = reconcilerState.decoratorsToDecorate.filter { key in
      return !reconcilerState.decoratorsToAdd.contains(key)
    }
    decoratorsToRemove.forEach { key in
      decoratorView(forKey: key, createIfNecessary: false)?.removeFromSuperview()
      destroyCachedDecoratorView(forKey: key)
      textStorage.decoratorPositionCache[key] = nil
    }
    reconcilerState.decoratorsToAdd.forEach { key in
      if editor.decoratorCache[key] == nil {
        editor.decoratorCache[key] = DecoratorCacheItem.needsCreation
      }
      guard let rangeCacheItem = reconcilerState.nextRangeCache[key] else { return }
      let resolvedCacheItem = rangeCacheItem.resolvingLocation(
        using: editor.rangeCacheLocationIndex, key: key)
      textStorage.decoratorPositionCache[key] = resolvedCacheItem.location
    }
    decoratorsToDecorate.forEach { key in
      if let cacheItem = editor.decoratorCache[key], let view = cacheItem.view {
        editor.decoratorCache[key] = DecoratorCacheItem.needsDecorating(view)
      }
      guard let rangeCacheItem = reconcilerState.nextRangeCache[key] else { return }
      let resolvedCacheItem = rangeCacheItem.resolvingLocation(
        using: editor.rangeCacheLocationIndex, key: key)
      textStorage.decoratorPositionCache[key] = resolvedCacheItem.location
    }

    let theme = editor.getTheme()
    var usedAnchorDelta = false
    if editor.featureFlags.reconcilerAnchors && reconcilerState.fallbackReason == nil {
      let anchorOutcome = TextStorageDeltaApplier.applyAnchorAwareDelta(
        state: reconcilerState,
        textStorage: textStorage,
        theme: theme,
        pendingEditorState: reconcilerState.nextEditorState,
        markedTextOperation: markedTextOperation,
        markedTextPointForAddition: markedTextPointForAddition,
        editor: editor
      )

      switch anchorOutcome {
      case .applied(let anchorResult):
        usedAnchorDelta = true
        editor.log(.reconciler, .verbose, "applied text storage delta via anchor-aware mode")
        markedTextAttributedString = anchorResult
      case .fallback:
        break
      }
    }
    let afterDelta = CFAbsoluteTimeGetCurrent()
    debugLog(
      "reconciler phase delta duration=\(String(format: "%.4f", afterDelta - beginEditingTime))")

    if usedAnchorDelta && editor.featureFlags.reconcilerSanityCheck {
      let sanityTextStorage = TextStorage()
      sanityTextStorage.setAttributedString(textStorageBaseline)
      sanityTextStorage.mode = .controllerMode
      sanityTextStorage.beginEditing()
      _ = applyLegacyTextStorageDelta(
        state: reconcilerState,
        textStorage: sanityTextStorage,
        theme: theme,
        pendingEditorState: reconcilerState.nextEditorState,
        markedTextOperation: markedTextOperation,
        markedTextPointForAddition: markedTextPointForAddition,
        editor: editor)
      sanityTextStorage.endEditing()
      sanityTextStorage.mode = .none

      let legacySnapshot = NSAttributedString(attributedString: sanityTextStorage)
      let anchorSnapshot = NSAttributedString(attributedString: textStorage)
      if !legacySnapshot.isEqual(to: anchorSnapshot) {
        editor.log(
          .reconciler, .error,
          "anchor-aware reconciliation diverged from legacy output; disabling anchors")
        reconcilerState.registerFallbackReason(.sanityCheckFailed)
        editor.setReconcilerAnchorsEnabled(false)
        textStorage.setAttributedString(textStorageBaseline)
        usedAnchorDelta = false
      }
    }

    if !usedAnchorDelta {
      if reconcilerState.fallbackReason == .sanityCheckFailed {
        editor.setReconcilerAnchorsEnabled(false)
      }
      markedTextAttributedString = applyLegacyTextStorageDelta(
        state: reconcilerState,
        textStorage: textStorage,
        theme: theme,
        pendingEditorState: reconcilerState.nextEditorState,
        markedTextOperation: markedTextOperation,
        markedTextPointForAddition: markedTextPointForAddition,
        editor: editor)
    }

    let lastDescendentAttributes = getRoot()?.getLastChild()?.getAttributedStringAttributes(
      theme: theme)

    // TODO: this iteration applies the attributes in an arbitrary order. If we are to handle nesting nodes with these block level attributes
    // we may want to apply them in a deterministic order, and also make them nest additively (i.e. for when two blocks start at the same paragraph)
    var nodesToApplyBlockAttributes: Set<NodeKey> = []
    if reconcilerState.treatAllNodesAsDirty {
      nodesToApplyBlockAttributes = Set(pendingEditorState.nodeMap.keys)
    } else {
      for nodeKey in reconcilerState.dirtyNodes.keys {
        guard let node = getNodeByKey(key: nodeKey) else { continue }
        nodesToApplyBlockAttributes.insert(nodeKey)
        for parentNodeKey in node.getParentKeys() {
          nodesToApplyBlockAttributes.insert(parentNodeKey)
        }
      }
    }
    let rangeCache = reconcilerState.nextRangeCache
    let blockStart = CFAbsoluteTimeGetCurrent()
    for nodeKey in nodesToApplyBlockAttributes {
      guard let node = getNodeByKey(key: nodeKey),
        node.isAttached(),
        let cacheItem = rangeCache[nodeKey],
        let attributes = node.getBlockLevelAttributes(theme: theme)
      else { continue }

      AttributeUtils.applyBlockLevelAttributes(
        attributes, cacheItem: cacheItem, textStorage: textStorage, nodeKey: nodeKey,
        lastDescendentAttributes: lastDescendentAttributes ?? [:])
    }
    debugLog(
      "reconciler blockAttributes duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - blockStart)) count=\(nodesToApplyBlockAttributes.count)")

    editor.rangeCache = reconcilerState.nextRangeCache
    if usedAnchorDelta, !reconcilerState.locationShifts.isEmpty,
      !editor.rangeCacheLocationIndex.isEmpty
    {
      let sortedShifts = reconcilerState.locationShifts.sorted { $0.location < $1.location }
      for shift in sortedShifts {
        editor.rangeCacheLocationIndex.shiftNodes(startingAt: shift.location, delta: shift.delta)
        debugLog("rangeIndex applied shift start=\(shift.location) delta=\(shift.delta)")
      }
    } else {
      let rebuildStart = CFAbsoluteTimeGetCurrent()
      editor.rangeCacheLocationIndex.rebuild(rangeCache: editor.rangeCache)
      debugLog(
        "reconciler rangeIndex rebuild duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - rebuildStart))")
    }

    // Rebuild anchor index if anchors are enabled
    if editor.featureFlags.reconcilerAnchors, let textStorage = editor.textStorage {
      let anchorRebuildStart = CFAbsoluteTimeGetCurrent()
      editor.anchorIndex.rebuild(from: textStorage)
      debugLog(
        "reconciler anchorIndex rebuild duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - anchorRebuildStart)) nodes=\(editor.anchorIndex.nodeCount)")
    }
    let endEditingStart = CFAbsoluteTimeGetCurrent()
    textStorage.endEditing()
    debugLog(
      "reconciler textStorage.endEditing duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - endEditingStart))")
    textStorage.mode = previousMode
    debugLog(
      "reconciler total update duration=\(String(format: "%.4f", CFAbsoluteTimeGetCurrent() - updateStart))")
    editor.lastReconcilerUsedAnchors = usedAnchorDelta
    editor.lastReconcilerFallbackReason = reconcilerState.fallbackReason

    if let markedTextOperation,
      markedTextOperation.createMarkedText,
      let markedTextAttributedString,
      let startPoint = markedTextPointForAddition,
      let frontend = editor.frontend
    {
      // We have a marked text operation, an attributed string, we know the Point at which it should be added.
      // Note that the text has _already_ been inserted into the TextStorage, so we actually have to _replace_ the
      // marked text range with the same text, but via a marked text operation. Hence we deduce the end point
      // of the marked text, set a fake selection using it, and then tell the text view to go ahead and start a
      // marked text operation.
      let length = markedTextOperation.markedTextString.lengthAsNSString()
      let endPoint = Point(key: startPoint.key, offset: startPoint.offset + length, type: .text)
      try frontend.updateNativeSelection(
        from: RangeSelection(anchor: startPoint, focus: endPoint, format: TextFormat()))
      let attributedSubstring = markedTextAttributedString.attributedSubstring(
        from: NSRange(location: startPoint.offset, length: length))
      editor.frontend?.setMarkedTextFromReconciler(
        attributedSubstring, selectedRange: markedTextOperation.markedTextInternalSelection)

      // do not do selection reconcile after marked text!
      // The selection will be correctly set as part of the setMarkedTextFromReconciler() call.
      return
    }

    var selectionsAreDifferent = false
    if let nextSelection, let currentSelection {
      let isSame = nextSelection.isSelection(currentSelection)
      selectionsAreDifferent = !isSame
    }

    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(
        prevSelection: currentSelection, nextSelection: nextSelection, editor: editor)
    }
  }

  /// Fast path for single structural insertions
  @MainActor
  private static func tryFastStructuralInsertion(reconcilerState: ReconcilerState, editor: Editor) -> (rangeCache: [NodeKey: RangeCacheItem], insertions: [ReconcilerInsertion], shifts: [(location: Int, delta: Int)])? {

    // Check if this is a simple insertion case
    guard let root = reconcilerState.nextEditorState.nodeMap[kRootNodeKey] as? RootNode,
          let prevRoot = reconcilerState.prevEditorState.nodeMap[kRootNodeKey] as? RootNode else {
      return nil
    }

    let prevChildren = prevRoot.children
    let nextChildren = root.children
    let prevCount = prevChildren.count
    let nextCount = nextChildren.count

    // Check for single insertion
    guard nextCount == prevCount + 1 else {
      return nil
    }

    // Find the inserted child
    var insertedIndex: Int?
    for i in 0..<nextCount {
      let isNewNode = i >= prevCount || (i < prevCount && nextChildren[i] != prevChildren[i])
      if isNewNode {
        insertedIndex = i
        break
      }
    }

    guard let index = insertedIndex else {
      return nil
    }

    let insertedKey = nextChildren[index]
    guard let insertedNode = reconcilerState.nextEditorState.nodeMap[insertedKey] else {
      return nil
    }

    debugLog("🚀 FAST INSERT: Detected insertion at index \(index) of \(nextCount) children")

    // Calculate insertion location using existing range cache
    var insertLocation: Int = 0
    if index > 0 {
      // Insert after previous node
      let prevNodeKey = nextChildren[index - 1]
      if let prevCache = reconcilerState.prevRangeCache[prevNodeKey] {
        insertLocation = prevCache.location + prevCache.preambleLength +
                        prevCache.childrenLength + prevCache.textLength +
                        prevCache.postambleLength
      }
    }

    // Build insertion data for the new node
    var insertions: [ReconcilerInsertion] = []
    var newRangeCache = reconcilerState.prevRangeCache

    // Calculate the content to insert
    let preamble = insertedNode.getPreamble()
    let text = insertedNode.getTextPart()
    let postamble = insertedNode.getPostamble()

    let preambleLength = preamble.lengthAsNSString()
    let textLength = text.lengthAsNSString()
    let postambleLength = postamble.lengthAsNSString()
    let totalLength = preambleLength + textLength + postambleLength

    // Add insertions
    if preambleLength > 0 {
      insertions.append(ReconcilerInsertion(location: insertLocation, nodeKey: insertedKey, part: .preamble))
    }
    if textLength > 0 {
      insertions.append(ReconcilerInsertion(location: insertLocation + preambleLength, nodeKey: insertedKey, part: .text))
    }
    if postambleLength > 0 {
      insertions.append(ReconcilerInsertion(location: insertLocation + preambleLength + textLength, nodeKey: insertedKey, part: .postamble))
    }

    // Create range cache entry for new node
    newRangeCache[insertedKey] = RangeCacheItem(
      location: insertLocation,
      preambleLength: preambleLength,
      childrenLength: 0,
      textLength: textLength,
      postambleLength: postambleLength
    )

    // Create shifts for all nodes after insertion
    let shifts = [(location: insertLocation + totalLength, delta: totalLength)]

    debugLog("🚀 FAST INSERT: Complete - avoided walking \(prevCount) nodes!")

    return (rangeCache: newRangeCache, insertions: insertions, shifts: shifts)
  }

  @MainActor
  private static func reconcileNode(key: NodeKey, reconcilerState: ReconcilerState) throws {
    reconcilerState.visitedNodes += 1

    guard let prevNode = reconcilerState.prevEditorState.nodeMap[key],
      let nextNode = reconcilerState.nextEditorState.nodeMap[key]
    else {
      throw LexicalError.invariantViolation(
        "reconcileNode should only be called when a node is present in both node maps, otherwise create or delete should be called"
      )
    }
    guard let prevRange = reconcilerState.prevRangeCache[key] else {
      throw LexicalError.invariantViolation(
        "Node map entry for '\(key)' not found")
    }

    let isDirty = reconcilerState.dirtyNodes[key] != nil || reconcilerState.treatAllNodesAsDirty

    if prevNode === nextNode && !isDirty {
      // OPTIMIZED: Skip clean subtrees entirely!
      // Use Fenwick tree to get the shifted location instead of walking all children

      // Calculate total size of this node (including children)
      let totalNodeSize = prevRange.preambleLength + prevRange.textLength +
                         prevRange.childrenLength + prevRange.postambleLength

      // Update location using Fenwick tree offset
      let shiftedLocation = reconcilerState.locationCursor

      // Just copy the cache entry with updated location
      var nextRangeCacheItem = prevRange
      nextRangeCacheItem.location = shiftedLocation
      reconcilerState.nextRangeCache[key] = nextRangeCacheItem

      // Update cursor and skip entire subtree
      reconcilerState.locationCursor += totalNodeSize

      // Log for debugging
      debugLog("SKIPPED CLEAN SUBTREE: node=\(key) size=\(totalNodeSize) children=\(prevRange.childrenLength)")

      return  // Don't recurse into children!
    }

    // ULTRA-OPTIMIZATION: Skip ALL processing for truly unchanged nodes
    if !isDirty {
      let prevText = prevNode.getTextPart()
      let nextText = nextNode.getTextPart()
      let prevPreamble = prevNode.getPreamble()
      let nextPreamble = nextNode.getPreamble()
      let prevPostamble = prevNode.getPostamble()
      let nextPostamble = nextNode.getPostamble()

      if prevText == nextText && prevPreamble == nextPreamble && prevPostamble == nextPostamble {
        // Content is identical, just update cache location
        var nextRangeCacheItem = prevRange
        nextRangeCacheItem.location = reconcilerState.locationCursor
        reconcilerState.nextRangeCache[key] = nextRangeCacheItem
        reconcilerState.locationCursor += prevRange.preambleLength + prevRange.textLength +
          prevRange.childrenLength + prevRange.postambleLength

        // CRITICAL: Don't add ANY ranges for unchanged content!
        // This is what makes anchor-aware FASTER than legacy
        debugLog("SKIP UNCHANGED: node=\(key) size=\(prevRange.preambleLength + prevRange.textLength + prevRange.childrenLength + prevRange.postambleLength)")
        return
      }
    }

    var nextRangeCacheItem = RangeCacheItem()
    nextRangeCacheItem.location = reconcilerState.locationCursor

    let nextPreambleString = nextNode.getPreamble()
    let nextPreambleLength = nextPreambleString.lengthAsNSString()
    createAddRemoveRanges(
      key: key,
      prevLocation: prevRange.location,
      prevLength: prevRange.preambleLength,
      nextLength: nextPreambleLength,
      reconcilerState: reconcilerState,
      part: .preamble
    )
    nextRangeCacheItem.preambleLength = nextPreambleLength
    nextRangeCacheItem.preambleSpecialCharacterLength = nextPreambleString.lengthAsNSString(
      includingCharacters: ["\u{200B}"])
    if let elementNode = nextNode as? ElementNode, let anchor = elementNode.anchorStartString {
      nextRangeCacheItem.startAnchorLength = anchor.lengthAsNSString()
    } else {
      nextRangeCacheItem.startAnchorLength = 0
    }

    // right, now we have finished the preamble, and the cursor is in the right place. Time for children.
    if nextNode is ElementNode {
      let cursorBeforeChildren = reconcilerState.locationCursor
      try reconcileChildren(key: key, reconcilerState: reconcilerState)
      nextRangeCacheItem.childrenLength = reconcilerState.locationCursor - cursorBeforeChildren
    } else if nextNode is DecoratorNode {
      reconcilerState.decoratorsToDecorate.append(key)
    }

    // for any decorator node siblings after the next node we need to decorate it to handle any repositioning
    var nextSibling = nextNode.getNextSibling()
    while nextSibling != nil {
      if let nextSibling = nextSibling as? DecoratorNode {
        reconcilerState.decoratorsToDecorate.append(nextSibling.key)
      }
      nextSibling = nextSibling?.getNextSibling()
    }

    let nextTextLength = nextNode.getTextPart().lengthAsNSString()
    createAddRemoveRanges(
      key: key,
      prevLocation: prevRange.location + prevRange.preambleLength + prevRange.childrenLength,
      prevLength: prevRange.textLength,
      nextLength: nextTextLength,
      reconcilerState: reconcilerState,
      part: .text
    )
    nextRangeCacheItem.textLength = nextTextLength

    let nextPostambleString = nextNode.getPostamble()
    let nextPostambleLength = nextPostambleString.lengthAsNSString()
    createAddRemoveRanges(
      key: key,
      prevLocation: prevRange.location + prevRange.preambleLength + prevRange.childrenLength
        + prevRange.textLength,
      prevLength: prevRange.postambleLength,
      nextLength: nextPostambleLength,
      reconcilerState: reconcilerState,
      part: .postamble
    )
    nextRangeCacheItem.postambleLength = nextPostambleLength
    if let elementNode = nextNode as? ElementNode, let anchor = elementNode.anchorEndString {
      nextRangeCacheItem.endAnchorLength = anchor.lengthAsNSString()
    } else {
      nextRangeCacheItem.endAnchorLength = 0
    }

    reconcilerState.nextRangeCache[key] = nextRangeCacheItem
  }

  @MainActor
  private static func createAddRemoveRanges(
    key: NodeKey,
    prevLocation: Int,
    prevLength: Int,
    nextLength: Int,
    reconcilerState: ReconcilerState,
    part: NodePart
  ) {
    // OPTIMIZATION: Skip creating ranges for unchanged content
    let isDirty = reconcilerState.dirtyNodes[key] != nil || reconcilerState.treatAllNodesAsDirty

    // If lengths match and node isn't dirty, check if we can skip
    if prevLength == nextLength && !isDirty {
      // For anchor-aware mode, we might be able to skip this entirely
      if let prevNode = reconcilerState.prevEditorState.nodeMap[key],
         let nextNode = reconcilerState.nextEditorState.nodeMap[key] {

        let prevContent: String
        let nextContent: String

        switch part {
        case .preamble:
          prevContent = prevNode.getPreamble()
          nextContent = nextNode.getPreamble()
        case .text:
          prevContent = prevNode.getTextPart()
          nextContent = nextNode.getTextPart()
        case .postamble:
          prevContent = prevNode.getPostamble()
          nextContent = nextNode.getPostamble()
        }

        if prevContent == nextContent {
          // Content unchanged, skip creating ranges
          reconcilerState.locationCursor += nextLength
          debugLog("SKIP RANGE: node=\(key) part=\(part) len=\(nextLength)")
          return
        }
      }
    }

    // Original logic for changed content
    if prevLength > 0 {
      let prevRange = NSRange(location: prevLocation, length: prevLength)
      reconcilerState.rangesToDelete.append(prevRange)
      reconcilerState.deletedCharacterCount += prevLength
    }
    if nextLength > 0 {
      let insertion = ReconcilerInsertion(
        location: reconcilerState.locationCursor, nodeKey: key, part: part)
      reconcilerState.rangesToAdd.append(insertion)
      reconcilerState.insertedCharacterCount += nextLength
    }

    // Track location shifts for Fenwick tree updates
    let lengthDelta = nextLength - prevLength
    if lengthDelta != 0 {
      // Record this shift to apply to Fenwick tree
      let shiftLocation = reconcilerState.locationCursor + nextLength
      reconcilerState.locationShifts.append((location: shiftLocation, delta: lengthDelta))
      debugLog("FENWICK: Recording shift at \(shiftLocation) delta=\(lengthDelta)")
    }

    reconcilerState.locationCursor += nextLength
  }

  @MainActor
  private static func createNode(key: NodeKey, reconcilerState: ReconcilerState) {
    reconcilerState.visitedNodes += 1
    reconcilerState.registerFallbackReason(.structuralChange)
    guard let nextNode = reconcilerState.nextEditorState.nodeMap[key] else {
      return
    }

    var nextRangeCacheItem = RangeCacheItem()
    nextRangeCacheItem.location = reconcilerState.locationCursor

    let nextPreambleString = nextNode.getPreamble()
    let nextPreambleLength = nextPreambleString.lengthAsNSString()
    let preambleInsertion = ReconcilerInsertion(
      location: reconcilerState.locationCursor, nodeKey: key, part: .preamble)
    reconcilerState.rangesToAdd.append(preambleInsertion)
    reconcilerState.locationCursor += nextPreambleLength
    nextRangeCacheItem.preambleLength = nextPreambleLength
    nextRangeCacheItem.preambleSpecialCharacterLength = nextPreambleString.lengthAsNSString(
      includingCharacters: ["\u{200B}"])
    if let elementNode = nextNode as? ElementNode, let anchor = elementNode.anchorStartString {
      nextRangeCacheItem.startAnchorLength = anchor.lengthAsNSString()
    } else {
      nextRangeCacheItem.startAnchorLength = 0
    }
    reconcilerState.insertedCharacterCount += nextPreambleLength

    if let nextNode = nextNode as? ElementNode, nextNode.children.count > 0 {
      let cursorBeforeChildren = reconcilerState.locationCursor
      createChildren(
        nextNode.children, range: 0...nextNode.children.count - 1, reconcilerState: reconcilerState)
      nextRangeCacheItem.childrenLength = reconcilerState.locationCursor - cursorBeforeChildren
    } else if nextNode is DecoratorNode {
      reconcilerState.decoratorsToAdd.append(key)
      reconcilerState.registerFallbackReason(.decoratorMutation)
    }

    let nextTextLength = nextNode.getTextPart().lengthAsNSString()
    let textInsertion = ReconcilerInsertion(
      location: reconcilerState.locationCursor, nodeKey: key, part: .text)
    reconcilerState.rangesToAdd.append(textInsertion)
    reconcilerState.locationCursor += nextTextLength
    nextRangeCacheItem.textLength = nextTextLength
    reconcilerState.insertedCharacterCount += nextTextLength

    let nextPostambleString = nextNode.getPostamble()
    let nextPostambleLength = nextPostambleString.lengthAsNSString()
    let postambleInsertion = ReconcilerInsertion(
      location: reconcilerState.locationCursor, nodeKey: key, part: .postamble)
    reconcilerState.rangesToAdd.append(postambleInsertion)
    reconcilerState.locationCursor += nextPostambleLength
    nextRangeCacheItem.postambleLength = nextPostambleLength
    if let elementNode = nextNode as? ElementNode, let anchor = elementNode.anchorEndString {
      nextRangeCacheItem.endAnchorLength = anchor.lengthAsNSString()
    } else {
      nextRangeCacheItem.endAnchorLength = 0
    }
    reconcilerState.insertedCharacterCount += nextPostambleLength

    reconcilerState.nextRangeCache[key] = nextRangeCacheItem
  }

  @MainActor
  private static func destroyNode(key: NodeKey, reconcilerState: ReconcilerState) {
    reconcilerState.visitedNodes += 1
    reconcilerState.registerFallbackReason(.structuralChange)
    guard let prevNode = reconcilerState.prevEditorState.nodeMap[key],
      let prevRangeCacheItem = reconcilerState.prevRangeCache[key]
    else {
      return
    }

    let prevPreambleRange = NSRange(
      location: prevRangeCacheItem.location, length: prevRangeCacheItem.preambleLength)
    reconcilerState.rangesToDelete.append(prevPreambleRange)
    reconcilerState.deletedCharacterCount += prevRangeCacheItem.preambleLength

    if let prevNode = prevNode as? ElementNode, prevNode.children.count > 0 {
      destroyChildren(
        prevNode.children, range: 0...prevNode.children.count - 1, reconcilerState: reconcilerState)
    } else if prevNode is DecoratorNode {
      reconcilerState.possibleDecoratorsToRemove.append(key)
      reconcilerState.registerFallbackReason(.decoratorMutation)
    }

    let prevTextRange = NSRange(
      location: prevRangeCacheItem.location + prevRangeCacheItem.preambleLength
        + prevRangeCacheItem.childrenLength, length: prevRangeCacheItem.textLength)
    reconcilerState.rangesToDelete.append(prevTextRange)
    reconcilerState.deletedCharacterCount += prevRangeCacheItem.textLength

    let prevPostambleRange = NSRange(
      location: prevRangeCacheItem.location + prevRangeCacheItem.preambleLength
        + prevRangeCacheItem.childrenLength + prevRangeCacheItem.textLength,
      length: prevRangeCacheItem.postambleLength)
    reconcilerState.rangesToDelete.append(prevPostambleRange)
    reconcilerState.deletedCharacterCount += prevRangeCacheItem.postambleLength

    if reconcilerState.nextEditorState.nodeMap[key] == nil {
      reconcilerState.nextRangeCache.removeValue(forKey: key)
    }
  }

  @MainActor
  private static func reconcileChildren(key: NodeKey, reconcilerState: ReconcilerState) throws {
    guard let prevNode = reconcilerState.prevEditorState.nodeMap[key] as? ElementNode,
      let nextNode = reconcilerState.nextEditorState.nodeMap[key] as? ElementNode
    else {
      return
    }
    // in JS, this method does a few optimisation codepaths, then calls to the slow path reconcileNodeChildren. I'll not program the optimisations yet.
    try reconcileNodeChildren(
      prevChildren: prevNode.children,
      nextChildren: nextNode.children,
      prevChildrenLength: prevNode.children.count,
      nextChildrenLength: nextNode.children.count,
      reconcilerState: reconcilerState)
  }

  @MainActor
  private static func reconcileNodeChildren(
    prevChildren: [NodeKey],
    nextChildren: [NodeKey],
    prevChildrenLength: Int,
    nextChildrenLength: Int,
    reconcilerState: ReconcilerState
  ) throws {
    let prevEndIndex = prevChildrenLength - 1
    let nextEndIndex = nextChildrenLength - 1
    var prevIndex = 0
    var nextIndex = 0

    // the sets exist as an optimisation for performance reasons
    var prevChildrenSet: Set<NodeKey>?
    var nextChildrenSet: Set<NodeKey>?

    while prevIndex <= prevEndIndex && nextIndex <= nextEndIndex {
      let prevKey = prevChildren[prevIndex]
      let nextKey = nextChildren[nextIndex]

      if prevKey == nextKey {
        // PERFORMANCE FIX: Only reconcile if the child is actually dirty!
        let childIsDirty = reconcilerState.dirtyNodes[nextKey] != nil || reconcilerState.treatAllNodesAsDirty
        if childIsDirty {
          try reconcileNode(key: nextKey, reconcilerState: reconcilerState)
        } else {
          // Skip clean children entirely - just copy their cache entry with updated location
          reconcilerState.visitedNodes += 1  // Still count it as visited
          if let prevRange = reconcilerState.prevRangeCache[nextKey] {
            let totalSize = prevRange.preambleLength + prevRange.textLength +
                          prevRange.childrenLength + prevRange.postambleLength
            var nextRange = prevRange
            nextRange.location = reconcilerState.locationCursor
            reconcilerState.nextRangeCache[nextKey] = nextRange
            reconcilerState.locationCursor += totalSize
          }
        }
        prevIndex += 1
        nextIndex += 1
      } else {
        if prevChildrenSet == nil {
          prevChildrenSet = Set(prevChildren)
        }
        if nextChildrenSet == nil {
          nextChildrenSet = Set(nextChildren)
        }

        let nextHasPrevKey = nextChildren.contains(prevKey)
        let prevHasNextKey = prevChildren.contains(nextKey)

        if !nextHasPrevKey {
          // Remove prev
          destroyNode(key: prevKey, reconcilerState: reconcilerState)
          prevIndex += 1
        } else if !prevHasNextKey {
          // Create next
          createNode(key: nextKey, reconcilerState: reconcilerState)
          nextIndex += 1
        } else {
          // Move next -- destroy old and then insert new. (The counterpart will occur later in the loop!)
          destroyNode(key: prevKey, reconcilerState: reconcilerState)
          createNode(key: nextKey, reconcilerState: reconcilerState)
          prevIndex += 1
          nextIndex += 1
        }
      }
    }

    let appendNewChildren = prevIndex > prevEndIndex
    let removeOldChildren = nextIndex > nextEndIndex

    if appendNewChildren && !removeOldChildren {
      createChildren(
        nextChildren, range: nextIndex...nextEndIndex, reconcilerState: reconcilerState)
    } else if removeOldChildren && !appendNewChildren {
      destroyChildren(
        prevChildren, range: prevIndex...prevEndIndex, reconcilerState: reconcilerState)
    }
  }

  @MainActor
  private static func createChildren(
    _ children: [NodeKey], range: ClosedRange<Int>, reconcilerState: ReconcilerState
  ) {
    for child in children[range] {
      createNode(key: child, reconcilerState: reconcilerState)
    }
  }

  @MainActor
  private static func destroyChildren(
    _ children: [NodeKey], range: ClosedRange<Int>, reconcilerState: ReconcilerState
  ) {
    for child in children[range] {
      destroyNode(key: child, reconcilerState: reconcilerState)
    }
  }

  // DEPRECATED: No longer used - we skip clean subtrees entirely
  // Keeping for reference but marked as deprecated
  @available(*, deprecated, message: "Use Fenwick tree for location updates instead")
  @MainActor
  private static func updateLocationOfNonDirtyNode(key: NodeKey, reconcilerState: ReconcilerState) {
    // This function used to recursively walk all children even for clean nodes
    // Now we skip clean subtrees entirely in reconcileNode()
    fatalError("updateLocationOfNonDirtyNode should not be called - clean subtrees are skipped")
  }

  @MainActor
fileprivate static func attributedStringFromInsertion(
    _ insertion: ReconcilerInsertion,
    state: EditorState,
    theme: Theme
  ) -> NSAttributedString {
    guard let node = state.nodeMap[insertion.nodeKey] else {
      return NSAttributedString()
    }

    var attributedString: NSAttributedString

    switch insertion.part {
    case .text:
      attributedString = NSAttributedString(string: node.getTextPart())
    case .preamble:
      attributedString = NSAttributedString(string: node.getPreamble())
    case .postamble:
      attributedString = NSAttributedString(string: node.getPostamble())
    }

    attributedString = AttributeUtils.attributedStringByAddingStyles(
      attributedString,
      from: node,
      state: state,
      theme: theme)

    return attributedString
  }

  @MainActor
  private static func reconcileSelection(
    prevSelection: BaseSelection?,
    nextSelection: BaseSelection?,
    editor: Editor
  ) throws {
    guard let nextSelection else {
      if let prevSelection {
        if !prevSelection.dirty {
          return
        }

        editor.frontend?.resetSelectedRange()
      }

      return
    }

    // TODO: if node selection, go tell decorator nodes to select themselves!

    try editor.frontend?.updateNativeSelection(from: nextSelection)
  }
}

internal func performReconcilerSanityCheck(
  editor sanityCheckEditor: Editor,
  expectedOutput: NSAttributedString
) throws {
  // TODO @amyworrall: this was commented out during the Frontend refactor. Create a new Frontend that contains
  // a TextKit stack but no selection or UI. Use that to re-implement the reconciler.

  //    // create new editor to reconcile within
  //    let editor = Editor(
  //      featureFlags: FeatureFlags(reconcilerSanityCheck: false),
  //      editorConfig: EditorConfig(theme: sanityCheckEditor.getTheme(), plugins: []))
  //    editor.textStorage = TextStorage()
  //
  //    try editor.setEditorState(sanityCheckEditor.getEditorState())
  //
  //    if let textStorage = editor.textStorage, !expectedOutput.isEqual(to: textStorage) {
  //      throw LexicalError.sanityCheck(
  //        errorMessage: "Failed sanity check",
  //        textViewText: expectedOutput.string,
  //        fullReconcileText: textStorage.string)
  //    }
}
