/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import Foundation
import Lexical
import SelectableDecoratorNode
import UIKit

extension NodeType {
  static let selectableImage = NodeType(rawValue: "selectableImage")
}

public class SelectableImageNode: SelectableDecoratorNode {
  var url: URL?
  var size = CGSize.zero
  var sourceID: String = ""

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

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)
  }

  override public class func getType() -> NodeType {
    return .selectableImage
  }

  override public func clone() -> Self {
    Self(url: url?.absoluteString ?? "", size: size, sourceID: sourceID, key: key)
  }

  override public func createContentView() -> UIImageView {
    let imageView = createImageView()
    loadImage(imageView: imageView)
    return imageView
  }

  override open func decorateContentView(view: UIView, wrapper: SelectableDecoratorView) {
    if let view = view as? UIImageView {
      loadImage(imageView: view)
    }
  }

  public func getURL() -> String? {
    let latest = getLatest()
    return latest.url?.absoluteString
  }

  public func setURL(_ url: String) throws {
    try errorOnReadOnly()

    try getWritable().url = URL(string: url)
  }

  public func getSourceID() -> String? {
    let latest = getLatest()
    return latest.sourceID
  }

  public func setSourceID(_ sourceID: String) throws {
    try errorOnReadOnly()

    try getWritable().sourceID = sourceID
  }

  private func createImageView() -> UIImageView {
    let view = UIImageView(frame: CGRect(origin: CGPoint.zero, size: size))
    view.isUserInteractionEnabled = true

    view.backgroundColor = .lightGray

    return view
  }

  private func loadImage(imageView: UIImageView) {
    guard let url else { return }

    URLSession.shared.dataTask(with: url) { (data, response, error) in
      if error != nil {
        return
      }

      guard let data else {
        return
      }

      DispatchQueue.main.async {
        imageView.image = UIImage(data: data)
      }
    }.resume()
  }

  let maxImageHeight: CGFloat = 600.0

  override open func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGSize {

    if size.width <= textViewWidth {
      return size
    }
    return AVMakeRect(aspectRatio: size, insideRect: CGRect(x: 0, y: 0, width: textViewWidth, height: maxImageHeight)).size
  }
}
