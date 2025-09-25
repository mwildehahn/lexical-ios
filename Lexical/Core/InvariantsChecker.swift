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

@MainActor
internal struct InvariantsReport {
  let issues: [String]
  var isClean: Bool { issues.isEmpty }
}

/// Validates key invariants between RangeCache, Fenwick tree, and TextStorage.
/// Intended for debug/diagnostics; never throws in production paths.
@MainActor
internal func validateEditorInvariants(editor: Editor) -> InvariantsReport {
  var issues: [String] = []

  guard let textStorage = editor.textStorage else {
    return InvariantsReport(issues: ["No TextStorage attached to editor"]) 
  }

  let fenwick = editor.fenwickTree
  let rangeCache = editor.rangeCache

  // 1) Root covers entire document
  if let rootItem = rangeCache[kRootNodeKey] {
    let rootRange = rootItem.entireRangeFromFenwick(using: fenwick)
    if rootRange.length != textStorage.length {
      issues.append("Root entireRange(\(rootRange.length)) != textStorage.length(\(textStorage.length))")
    }
  } else {
    issues.append("Missing rangeCache for root node")
  }

  // 2) Element children's sum equals childrenLength
  for (key, item) in rangeCache {
    guard let node = editor.getEditorState().nodeMap[key] else { continue }
    if let element = node as? ElementNode {
      var childrenSum = 0
      for childKey in element.getChildrenKeys() {
        if let childItem = rangeCache[childKey] {
          childrenSum += childItem.preambleLength + childItem.childrenLength + childItem.textLength + childItem.postambleLength
        }
      }
      if childrenSum != item.childrenLength {
        issues.append("childrenLength mismatch for \(key): cache=\(item.childrenLength) sum=\(childrenSum)")
      }
    }
  }

  // 3) TextNode text matches TextStorage substring at textRange
  for (key, item) in rangeCache {
    guard let node = editor.getEditorState().nodeMap[key] as? TextNode else { continue }
    let tr = item.textRangeFromFenwick(using: fenwick, leadingShift: editor.featureFlags.leadingNewlineBaselineShift, rangeCache: editor.rangeCache)
    if NSMaxRange(tr) <= textStorage.length { // sanity guard
      let storageText = textStorage.attributedSubstring(from: tr).string
      let nodeText = node.getText_dangerousPropertyAccess()
      if storageText != nodeText {
        issues.append("Text mismatch for \(key): storage='\(storageText)' node='\(nodeText)'")
      }
    } else {
      issues.append("Text range out of bounds for \(key): \(tr) vs length=\(textStorage.length)")
    }
  }

  return InvariantsReport(issues: issues)
}
