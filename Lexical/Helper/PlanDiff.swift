/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)

import Foundation
import LexicalCore

@MainActor
struct NodePartDiff: Sendable {
  public let key: NodeKey
  public let preDelta: Int
  public let textDelta: Int
  public let postDelta: Int
  public var entireDelta: Int { preDelta + textDelta + postDelta }
}

/// Computes per-node deltas for preamble/text/postamble lengths between prev (range cache) and pending state
/// for the current update cycle. Only nodes present in both states and marked dirty are considered.
@MainActor
func computePartDiffs(
  editor: Editor,
  prevState: EditorState,
  nextState: EditorState,
  prevRangeCache: [NodeKey: RangeCacheItem]? = nil,
  keys: [NodeKey]? = nil
) -> [NodeKey: NodePartDiff] {
  var out: [NodeKey: NodePartDiff] = [:]
  let prevMap = prevRangeCache ?? editor.rangeCache
  let sourceKeys: [NodeKey] = keys ?? Array(editor.dirtyNodes.keys)
  for key in sourceKeys {
    guard let prev = prevMap[key], let next = nextState.nodeMap[key] else { continue }
    let preNext = next.getPreamble().lengthAsNSString()
    let textNext = next.getTextPart().lengthAsNSString()
    let postNext = next.getPostamble().lengthAsNSString()
    let preDelta = preNext - prev.preambleLength
    let textDelta = textNext - prev.textLength
    let postDelta = postNext - prev.postambleLength
    if preDelta != 0 || textDelta != 0 || postDelta != 0 {
      out[key] = NodePartDiff(key: key, preDelta: preDelta, textDelta: textDelta, postDelta: postDelta)
    }
  }
  return out
}
#endif  // canImport(UIKit)
