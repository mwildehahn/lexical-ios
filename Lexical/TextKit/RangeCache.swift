/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

/* The range cache is used when updating the NSTextStorage following a change to Lexical's
 * data model. In order to do the update with nuance, changing only the bits of the string
 * that have changed, we need to know where those bits of string are. The range cache
 * is how this information is stored, to save having to regenerate it (an expensive operation).
 */

struct RangeCacheItem {
  var location: Int = 0
  // the length of the full preamble, including any special characters
  var preambleLength: Int = 0
  // the length of any special characters in the preamble
  var preambleSpecialCharacterLength: Int = 0
  var childrenLength: Int = 0
  var textLength: Int = 0
  var postambleLength: Int = 0
  var startAnchorLength: Int = 0
  var endAnchorLength: Int = 0

  var range: NSRange {
    NSRange(
      location: location, length: preambleLength + childrenLength + textLength + postambleLength)
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
  _ location: Int, searchDirection: UITextStorageDirection, rangeCache: [NodeKey: RangeCacheItem],
  locationIndex: RangeCacheLocationIndex? = nil
) throws -> Point? {
  do {
    let searchResult = try evaluateNode(
      kRootNodeKey, stringLocation: location, searchDirection: searchDirection,
      rangeCache: rangeCache, locationIndex: locationIndex)
    guard let searchResult, let offset = searchResult.offset else {
      return nil
    }

    switch searchResult.type {
    case .endBoundary, .startBoundary, .illegal:
      return nil
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
  rangeCache: [NodeKey: RangeCacheItem], locationIndex: RangeCacheLocationIndex?
) throws -> RangeCacheSearchResult? {
  guard let rangeCacheItem = rangeCache[nodeKey], let node = getNodeByKey(key: nodeKey) else {
    throw LexicalError.rangeCacheSearch("Couldn't find node or range cache item for key \(nodeKey)")
  }

  let resolvedRangeCacheItem = rangeCacheItem.resolvingLocation(
    using: locationIndex ?? getActiveEditor()?.rangeCacheLocationIndex, key: nodeKey)

  if resolvedRangeCacheItem.startAnchorLength > 0 {
    let startAnchorRange = NSRange(
      location: resolvedRangeCacheItem.location,
      length: resolvedRangeCacheItem.startAnchorLength)
    if NSLocationInRange(stringLocation, startAnchorRange) {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .startBoundary, offset: nil)
    }
  }

  if resolvedRangeCacheItem.endAnchorLength > 0 {
    let endAnchorStart = resolvedRangeCacheItem.location + resolvedRangeCacheItem.preambleLength
      + resolvedRangeCacheItem.childrenLength + resolvedRangeCacheItem.textLength
      + resolvedRangeCacheItem.postambleLength - resolvedRangeCacheItem.endAnchorLength
    let endAnchorRange = NSRange(location: endAnchorStart, length: resolvedRangeCacheItem.endAnchorLength)
    if NSLocationInRange(stringLocation, endAnchorRange) {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .endBoundary, offset: nil)
    }
  }

  if let parentKey = node.parent, let parentRangeCacheItem = rangeCache[parentKey] {
    let resolvedParentRangeCacheItem = parentRangeCacheItem.resolvingLocation(
      using: locationIndex ?? getActiveEditor()?.rangeCacheLocationIndex, key: parentKey)
    if stringLocation == resolvedParentRangeCacheItem.location
      && resolvedParentRangeCacheItem.preambleSpecialCharacterLength
        - resolvedParentRangeCacheItem.preambleLength
        == 0
    {
      if node is TextNode {
        return RangeCacheSearchResult(nodeKey: nodeKey, type: .text, offset: 0)
      }
    }
  }

  if !resolvedRangeCacheItem.entireRange().byAddingOne().contains(stringLocation) {
    return nil
  }

  if node is TextNode {
    let expandedTextRange = resolvedRangeCacheItem.textRange().byAddingOne()
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
          rangeCache: rangeCache, locationIndex: locationIndex)
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

  if resolvedRangeCacheItem.entireRange().length == 0 {
    // caret is at the last row - element with no children
    if stringLocation == resolvedRangeCacheItem.location {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    // return the appropriate boundary for the search direction!
    let boundary: RangeCacheSearchResultType =
      (searchDirection == .forward) ? .startBoundary : .endBoundary
    return RangeCacheSearchResult(nodeKey: nodeKey, type: boundary, offset: nil)
  }

  if stringLocation == resolvedRangeCacheItem.location {
    if resolvedRangeCacheItem.preambleLength == 0 && node is ElementNode {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    return RangeCacheSearchResult(nodeKey: nodeKey, type: .startBoundary, offset: nil)
  }

  if stringLocation == resolvedRangeCacheItem.entireRange().upperBound {
    if resolvedRangeCacheItem.selectableRange().length == 0 {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    return RangeCacheSearchResult(nodeKey: nodeKey, type: .endBoundary, offset: nil)
  }

  let preambleEnd = resolvedRangeCacheItem.location + resolvedRangeCacheItem.preambleLength
  if stringLocation == preambleEnd {
    if resolvedRangeCacheItem.selectableRange().length == 0 {
      return RangeCacheSearchResult(nodeKey: nodeKey, type: .element, offset: 0)
    }

    if resolvedRangeCacheItem.childrenLength == 0 {
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
  func entireRange() -> NSRange {
    return NSRange(
      location: location, length: preambleLength + childrenLength + textLength + postambleLength)
  }
  func textRange() -> NSRange {
    return NSRange(location: location + preambleLength + childrenLength, length: textLength)
  }
  func childrenRange() -> NSRange {
    return NSRange(location: location + preambleLength, length: childrenLength)
  }
  func selectableRange() -> NSRange {
    let nonSelectableCharacters = preambleSpecialCharacterLength + startAnchorLength + endAnchorLength
    let totalLength = preambleLength + childrenLength + textLength + postambleLength
    let adjustedLength = max(0, totalLength - nonSelectableCharacters)
    return NSRange(location: location, length: adjustedLength)
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
  guard
    let editor = getActiveEditor(),
    let node = getNodeByKey(key: nodeKey) as? TextNode,
    let cacheItem = editor.rangeCache[nodeKey]
  else {
    fatalError()
  }

  let oldEnd = cacheItem.location + cacheItem.preambleLength + cacheItem.childrenLength
    + cacheItem.textLength + cacheItem.postambleLength
  editor.rangeCache[nodeKey]?.textLength = node.getTextPart().lengthAsNSString()

  if delta != 0 {
    editor.rangeCacheLocationIndex.shiftNodes(startingAt: oldEnd, delta: delta)
  }

  let parentKeys = node.getParents().map { $0.getKey() }

  for parentKey in parentKeys {
    editor.rangeCache[parentKey]?.childrenLength += delta
  }
}
