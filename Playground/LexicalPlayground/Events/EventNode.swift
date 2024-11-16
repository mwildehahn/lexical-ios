//
//  EventNode.swift
//  LexicalPlayground
//
//  Created by Nemanja Kovacevic on 15.11.24..
//

import Foundation
import Lexical
import UIKit

extension NodeType {
  static let event = NodeType(rawValue: "event")
}

public class EventNode: DecoratorNode {
  
  private var event: Event?

  override public class func getType() -> NodeType {
    return .event
  }

  public required init(event: Event?, key: NodeKey? = nil) {
    super.init(key)
    self.event = event
  }

  required init(_ key: NodeKey? = nil) {
    super.init(key)
  }

  override public func clone() -> Self {
    Self(event: event, key: key)
  }

  override public func createView() -> UIView {
    let view = FullWidthNodeView(title: event?.title ?? "")
    return view
  }
  
  override open func decorate(view: UIView) {
    // no-op
  }

  override open func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGSize {
    
    let fullWidthSize = CGSize(width: textViewWidth, height: 100)
    return fullWidthSize
  }
  
  // MARK: - Getters and setters
  
  public func getEvent() -> Event? {
    let latest: EventNode = getLatest()
    return latest.event
  }

  public func setEvent(_ event: Event) throws {
    try errorOnReadOnly()
    try getWritable().event = event
  }
  
  // MARK: - Serialization

  enum CodingKeys: String, CodingKey {
    case event
  }

  public required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try super.init(from: decoder)

    self.event = try container.decode(Event.self, forKey: .event)
  }

  override open func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.event, forKey: .event)
  }
  
  // todo do we need this?
  func canInsertTextAfter() -> Bool {
    return false
  }
  
}

class FullWidthNodeView: UIView {

  init(title: String) {
    super.init(frame: .zero)
    setupView(text: title)
  }
    
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView(text: "")
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView(text: "")
  }
  
  private func setupView(text: String) {
    self.backgroundColor = .blue
    self.layer.cornerRadius = 8
    
    let label = UILabel()
    label.text = text
    label.textAlignment = .center
    label.textColor = .white
    label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    
    self.addSubview(label)
    
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
        label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8)
    ])
  }

  override func layoutSubviews() {
      super.layoutSubviews()
      guard let superview = superview else { return }
      self.frame = CGRect(x: 0, y: self.frame.origin.y, width: superview.frame.width, height: 60)
  }
  
}

