import Foundation
import UniformTypeIdentifiers

/// Shared pasteboard helper values for platform-neutral code.
public enum UXPasteboardContentType {
  /// Plain text (UTF-8) content identifier.
  public static let plainTextIdentifier = UTType.plainText.identifier

  /// Rich Text Format content identifier.
  public static let richTextIdentifier = UTType.rtf.identifier

  /// Plain text UTType reference.
  public static let plainText = UTType.plainText

  /// Rich text UTType reference.
  public static let richText = UTType.rtf
}
