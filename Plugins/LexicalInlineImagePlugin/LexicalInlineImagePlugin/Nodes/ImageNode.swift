/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import Foundation
import Lexical
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension NodeType {
  static let image = NodeType(rawValue: "image")
}

@MainActor
protocol ImageNodeVisitor {
  func visitImageNode(_ node: ImageNode) throws
}

extension CommandType {
  public static let imageTap = CommandType(rawValue: "imageTap")
}

public class ImageNode: DecoratorNode {
  var url: URL?
  var size = CGSize.zero
  var sourceID: String = ""

  override public class func getType() -> NodeType {
    return .image
  }

  public required init(url: String, size: CGSize, sourceID: String, key: NodeKey? = nil) {
    super.init(key)

    self.url = URL(string: url)
    self.size = size
    self.sourceID = sourceID
  }

  required init(_ key: NodeKey? = nil) {
    super.init(key)
  }

  public required convenience init(from decoder: Decoder) throws {
    try self.init(from: decoder, depth: nil, index: nil)
  }

  public required init(
    from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil
  ) throws {
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)
    // Decode custom properties if present
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let urlString = try container.decodeIfPresent(String.self, forKey: .url) {
      self.url = URL(string: urlString)
    }
    if let w = try container.decodeIfPresent(CGFloat.self, forKey: .w),
       let h = try container.decodeIfPresent(CGFloat.self, forKey: .h) {
      self.size = CGSize(width: w, height: h)
    }
    self.sourceID = (try container.decodeIfPresent(String.self, forKey: .sourceID)) ?? ""
  }

  public override func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    if let url { try container.encode(url.absoluteString, forKey: .url) }
    try container.encode(size.width, forKey: .w)
    try container.encode(size.height, forKey: .h)
    try container.encode(sourceID, forKey: .sourceID)
  }

  private enum CodingKeys: String, CodingKey {
    case url
    case w
    case h
    case sourceID
  }

  override public func clone() -> Self {
    Self(url: url?.absoluteString ?? "", size: size, sourceID: sourceID, key: key)
  }

  override public func createView() -> PlatformImageView {
    editorForTapHandling = getActiveEditor()
    let imageView = createImageView()
    loadImage(imageView: imageView)
    return imageView
  }

  override open func decorate(view: PlatformView) {
    if let view = view as? PlatformImageView {
      for gr in view.gestureRecognizers ?? [] {
        view.removeGestureRecognizer(gr)
      }
      let gestureRecognizer = PlatformTapGestureRecognizer(
        target: self, action: #selector(handleTap(gestureRecognizer:)))
      view.addGestureRecognizer(gestureRecognizer)
      loadImage(imageView: view)
    }
  }

  public func getURL() -> String? {
    let latest: ImageNode = getLatest()

    return latest.url?.absoluteString
  }

  public func setURL(_ url: String) throws {
    try errorOnReadOnly()

    try getWritable().url = URL(string: url)
  }

  public func getSourceID() -> String? {
    let latest: ImageNode = getLatest()

    return latest.sourceID
  }

  public func setSourceID(_ sourceID: String) throws {
    try errorOnReadOnly()

    try getWritable().sourceID = sourceID
  }

  private func createImageView() -> PlatformImageView {
    let view = PlatformImageView(frame: CGRect(origin: CGPoint.zero, size: size))
    #if canImport(UIKit)
    view.isUserInteractionEnabled = true
    view.backgroundColor = .lightGray
    #elseif canImport(AppKit)
    view.wantsLayer = true
    view.layer?.backgroundColor = PlatformColor.lightGray.cgColor
    #endif

    return view
  }

  private weak var editorForTapHandling: Editor?
  @objc internal func handleTap(gestureRecognizer: PlatformTapGestureRecognizer) {
    guard let editorForTapHandling else { return }
    do {
      try editorForTapHandling.update {
        editorForTapHandling.dispatchCommand(type: .imageTap, payload: getSourceID())
      }
    } catch {
      editorForTapHandling.log(.node, .error, "Error thrown in tap handler, \(error)")
    }
  }

  private func loadImage(imageView: PlatformImageView) {
    guard let url else { return }

    URLSession.shared.dataTask(with: url) { (data, response, error) in
      if error != nil {
        return
      }

      guard let data else {
        return
      }

      DispatchQueue.main.async {
        imageView.image = PlatformImage(data: data)
      }
    }.resume()
  }

  let maxImageHeight: CGFloat = 600.0

  override open func sizeForDecoratorView(
    textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]
  ) -> CGSize {

    if size.width <= textViewWidth {
      return size
    }
    return AVMakeRect(
      aspectRatio: size,
      insideRect: CGRect(x: 0, y: 0, width: textViewWidth, height: maxImageHeight)
    ).size
  }

  open override func accept<V>(visitor: V) throws where V: NodeVisitor {
    if let visitor = visitor as? ImageNodeVisitor {
      try visitor.visitImageNode(self)
    }
  }
}
