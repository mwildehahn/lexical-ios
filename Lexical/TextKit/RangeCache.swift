/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
typealias UITextStorageDirection = NSTextStorageDirection
#endif

/* The range cache is used when updating the NSTextStorage following a change to Lexical's
 * data model. In order to do the update with nuance, changing only the bits of the string
 * that have changed, we need to know where those bits of string are. The range cache
 * is how this information is stored, to save having to regenerate it (an expensive operation).
 */

struct RangeCacheItem {
  var nodeKey: NodeKey = ""
  // Dual storage: location for legacy reconciler, nodeIndex for optimized reconciler with Fenwick tree
  var location: Int = 0  // Absolute location for legacy reconciler
  var nodeIndex: Int = 0  // Index in the Fenwick tree for optimized reconciler

  // the length of the full preamble, including any special characters
  var preambleLength: Int = 0
  // the length of any special characters in the preamble
  var preambleSpecialCharacterLength: Int = 0
  var childrenLength: Int = 0
  var textLength: Int = 0
  var postambleLength: Int = 0

  // For optimized reconciler: compute location dynamically from Fenwick tree
  @MainActor
  func locationFromFenwick(using fenwickTree: FenwickTree) -> Int {
    // For element nodes, the caller (tests) expects this to return the element's
    // absolute start. Compute via absolute accumulation since a single-index
    // Fenwick representation cannot encode both pre/post positions.
    if let _ = getNodeByKey(key: nodeKey) as? ElementNode,
       let editor = getActiveEditor() {
      let base = absoluteNodeStartLocation(nodeKey, rangeCache: editor.rangeCache, useOptimized: true, fenwickTree: editor.fenwickTree, leadingShift: false)
      return base
    }
    return fenwickTree.getNodeOffset(nodeIndex: nodeIndex)
  }

  // Get range using absolute location (legacy reconciler)
  var range: NSRange {
    return NSRange(location: location, length: preambleLength + childrenLength + textLength + postambleLength)
  }

  // Get range using Fenwick tree (optimized reconciler)
  @MainActor
  func rangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    NSRange(
      location: locationFromFenwick(using: fenwickTree),
      length: preambleLength + childrenLength + textLength + postambleLength)
  }
}

// MARK: - Search for nodes based on range

/*
 * This method is used to search a combination of the node tree and the range cache, to find a Point for a given
 * string location. The string location can be 0 <= x <= length. Location is specified in UTF16 code points, as
 * used by NSString. (Note that Swift string locations are not compatible.)
 *
 * If the string location falls in an invalid place (such as inside a multi-character preamble), this method
 * will return nil.
 *
 * searchDirection is used to break ties for when there would be more than one valid Point for a location. For
 * example, if the location sits between two consecutive Text nodes, the Point could either be at the end of the
 * first Text node, or at the start of the second Text node.
 */
