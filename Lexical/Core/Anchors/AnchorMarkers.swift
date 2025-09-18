/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

internal enum AnchorMarkerKind: String {
  case start = "S"
  case end = "E"
}

internal struct AnchorMarker {
  internal let kind: AnchorMarkerKind
  internal let nodeKey: NodeKey
}

internal enum AnchorMarkers {
  private static let prefix = "\u{F8F0}"
  private static let suffix = "\u{F8F1}"
  private static let separator: Character = ":"

  static func make(kind: AnchorMarkerKind, key: NodeKey) -> String {
    return prefix + kind.rawValue + String(separator) + key + suffix
  }

  static func parse(_ marker: String) -> AnchorMarker? {
    guard marker.hasPrefix(prefix), marker.hasSuffix(suffix) else {
      return nil
    }

    let trimmed = marker.dropFirst(prefix.count).dropLast(suffix.count)
    guard let separatorIndex = trimmed.firstIndex(of: separator) else {
      return nil
    }

    let kindSubstring = trimmed[..<separatorIndex]
    let keySubstring = trimmed[trimmed.index(after: separatorIndex)...]

    guard let kind = AnchorMarkerKind(rawValue: String(kindSubstring)) else {
      return nil
    }

    return AnchorMarker(kind: kind, nodeKey: String(keySubstring))
  }

  static func stripAnchors(from string: String) -> String {
    guard string.contains(prefix) else {
      return string
    }

    let mutable = NSMutableString(string: string)
    removeAnchorRanges(from: mutable)
    return String(mutable)
  }

  static func stripAnchors(from attributedString: NSAttributedString) -> NSAttributedString {
    guard attributedString.string.contains(prefix) else {
      return attributedString
    }

    let mutable = NSMutableAttributedString(attributedString: attributedString)
    removeAnchorRanges(from: mutable)
    return mutable
  }

  private static func removeAnchorRanges(from mutableString: NSMutableString) {
    let ranges = anchorRanges(in: mutableString)
    for range in ranges.reversed() {
      mutableString.deleteCharacters(in: range)
    }
  }

  private static func removeAnchorRanges(from attributedString: NSMutableAttributedString) {
    let ranges = anchorRanges(in: attributedString.mutableString)
    for range in ranges.reversed() {
      attributedString.deleteCharacters(in: range)
    }
  }

  private static func anchorRanges(in string: NSMutableString) -> [NSRange] {
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: string.length)
    while true {
      let prefixRange = string.range(of: prefix, options: [.literal], range: searchRange)
      if prefixRange.location == NSNotFound {
        break
      }

      let suffixSearchStart = prefixRange.location + prefixRange.length
      let suffixSearchRange = NSRange(
        location: suffixSearchStart,
        length: string.length - suffixSearchStart)
      let suffixRange = string.range(of: suffix, options: [.literal], range: suffixSearchRange)
      if suffixRange.location == NSNotFound {
        break
      }

      let anchorLength = (suffixRange.location + suffixRange.length) - prefixRange.location
      let anchorRange = NSRange(location: prefixRange.location, length: anchorLength)
      ranges.append(anchorRange)

      let nextStart = anchorRange.location + anchorRange.length
      if nextStart >= string.length {
        break
      }
      searchRange = NSRange(location: nextStart, length: string.length - nextStart)
    }
    return ranges
  }
}
