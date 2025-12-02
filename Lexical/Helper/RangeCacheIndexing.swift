/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)

import Foundation
import LexicalCore

/// Returns node keys sorted by their string location ascending, breaking ties by longer range first.
/// Mirrors sorting used in RangeHelpers.allNodeKeysSortedByLocation but operates on an explicit cache.
@MainActor
internal func sortedNodeKeysByLocation(rangeCache: [NodeKey: RangeCacheItem]) -> [NodeKey] {
  return rangeCache
    .map { $0 }
    .sorted { a, b in
      if a.value.location != b.value.location {
        return a.value.location < b.value.location
      }
      return a.value.range.length > b.value.range.length
    }
    .map { $0.key }
}
#endif  // canImport(UIKit)