@MainActor
internal func pointAtStringLocation(
  _ location: Int, searchDirection: UITextStorageDirection, rangeCache: [NodeKey: RangeCacheItem]
) throws -> Point? {
  // Fast-path (diagnostic mode only): exact element childrenStart boundary maps to element offset 0
  if let editor = getActiveEditor(), editor.featureFlags.selectionParityDebug, editor.featureFlags.optimizedReconciler {
    let useOptimized = editor.featureFlags.optimizedReconciler
    let fenwickTree = editor.fenwickTree
    for (k, item) in rangeCache {
      if let _ = getNodeByKey(key: k) as? ElementNode {
        let base = useOptimized
          ? absoluteNodeStartLocation(k, rangeCache: rangeCache, useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
          : item.location
        let childrenStart = base + item.preambleLength
        if location == childrenStart {
          return Point(key: k, offset: 0, type: .element)
        }
      }
    }
  }
  do {
    let searchResult = try evaluateNode(
      kRootNodeKey, stringLocation: location, searchDirection: searchDirection,
      rangeCache: rangeCache)
    guard let searchResult, let offset = searchResult.offset else {
      return nil
    }

    switch searchResult.type {
    case .endBoundary, .startBoundary, .illegal:
      throw LexicalError.internal("Failed to find node for location: \(location)")
    case .text:
      return Point(key: searchResult.nodeKey, offset: offset, type: .text)
    case .element:
      return Point(key: searchResult.nodeKey, offset: offset, type: .element)
    }
  } catch LexicalError.rangeCacheSearch {
    return nil
  }
}

@MainActor
private func evaluateNode(
  _ nodeKey: NodeKey, stringLocation: Int, searchDirection: UITextStorageDirection,
  rangeCache: [NodeKey: RangeCacheItem]
) throws -> RangeCacheSearchResult? {
  guard let rangeCacheItem = rangeCache[nodeKey],
        let node = getNodeByKey(key: nodeKey),
        let editor = getActiveEditor() else {
    throw LexicalError.rangeCacheSearch("Couldn't find node or range cache item for key \(nodeKey)")
  }

  // Use appropriate method based on feature flag
  let useOptimized = editor.featureFlags.optimizedReconciler
  let fenwickTree = editor.fenwickTree
  if editor.featureFlags.selectionParityDebug {
    let nodeType: String = (node is TextNode) ? "Text" : ((node is ElementNode) ? "Element" : String(describing: type(of: node)))
    let base = useOptimized ? rangeCacheItem.locationFromFenwick(using: fenwickTree) : rangeCacheItem.location
    print("🔥 EVAL node=\(nodeKey) type=\(nodeType) baseStart=\(base) loc=\(stringLocation) dir=\(searchDirection == .forward ? "fwd" : "back") pre=\(rangeCacheItem.preambleLength) ch=\(rangeCacheItem.childrenLength) tx=\(rangeCacheItem.textLength) post=\(rangeCacheItem.postambleLength)")
  }

  if let parentKey = node.parent, let parentRangeCacheItem = rangeCache[parentKey] {
    let parentLocation = useOptimized
      ? absoluteNodeStartLocation(parentKey, rangeCache: rangeCache, useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
      : parentRangeCacheItem.location
    if stringLocation == parentLocation
      && parentRangeCacheItem.preambleSpecialCharacterLength == 0
    {
      if editor.featureFlags.selectionParityDebug {
        print("🔥 RANGE CACHE PARITY: at parent-start boundary for child \(nodeKey), mapping to text-start if TextNode")
      }
      if node is TextNode {
        return RangeCacheSearchResult(nodeKey: nodeKey, type: .text, offset: 0)
      }
    }
  }

  // Compute absolute start using unified logic, then derive ranges from cached lengths.
  let nodeStart = useOptimized
    ? absoluteNodeStartLocation(nodeKey, rangeCache: rangeCache, useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
    : rangeCacheItem.location
  let entireRange = NSRange(location: nodeStart, length: rangeCacheItem.preambleLength + rangeCacheItem.childrenLength + rangeCacheItem.textLength + rangeCacheItem.postambleLength)
  if !entireRange.byAddingOne().contains(stringLocation) {
    return nil
  }

  if node is TextNode {
    let textRange = NSRange(location: nodeStart + rangeCacheItem.preambleLength + rangeCacheItem.childrenLength, length: rangeCacheItem.textLength)
    // Tie-break at text end:
    // - Parity diagnostics (selectionParityDebug=true): forward excludes text end (prefers next), backward includes.
    // - Baseline (default): forward includes text end (stays on current), backward excludes.
    let useParity = getActiveEditor()?.featureFlags.selectionParityDebug == true
    let rangeToUse: NSRange = {
      if useParity {
        return (searchDirection == .forward) ? textRange : textRange.byAddingOne()
      } else {
        return (searchDirection == .forward) ? textRange.byAddingOne() : textRange
      }
    }()
    if rangeToUse.contains(stringLocation) {
      let offset = stringLocation - textRange.location
      // Clamp inside [0, textLength] for safety
      let clamped = max(0, min(rangeCacheItem.textLength, offset))
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .text, offset: clamped)
    }
  }

  if let node = node as? ElementNode {
    let childrenArray =
      (searchDirection == .forward) ? node.getChildrenKeys() : node.getChildrenKeys().reversed()

    var possibleBoundaryElementResult: RangeCacheSearchResult?
    for childKey in childrenArray {
      // note: I'm using try? because that lets us attempt to still return a selection even if there's an error deeper in the tree.
      // This might be a mistake, in which case we can change it to just `try` and propagate the exception. @amyworrall
      guard
        let result = try? evaluateNode(
          childKey, stringLocation: stringLocation, searchDirection: searchDirection,
          rangeCache: rangeCache)
      else { continue }
      if result.type == .text || result.type == .element {
        if editor.featureFlags.selectionParityDebug {
          print("🔥 EVAL child direct result: parent=\(nodeKey) child=\(childKey) type=\(result.type) offset=\(result.offset ?? -1)")
        }
        return result
      }
      guard let childIndex = node.getChildrenKeys().firstIndex(of: childKey) else { continue }
      if result.type == .startBoundary {
        // the boundary of a child, so return self key with appropriate offset
        possibleBoundaryElementResult = RangeCacheSearchResult(
          nodeKey: nodeKey, type: .element, offset: childIndex)
      }
      if result.type == .endBoundary {
        possibleBoundaryElementResult = RangeCacheSearchResult(
          nodeKey: nodeKey, type: .element, offset: childIndex + 1)
      }
    }

    if let possibleBoundaryElementResult {
      if editor.featureFlags.selectionParityDebug {
        print("🔥 RANGE CACHE PARITY: child boundary -> returning element offset for parent=\(nodeKey) offset=\(possibleBoundaryElementResult.offset ?? -1)")
      }
      // We do this 'possible result' check so that we prioritise text results where we can.
      return possibleBoundaryElementResult
    }

    // Fallback: if no child yielded a direct result, try mapping exact boundaries
    // to element offsets to avoid nil results at child start/end boundaries.
    let normalOrderChildren = node.getChildrenKeys()
    // Compute parent start for convenience
    let parentStart = nodeStart
    // Start of children content
    let childrenStart = parentStart + rangeCacheItem.preambleLength
    // End of children content
    let childrenEnd = childrenStart + rangeCacheItem.childrenLength
    if editor.featureFlags.selectionParityDebug {
      print("🔥 EVAL element=\(nodeKey) parentStart=\(parentStart) childrenStart=\(childrenStart) childrenEnd=\(childrenEnd) childCount=\(normalOrderChildren.count)")
      for ck in normalOrderChildren {
        if let c = rangeCache[ck] {
          let cStart = useOptimized ? absoluteNodeStartLocation(ck, rangeCache: rangeCache, useOptimized: true, fenwickTree: fenwickTree, leadingShift: false) : c.location
          let cType = (getNodeByKey(key: ck) is TextNode) ? "Text" : "Elem"
          print("  🔹 child key=\(ck) type=\(cType) start=\(cStart) pre=\(c.preambleLength) ch=\(c.childrenLength) tx=\(c.textLength) post=\(c.postambleLength)")
        }
      }
    }

    // Exact start/end first only in parity diagnostics
    if editor.featureFlags.selectionParityDebug {
      if stringLocation == childrenStart {
        print("🔥 RANGE CACHE PARITY: exact childrenStart -> element offset 0 for node=\(nodeKey)")
        return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
      }
      if stringLocation == childrenEnd {
        print("🔥 RANGE CACHE PARITY: exact childrenEnd -> element offset count for node=\(nodeKey)")
        return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: normalOrderChildren.count)
      }
    }

    // Check exact match to each child's start location with canonical tie-breaks (takes precedence)
    for (idx, ck) in normalOrderChildren.enumerated() {
      if let childItem = rangeCache[ck] {
        let childStart = useOptimized
          ? absoluteNodeStartLocation(ck, rangeCache: rangeCache, useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
          : childItem.location
        if stringLocation == childStart {
          if editor.featureFlags.selectionParityDebug {
            print("🔥 EVAL tie childStart: parent=\(nodeKey) child=\(ck) idx=\(idx) dir=\(searchDirection == .forward ? "fwd" : "back")")
          }

          if editor.featureFlags.selectionParityDebug {
            print("🔥 RANGE CACHE PARITY: exact child start -> canonical tie-break. parent=\(nodeKey) child=\(ck) idx=\(idx) dir=\(searchDirection == .forward ? "fwd" : "back")")
          }
          if searchDirection == .forward {
            if let _ = getNodeByKey(key: ck) as? TextNode {
              return RangeCacheSearchResult(nodeKey: ck, type: .text, offset: 0)
            }
            return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: idx)
          } else {
            if idx > 0 {
              let prevKey = normalOrderChildren[idx - 1]
              if let prevItem = rangeCache[prevKey], let _ = getNodeByKey(key: prevKey) as? TextNode {
                return RangeCacheSearchResult(nodeKey: prevKey, type: .text, offset: prevItem.textLength)
              }
            }
            return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: idx)
          }
        }
      }
    }

    
  }

  let entireRangeForCheck = useOptimized ? rangeCacheItem.entireRangeFromFenwick(using: fenwickTree) : rangeCacheItem.entireRange
  if entireRangeForCheck.length == 0 {
    // caret is at the last row - element with no children
    let itemLocation = useOptimized ? rangeCacheItem.locationFromFenwick(using: fenwickTree) : rangeCacheItem.location
    if stringLocation == itemLocation {
      if editor.featureFlags.selectionParityDebug {
        print("🔥 RANGE CACHE PARITY: empty element at start -> element offset 0 for node=\(nodeKey)")
      }
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    // return the appropriate boundary for the search direction!
    let boundary: RangeCacheSearchResultType =
      (searchDirection == .forward) ? .startBoundary : .endBoundary
    return RangeCacheSearchResult(nodeKey: nodeKey, type: boundary, offset: nil)
  }

  let itemLocation = nodeStart
  if stringLocation == itemLocation {
    if rangeCacheItem.preambleLength == 0 && node is ElementNode {
      if editor.featureFlags.selectionParityDebug {
        print("🔥 RANGE CACHE PARITY: element at start with no preamble -> element offset 0 for node=\(nodeKey)")
      }
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }
    return RangeCacheSearchResult(nodeKey: nodeKey, type: .startBoundary, offset: nil)
  }

  if stringLocation == entireRangeForCheck.upperBound {
    let selectableRange = useOptimized ? rangeCacheItem.selectableRangeFromFenwick(using: fenwickTree) : rangeCacheItem.selectableRange
    if selectableRange.length == 0 {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }
    return RangeCacheSearchResult(nodeKey: nodeKey, type: .endBoundary, offset: nil)
  }

  let preambleEnd = itemLocation + rangeCacheItem.preambleLength
  if stringLocation == preambleEnd {
    let selectableRange = useOptimized ? rangeCacheItem.selectableRangeFromFenwick(using: fenwickTree) : rangeCacheItem.selectableRange
    if selectableRange.length == 0 {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }
    if rangeCacheItem.childrenLength == 0 {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }
    return RangeCacheSearchResult(nodeKey: nodeKey, type: .startBoundary, offset: nil)
  }

  return RangeCacheSearchResult(nodeKey: nodeKey, type: .illegal, offset: nil)
}

extension NSRange {
  fileprivate func byAddingOne() -> NSRange {
    return NSRange(location: location, length: length + 1)
  }
}

extension RangeCacheItem {
  // Legacy reconciler methods (use absolute location)
  var entireRange: NSRange {
    return NSRange(
      location: location, length: preambleLength + childrenLength + textLength + postambleLength)
  }

  var textRange: NSRange {
    return NSRange(location: location + preambleLength + childrenLength, length: textLength)
  }

  var childrenRange: NSRange {
    return NSRange(location: location + preambleLength, length: childrenLength)
  }

  var selectableRange: NSRange {
    return NSRange(location: location, length: preambleLength + childrenLength + textLength + postambleLength - preambleSpecialCharacterLength)
  }

  // Optimized reconciler methods (use Fenwick tree)
  @MainActor
  func entireRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let editor = getActiveEditor()
    let start = absoluteNodeStartLocation(nodeKey, rangeCache: editor?.rangeCache ?? [:], useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
    return NSRange(location: start, length: preambleLength + childrenLength + textLength + postambleLength)
  }

  @MainActor
  func textRangeFromFenwick(using fenwickTree: FenwickTree, leadingShift: Bool = false, rangeCache cache: [NodeKey: RangeCacheItem]? = nil) -> NSRange {
    let editor = getActiveEditor()
    let rc = cache ?? editor?.rangeCache ?? [:]
    let useShift = false
    let start = absoluteNodeStartLocation(nodeKey, rangeCache: rc, useOptimized: true, fenwickTree: fenwickTree, leadingShift: useShift)
    return NSRange(location: start + preambleLength + childrenLength, length: textLength)
  }

  @MainActor
  func childrenRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let editor = getActiveEditor()
    let start = absoluteNodeStartLocation(nodeKey, rangeCache: editor?.rangeCache ?? [:], useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
    return NSRange(location: start + preambleLength, length: childrenLength)
  }

  @MainActor
  func selectableRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let editor = getActiveEditor()
    let start = absoluteNodeStartLocation(nodeKey, rangeCache: editor?.rangeCache ?? [:], useOptimized: true, fenwickTree: fenwickTree, leadingShift: false)
    return NSRange(location: start, length: preambleLength + childrenLength + textLength + postambleLength - preambleSpecialCharacterLength)
  }
}

