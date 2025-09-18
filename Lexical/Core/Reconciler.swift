/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

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

  static func applyAnchorAwareDelta(
    state: ReconcilerState,
    textStorage: TextStorage,
    theme: Theme,
    pendingEditorState: EditorState,
    markedTextOperation: MarkedTextOperation?,
    markedTextPointForAddition: Point?,
    editor: Editor
  ) -> AnchorDeltaOutcome {
    if AnchorSanityTestHooks.forceMismatch {
      state.fallbackReason = .sanityCheckFailed
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }
    guard !state.rangesToAdd.isEmpty,
      state.rangesToAdd.count == state.rangesToDelete.count,
      let textStorageNSString = textStorage.string as NSString?
    else {
      state.registerFallbackReason(.unsupportedDelta)
      if AnchorSanityTestHooks.forceMismatch {
        state.fallbackReason = .sanityCheckFailed
      }
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }

    var replacements: [(range: NSRange, attributedString: NSAttributedString)] = []

    for (index, insertion) in state.rangesToAdd.enumerated() {
      let deletionRange = state.rangesToDelete[index]

      guard
        let nextCacheItem = state.nextRangeCache[insertion.nodeKey],
        let previousCacheItem = state.prevRangeCache[insertion.nodeKey],
        let node = pendingEditorState.nodeMap[insertion.nodeKey]
      else {
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
      let expectedAnchor: String

      switch insertion.part {
      case .preamble:
        guard
          let element = node as? ElementNode,
          let startAnchor = element.anchorStartString,
          nextCacheItem.startAnchorLength == startAnchor.lengthAsNSString()
        else {
          state.registerFallbackReason(.unsupportedDelta)
          return .fallback
        }
        anchorRange = NSRange(
          location: resolvedPreviousCacheItem.location,
          length: resolvedPreviousCacheItem.startAnchorLength)
        expectedAnchor = startAnchor
      case .postamble:
        guard
          let element = node as? ElementNode,
          let endAnchor = element.anchorEndString,
          nextCacheItem.endAnchorLength == endAnchor.lengthAsNSString()
        else {
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
        expectedAnchor = endAnchor
      case .text:
          state.registerFallbackReason(.unsupportedDelta)
          if AnchorSanityTestHooks.forceMismatch {
            state.fallbackReason = .sanityCheckFailed
          }
          AnchorSanityTestHooks.forceMismatch = false
          return .fallback
        }

      guard anchorRange == deletionRange else {
        state.registerFallbackReason(.unsupportedDelta)
        if AnchorSanityTestHooks.forceMismatch {
          state.fallbackReason = .sanityCheckFailed
        }
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }

      guard anchorRange.location + anchorRange.length <= textStorageNSString.length else {
        state.registerFallbackReason(.unsupportedDelta)
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }

      let currentAnchor = textStorageNSString.substring(with: anchorRange)
      guard currentAnchor == expectedAnchor else {
        state.registerFallbackReason(.unsupportedDelta)
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }

      let existingAttributes = textStorage.attributes(at: anchorRange.location, effectiveRange: nil)
      let replacement = NSAttributedString(string: expectedAnchor, attributes: existingAttributes)
      if replacement.length != anchorRange.length {
        state.registerFallbackReason(.unsupportedDelta)
        AnchorSanityTestHooks.forceMismatch = false
        return .fallback
      }
      replacements.append((range: anchorRange, attributedString: replacement))
    }

    guard !replacements.isEmpty else {
      state.registerFallbackReason(.unsupportedDelta)
      if AnchorSanityTestHooks.forceMismatch {
        state.fallbackReason = .sanityCheckFailed
      }
      AnchorSanityTestHooks.forceMismatch = false
      return .fallback
    }

    for replacement in replacements.reversed() {
      textStorage.replaceCharacters(in: replacement.range, with: replacement.attributedString)
    }

    for replacement in replacements {
      let fixRange = NSRange(location: replacement.range.location, length: replacement.attributedString.length)
      textStorage.fixAttributes(in: fixRange)
    }

    if AnchorSanityTestHooks.forceMismatch {
      textStorage.insert(NSAttributedString(string: "!"), at: 0)
      AnchorSanityTestHooks.forceMismatch = false
    }

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
  editor.log(
    .reconciler, .verbose,
    "about to do rangesToDelete: total \(state.rangesToDelete.count)")

  var nonEmptyDeletionsCount = 0
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
  editor.log(.reconciler, .verbose, "did rangesToDelete: non-empty \(nonEmptyDeletionsCount)")

  editor.log(
    .reconciler, .verbose, "about to do rangesToAdd: total \(state.rangesToAdd.count)")

  var markedTextAttributedString: NSAttributedString?
  var nonEmptyRangesToAddCount = 0
  var rangesInserted: [NSRange] = []
  for insertion in state.rangesToAdd {
    let attributedString = Reconciler.attributedStringFromInsertion(
      insertion,
      state: pendingEditorState,
      theme: theme)
    if attributedString.length > 0 {
      nonEmptyRangesToAddCount += 1
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

  for range in rangesInserted {
    textStorage.fixAttributes(in: range)
  }

  editor.log(.reconciler, .verbose, "did rangesToAdd: non-empty \(nonEmptyRangesToAddCount)")

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

  @MainActor
  internal static func updateEditorState(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,  // the situations where we would want to not do this include handling non-controlled mode
    markedTextOperation: MarkedTextOperation?
  ) throws {
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

    try reconcileNode(key: kRootNodeKey, reconcilerState: reconcilerState)

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()

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

    editor.rangeCache = reconcilerState.nextRangeCache
    editor.rangeCacheLocationIndex.rebuild(rangeCache: editor.rangeCache)
    textStorage.endEditing()
    textStorage.mode = previousMode
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
      if prevRange.location != reconcilerState.locationCursor {
        // we only have to update the location of this and children; all other cache values are valid
        // NB, the updateLocationOfNonDirtyNode method handles updating the reconciler state location cursor
        updateLocationOfNonDirtyNode(key: key, reconcilerState: reconcilerState)
      } else {
        // cache is already valid, just update the cursor
        // no need to iterate into children, since their cache values are valid too and we've got a cached childrenLength we can use.
        reconcilerState.locationCursor +=
          prevRange.preambleLength + prevRange.textLength + prevRange.childrenLength
          + prevRange.postambleLength
      }
      return
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
        try reconcileNode(key: nextKey, reconcilerState: reconcilerState)
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

  @MainActor
  private static func updateLocationOfNonDirtyNode(key: NodeKey, reconcilerState: ReconcilerState) {
    // not a typo that I'm setting nextRangeCacheItem to prevRangeCache[key]. We want to start with the prev cache item and update it.
    guard var nextRangeCacheItem = reconcilerState.prevRangeCache[key],
      let nextNode = reconcilerState.nextEditorState.nodeMap[key]
    else {
      // expected range cache entry to already exist
      return
    }
    reconcilerState.visitedNodes += 1
    nextRangeCacheItem.location = reconcilerState.locationCursor
    reconcilerState.nextRangeCache[key] = nextRangeCacheItem

    reconcilerState.locationCursor += nextRangeCacheItem.preambleLength
    if let nextNode = nextNode as? ElementNode {
      for childNodeKey in nextNode.children {
        updateLocationOfNonDirtyNode(key: childNodeKey, reconcilerState: reconcilerState)
      }
    }

    reconcilerState.locationCursor += nextRangeCacheItem.textLength
    reconcilerState.locationCursor += nextRangeCacheItem.postambleLength
    return
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
