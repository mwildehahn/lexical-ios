/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Maps node keys to their anchor positions in TextStorage for O(1) lookup
@MainActor
internal final class AnchorIndex {

  /// Maps node keys to their start and end anchor positions
  private struct AnchorPosition {
    var startRange: NSRange  // Range of the start anchor marker
    var endRange: NSRange    // Range of the end anchor marker
    var contentRange: NSRange // Range between start and end anchors (the actual node content)
  }

  private var anchorPositions: [NodeKey: AnchorPosition] = [:]
  private var textStorageString: NSString = ""

  /// Find a node's position in TextStorage using its anchors
  func findNode(_ key: NodeKey) -> NSRange? {
    return anchorPositions[key]?.contentRange
  }

  /// Find the node that contains a given text position
  func findNodeContaining(location: Int) -> NodeKey? {
    for (key, position) in anchorPositions {
      let fullRange = NSRange(
        location: position.startRange.location,
        length: position.endRange.location + position.endRange.length - position.startRange.location
      )
      if NSLocationInRange(location, fullRange) {
        return key
      }
    }
    return nil
  }

  /// Find nodes near a position for insertion
  func findNodesNear(location: Int) -> (before: NodeKey?, after: NodeKey?) {
    var before: (key: NodeKey, endLocation: Int)?
    var after: (key: NodeKey, startLocation: Int)?

    for (key, position) in anchorPositions {
      let nodeEnd = position.endRange.location + position.endRange.length
      let nodeStart = position.startRange.location

      // Node ends before location
      if nodeEnd <= location {
        if before == nil || before!.endLocation < nodeEnd {
          before = (key, nodeEnd)
        }
      }

      // Node starts after location
      if nodeStart >= location {
        if after == nil || after!.startLocation > nodeStart {
          after = (key, nodeStart)
        }
      }
    }

    return (before?.key, after?.key)
  }

  /// Rebuild the entire index from TextStorage
  func rebuild(from textStorage: NSTextStorage) {
    anchorPositions.removeAll()
    textStorageString = textStorage.string as NSString

    // Scan for all anchor patterns in the text
    let anchorPattern = "\u{F8F0}[SE]:[^:\u{F8F1}]+\u{F8F1}"

    do {
      let regex = try NSRegularExpression(pattern: anchorPattern, options: [])
      let matches = regex.matches(
        in: textStorageString as String,
        options: [],
        range: NSRange(location: 0, length: textStorageString.length)
      )

      // Group matches by node key
      var startAnchors: [NodeKey: NSRange] = [:]
      var endAnchors: [NodeKey: NSRange] = [:]

      for match in matches {
        let matchedString = textStorageString.substring(with: match.range)
        if let anchor = AnchorMarkers.parse(matchedString) {
          switch anchor.kind {
          case .start:
            startAnchors[anchor.nodeKey] = match.range
          case .end:
            endAnchors[anchor.nodeKey] = match.range
          }
        }
      }

      // Build anchor positions for nodes that have both start and end
      for (key, startRange) in startAnchors {
        if let endRange = endAnchors[key] {
          let contentLocation = startRange.location + startRange.length
          let contentLength = endRange.location - contentLocation

          anchorPositions[key] = AnchorPosition(
            startRange: startRange,
            endRange: endRange,
            contentRange: NSRange(location: contentLocation, length: contentLength)
          )
        }
      }

    } catch {
      // If regex fails, fall back to empty index
      print("🪲 AnchorIndex: Failed to build anchor index: \(error)")
    }
  }

  /// Update the index after a local change
  func updateAfterInsertion(at location: Int, length: Int, nodeKey: NodeKey?) {
    // Shift all anchors after the insertion point
    var updatedPositions: [NodeKey: AnchorPosition] = [:]

    for (key, position) in anchorPositions {
      if key == nodeKey {
        // This is the newly inserted node, will be updated separately
        continue
      }

      var newPosition = position

      // Shift start anchor if after insertion
      if position.startRange.location >= location {
        newPosition.startRange.location += length
      }

      // Shift end anchor if after insertion
      if position.endRange.location >= location {
        newPosition.endRange.location += length
      }

      // Recalculate content range
      let contentLocation = newPosition.startRange.location + newPosition.startRange.length
      let contentLength = newPosition.endRange.location - contentLocation
      newPosition.contentRange = NSRange(location: contentLocation, length: contentLength)

      updatedPositions[key] = newPosition
    }

    anchorPositions = updatedPositions
  }

  /// Update the index after a deletion
  func updateAfterDeletion(range: NSRange) {
    var updatedPositions: [NodeKey: AnchorPosition] = [:]

    for (key, position) in anchorPositions {
      // Check if this node was deleted
      let nodeFullRange = NSRange(
        location: position.startRange.location,
        length: position.endRange.location + position.endRange.length - position.startRange.location
      )

      if NSLocationInRange(nodeFullRange.location, range) &&
         NSLocationInRange(nodeFullRange.location + nodeFullRange.length - 1, range) {
        // Node was deleted, remove from index
        continue
      }

      var newPosition = position

      // Shift start anchor if after deletion
      if position.startRange.location >= range.location + range.length {
        newPosition.startRange.location -= range.length
      }

      // Shift end anchor if after deletion
      if position.endRange.location >= range.location + range.length {
        newPosition.endRange.location -= range.length
      }

      // Recalculate content range
      let contentLocation = newPosition.startRange.location + newPosition.startRange.length
      let contentLength = newPosition.endRange.location - contentLocation
      newPosition.contentRange = NSRange(location: contentLocation, length: contentLength)

      updatedPositions[key] = newPosition
    }

    anchorPositions = updatedPositions
  }

  /// Clear the index
  func clear() {
    anchorPositions.removeAll()
    textStorageString = ""
  }

  /// Get statistics about the index
  var nodeCount: Int {
    return anchorPositions.count
  }

  /// Check if a node is in the index
  func contains(_ key: NodeKey) -> Bool {
    return anchorPositions[key] != nil
  }
}