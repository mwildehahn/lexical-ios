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
    return fenwickTree.getNodeOffset(nodeIndex: nodeIndex)
  }

  // Get range using absolute location (legacy reconciler)
  var range: NSRange {
    NSRange(
      location: location,
      length: preambleLength + childrenLength + textLength + postambleLength)
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

  if let parentKey = node.parent, let parentRangeCacheItem = rangeCache[parentKey] {
    let parentLocation = useOptimized ? parentRangeCacheItem.locationFromFenwick(using: fenwickTree) : parentRangeCacheItem.location
    if stringLocation == parentLocation
      && parentRangeCacheItem.preambleSpecialCharacterLength - parentRangeCacheItem.preambleLength
        == 0
    {
      if node is TextNode {
        return RangeCacheSearchResult(nodeKey: nodeKey, type: .text, offset: 0)
      }
    }
  }

  let entireRange = useOptimized ? rangeCacheItem.entireRangeFromFenwick(using: fenwickTree) : rangeCacheItem.entireRange
  if !entireRange.byAddingOne().contains(stringLocation) {
    return nil
  }

  if node is TextNode {
    let textRange = useOptimized ? rangeCacheItem.textRangeFromFenwick(using: fenwickTree) : rangeCacheItem.textRange
    let expandedTextRange = textRange.byAddingOne()
    if expandedTextRange.contains(stringLocation) {
      return RangeCacheSearchResult(
        nodeKey: nodeKey, type: .text, offset: stringLocation - expandedTextRange.location)
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
      // We do this 'possible result' check so that we prioritise text results where we can.
      return possibleBoundaryElementResult
    }
  }

  let entireRangeForCheck = useOptimized ? rangeCacheItem.entireRangeFromFenwick(using: fenwickTree) : rangeCacheItem.entireRange
  if entireRangeForCheck.length == 0 {
    // caret is at the last row - element with no children
    let itemLocation = useOptimized ? rangeCacheItem.locationFromFenwick(using: fenwickTree) : rangeCacheItem.location
    if stringLocation == itemLocation {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    // return the appropriate boundary for the search direction!
    let boundary: RangeCacheSearchResultType =
      (searchDirection == .forward) ? .startBoundary : .endBoundary
    return RangeCacheSearchResult(nodeKey: nodeKey, type: boundary, offset: nil)
  }

  let itemLocation = useOptimized ? rangeCacheItem.locationFromFenwick(using: fenwickTree) : rangeCacheItem.location
  if stringLocation == itemLocation {
    if rangeCacheItem.preambleLength == 0 && node is ElementNode {
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
    return NSRange(
      location: location,
      length: preambleLength + childrenLength + textLength + postambleLength
        - preambleSpecialCharacterLength)
  }

  // Optimized reconciler methods (use Fenwick tree)
  @MainActor
  func entireRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let loc = locationFromFenwick(using: fenwickTree)
    return NSRange(
      location: loc, length: preambleLength + childrenLength + textLength + postambleLength)
  }

  @MainActor
  func textRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let loc = locationFromFenwick(using: fenwickTree)
    return NSRange(location: loc + preambleLength + childrenLength, length: textLength)
  }

  @MainActor
  func childrenRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let loc = locationFromFenwick(using: fenwickTree)
    return NSRange(location: loc + preambleLength, length: childrenLength)
  }

  @MainActor
  func selectableRangeFromFenwick(using fenwickTree: FenwickTree) -> NSRange {
    let loc = locationFromFenwick(using: fenwickTree)
    return NSRange(
      location: loc,
      length: preambleLength + childrenLength + textLength + postambleLength
        - preambleSpecialCharacterLength)
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

