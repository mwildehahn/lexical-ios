/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct RangeCacheDebugEntry: Sendable {
  public let key: NodeKey
  public let location: Int
  public let preambleLength: Int
  public let childrenLength: Int
  public let textLength: Int
  public let postambleLength: Int
  public let startAnchorLength: Int
  public let endAnchorLength: Int

  public init(
    key: NodeKey,
    location: Int,
    preambleLength: Int,
    childrenLength: Int,
    textLength: Int,
    postambleLength: Int,
    startAnchorLength: Int,
    endAnchorLength: Int
  ) {
    self.key = key
    self.location = location
    self.preambleLength = preambleLength
    self.childrenLength = childrenLength
    self.textLength = textLength
    self.postambleLength = postambleLength
    self.startAnchorLength = startAnchorLength
    self.endAnchorLength = endAnchorLength
  }
}

@MainActor
public extension Editor {
  func debugRangeCacheEntries() -> [RangeCacheDebugEntry] {
    return rangeCache.map { key, item in
      RangeCacheDebugEntry(
        key: key,
        location: item.location,
        preambleLength: item.preambleLength,
        childrenLength: item.childrenLength,
        textLength: item.textLength,
        postambleLength: item.postambleLength,
        startAnchorLength: item.startAnchorLength,
        endAnchorLength: item.endAnchorLength
      )
    }.sorted { $0.location < $1.location }
  }
}

