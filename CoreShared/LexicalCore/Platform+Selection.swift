import Foundation
import UIKit

/// Snapshot of native selection state used for bridging platform frontends.
public struct UXSelectionSnapshot {
  public var range: NSRange
  public var affinity: UXTextStorageDirection
  public var markedRange: NSRange?
  public var markedAffinity: UXTextStorageDirection?
  public var opaque: Any?
  public var markedOpaque: Any?

  public init(range: NSRange,
              affinity: UXTextStorageDirection,
              markedRange: NSRange? = nil,
              markedAffinity: UXTextStorageDirection? = nil,
              opaque: Any? = nil,
              markedOpaque: Any? = nil) {
    self.range = range
    self.affinity = affinity
    self.markedRange = markedRange
    self.markedAffinity = markedAffinity
    self.opaque = opaque
    self.markedOpaque = markedOpaque
  }
}