private struct RangeCacheSearchResult {
  let nodeKey: NodeKey
  let type: RangeCacheSearchResultType
  let offset: Int?
}

private enum RangeCacheSearchResultType {
  case startBoundary  // the boundary types are converted to element type for the parent element
  case endBoundary
  case text
  case element
  case illegal  // used for if the search is inside a multi-character preamble/postamble
}

@MainActor
internal func updateRangeCacheForTextChange(nodeKey: NodeKey, delta: Int) {
  guard let editor = getActiveEditor(), let node = getNodeByKey(key: nodeKey) as? TextNode else {
    fatalError()
  }

  // Update the text length in the cache
  let oldTextLength = editor.rangeCache[nodeKey]?.textLength ?? 0
  editor.rangeCache[nodeKey]?.textLength = node.getTextPart().lengthAsNSString()
  let newTextLength = editor.rangeCache[nodeKey]?.textLength ?? 0

  // Update parent nodes' children length
  let parentKeys = node.getParents().map { $0.getKey() }
  for parentKey in parentKeys {
    editor.rangeCache[parentKey]?.childrenLength += delta
  }

  // Update the Fenwick tree with the length change
  if let cacheItem = editor.rangeCache[nodeKey] {
    editor.fenwickTree.updateNodeLength(
      nodeIndex: cacheItem.nodeIndex,
      oldLength: oldTextLength,
      newLength: newTextLength
    )
  }
}
