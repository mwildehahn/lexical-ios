/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - TextFormat

/// Represents text formatting options like bold, italic, etc.
public struct TextFormat: Equatable, Codable, Hashable, Sendable {

  public var bold: Bool
  public var italic: Bool
  public var underline: Bool
  public var strikethrough: Bool
  public var code: Bool
  public var subScript: Bool
  public var superScript: Bool

  public init() {
    self.bold = false
    self.italic = false
    self.underline = false
    self.strikethrough = false
    self.code = false
    self.subScript = false
    self.superScript = false
  }

  public init(
    bold: Bool = false,
    italic: Bool = false,
    underline: Bool = false,
    strikethrough: Bool = false,
    code: Bool = false,
    subScript: Bool = false,
    superScript: Bool = false
  ) {
    self.bold = bold
    self.italic = italic
    self.underline = underline
    self.strikethrough = strikethrough
    self.code = code
    self.subScript = subScript
    self.superScript = superScript
  }

  public func isTypeSet(type: TextFormatType) -> Bool {
    switch type {
    case .bold:
      return bold
    case .italic:
      return italic
    case .underline:
      return underline
    case .strikethrough:
      return strikethrough
    case .code:
      return code
    case .subScript:
      return subScript
    case .superScript:
      return superScript
    }
  }

  public mutating func updateFormat(type: TextFormatType, value: Bool) {
    switch type {
    case .bold:
      bold = value
    case .italic:
      italic = value
    case .underline:
      underline = value
    case .strikethrough:
      strikethrough = value
    case .code:
      code = value
    case .subScript:
      subScript = value
    case .superScript:
      superScript = value
    }
  }
}

extension TextFormat: CustomDebugStringConvertible {
  public var debugDescription: String {
    var parts: [String] = []
    if bold { parts.append("bold") }
    if italic { parts.append("italic") }
    if underline { parts.append("underline") }
    if strikethrough { parts.append("strikethrough") }
    if code { parts.append("code") }
    if subScript { parts.append("subScript") }
    if superScript { parts.append("superScript") }
    return parts.joined(separator: ", ")
  }
}
