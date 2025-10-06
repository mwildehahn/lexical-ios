import Foundation

#if canImport(UIKit)
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
#elseif canImport(AppKit)
import AppKit

public enum UXPasteboardContentType {
  public static let plainTextIdentifier = NSPasteboard.PasteboardType.string.rawValue
  public static let richTextIdentifier = NSPasteboard.PasteboardType.rtf.rawValue
  public static let plainText = NSPasteboard.PasteboardType.string
  public static let richText = NSPasteboard.PasteboardType.rtf
}
#endif
