import UIKit

/// Platform abstraction shims for UIKit-backed builds.
///
/// These aliases allow downstream code to reference `UX*` types that will
/// eventually map to AppKit equivalents once macOS support is enabled.
public typealias UXColor = UIColor
public typealias UXFont = UIFont
public typealias UXImage = UIImage
public typealias UXEdgeInsets = UIEdgeInsets
public typealias UXView = UIView
public typealias UXPasteboard = UIPasteboard

public typealias UXTextStorageDirection = UITextStorageDirection
public typealias UXTextGranularity = UITextGranularity
