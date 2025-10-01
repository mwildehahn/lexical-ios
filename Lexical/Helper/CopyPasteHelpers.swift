/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(UIKit)
import UIKit
import MobileCoreServices
#elseif canImport(AppKit)
import AppKit
#endif

import UniformTypeIdentifiers

#if canImport(UIKit)
@MainActor
internal func setPasteboard(selection: BaseSelection, pasteboard: PlatformPasteboard) throws {
  guard let editor = getActiveEditor() else {
    throw LexicalError.invariantViolation("Could not get editor")
  }
  let nodes = try generateArrayFromSelectedNodes(editor: editor, selection: selection).nodes
  let text = try selection.getTextContent()
  let encodedData = try JSONEncoder().encode(nodes)
  guard let jsonString = String(data: encodedData, encoding: .utf8) else { return }

  let itemProvider = NSItemProvider()
  itemProvider.registerItem(forTypeIdentifier: LexicalConstants.pasteboardIdentifier) {
    completionHandler, expectedValueClass, options in
    let data = NSData(data: jsonString.data(using: .utf8) ?? Data())
    completionHandler?(data, nil)
  }

  if #available(iOS 14.0, *) {
    pasteboard.items =
      [
        [
          (UTType.rtf.identifier): try getAttributedStringFromFrontend().data(
            from: NSRange(location: 0, length: getAttributedStringFromFrontend().length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        ],
        [LexicalConstants.pasteboardIdentifier: encodedData],
      ]
    if ProcessInfo.processInfo.isMacCatalystApp {
      // added this to enable copy/paste in the mac catalyst app
      // the problem is in the TextView.canPerformAction
      // after copy on iOS pasteboard.hasStrings returns true but on Mac it returns false for some reason
      // setting this string here will make it return true, pasting will take serialized nodes from the pasteboard
      // anyhow so this should not have any adverse effect
      pasteboard.string = text
    }
  } else {
    pasteboard.items =
      [
        [
          (kUTTypeRTF as String): try getAttributedStringFromFrontend().data(
            from: NSRange(location: 0, length: getAttributedStringFromFrontend().length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        ],
        [LexicalConstants.pasteboardIdentifier: encodedData],
      ]
  }
}
#elseif canImport(AppKit)
@MainActor
internal func setPasteboard(selection: BaseSelection, pasteboard: PlatformPasteboard) throws {
  guard let editor = getActiveEditor() else {
    throw LexicalError.invariantViolation("Could not get editor")
  }
  let nodes = try generateArrayFromSelectedNodes(editor: editor, selection: selection).nodes
  let text = try selection.getTextContent()
  let encodedData = try JSONEncoder().encode(nodes)

  // Clear and set pasteboard data
  pasteboard.clearContents()

  // Set RTF data
  let attrString = try getAttributedStringFromFrontend()
  if let rtfData = try? attrString.data(
    from: NSRange(location: 0, length: attrString.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  {
    pasteboard.setData(rtfData, forType: .rtf)
  }

  // Set Lexical JSON data
  pasteboard.setData(encodedData, forType: NSPasteboard.PasteboardType(LexicalConstants.pasteboardIdentifier))

  // Set plain text
  pasteboard.setString(text, forType: .string)
}
#endif

#if canImport(UIKit)
@MainActor
internal func insertDataTransferForRichText(selection: RangeSelection, pasteboard: PlatformPasteboard)
  throws
{
  let itemSet: IndexSet?
  if #available(iOS 14.0, *) {
    itemSet = pasteboard.itemSet(
      withPasteboardTypes: [
        (UTType.utf8PlainText.identifier),
        (UTType.url.identifier),
        LexicalConstants.pasteboardIdentifier,
      ]
    )
  } else {
    itemSet = pasteboard.itemSet(
      withPasteboardTypes: [
        (kUTTypeUTF8PlainText as String),
        (kUTTypeURL as String),
        LexicalConstants.pasteboardIdentifier,
      ]
    )
  }

  if let pasteboardData = pasteboard.data(
    forPasteboardType: LexicalConstants.pasteboardIdentifier,
    inItemSet: itemSet)?.last
  {
    let deserializedNodes = try JSONDecoder().decode(SerializedNodeArray.self, from: pasteboardData)

    guard let editor = getActiveEditor() else { return }

    _ = try insertGeneratedNodes(
      editor: editor, nodes: deserializedNodes.nodeArray, selection: selection)
    return
  }

  if #available(iOS 14.0, *) {
    if let pasteboardRTFData = pasteboard.data(
      forPasteboardType: (UTType.rtf.identifier),
      inItemSet: itemSet)?.last
    {
      let attributedString = try NSAttributedString(
        data: pasteboardRTFData,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      )
      try insertRTF(selection: selection, attributedString: attributedString)
      return
    }
  } else {
    if let pasteboardRTFData = pasteboard.data(
      forPasteboardType: (kUTTypeRTF as String),
      inItemSet: itemSet)?.last
    {
      let attributedString = try NSAttributedString(
        data: pasteboardRTFData,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      )

      try insertRTF(selection: selection, attributedString: attributedString)
      return
    }
  }

  if #available(iOS 14.0, *) {
    if let pasteboardStringData = pasteboard.data(
      forPasteboardType: (UTType.utf8PlainText.identifier),
      inItemSet: itemSet)?.last
    {
      try insertPlainText(
        selection: selection, text: String(decoding: pasteboardStringData, as: UTF8.self))
      return
    }
  } else {
    if let pasteboardStringData = pasteboard.data(
      forPasteboardType: (kUTTypeUTF8PlainText as String),
      inItemSet: itemSet)?.last
    {
      try insertPlainText(
        selection: selection, text: String(decoding: pasteboardStringData, as: UTF8.self))
      return
    }
  }

  if let url = pasteboard.urls?.first as? URL {
    let string = url.absoluteString
    try insertPlainText(selection: selection, text: string)
    return
  }
}
#elseif canImport(AppKit)
@MainActor
internal func insertDataTransferForRichText(selection: RangeSelection, pasteboard: PlatformPasteboard)
  throws
{
  // Try Lexical format first
  if let pasteboardData = pasteboard.data(forType: NSPasteboard.PasteboardType(LexicalConstants.pasteboardIdentifier)) {
    let deserializedNodes = try JSONDecoder().decode(SerializedNodeArray.self, from: pasteboardData)
    guard let editor = getActiveEditor() else { return }
    _ = try insertGeneratedNodes(
      editor: editor, nodes: deserializedNodes.nodeArray, selection: selection)
    return
  }

  // Try RTF
  if let pasteboardRTFData = pasteboard.data(forType: .rtf) {
    let attributedString = try NSAttributedString(
      data: pasteboardRTFData,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    try insertRTF(selection: selection, attributedString: attributedString)
    return
  }

  // Try plain text
  if let pasteboardStringData = pasteboard.data(forType: .string),
     let string = String(data: pasteboardStringData, encoding: .utf8)
  {
    try insertPlainText(selection: selection, text: string)
    return
  }

  // Try URL
  if let urlString = pasteboard.string(forType: .URL), let url = URL(string: urlString) {
    try insertPlainText(selection: selection, text: url.absoluteString)
    return
  }
}
#endif

@MainActor
internal func insertPlainText(selection: RangeSelection, text: String) throws {
  var stringArray: [String] = []
  let range = text.startIndex..<text.endIndex
  text.enumerateSubstrings(in: range, options: .byParagraphs) { subString, _, _, _ in
    stringArray.append(subString ?? "")
  }

  if stringArray.count == 1 {
    try selection.insertText(text)
  } else {
    var nodes: [Node] = []
    var i = 0
    for part in stringArray {
      let textNode = createTextNode(text: String(part))
      if i != 0 {
        let paragraphNode = createParagraphNode()
        try paragraphNode.append([textNode])
        nodes.append(paragraphNode)
      } else {
        nodes.append(textNode)
      }
      i += 1
    }

    _ = try selection.insertNodes(nodes: nodes, selectStart: false)
  }
}

@MainActor
internal func insertRTF(selection: RangeSelection, attributedString: NSAttributedString) throws {
  let paragraphs = attributedString.splitByNewlines()

  var nodes: [Node] = []
  var i = 0

  for paragraph in paragraphs {
    var extractedAttributes = [(attributes: [NSAttributedString.Key: Any], range: NSRange)]()
    paragraph.enumerateAttributes(in: NSRange(location: 0, length: paragraph.length)) {
      (dict, range, stopEnumerating) in
      extractedAttributes.append((attributes: dict, range: range))
    }

    var nodeArray: [Node] = []
    for attribute in extractedAttributes {
      let text = paragraph.attributedSubstring(from: attribute.range).string
      let textNode = createTextNode(text: text)

      #if canImport(UIKit)
      if (attribute.attributes.first(where: { $0.key == .font })?.value as? PlatformFont)?
        .fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
      {
        textNode.format.bold = true
      }

      if (attribute.attributes.first(where: { $0.key == .font })?.value as? PlatformFont)?
        .fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
      {
        textNode.format.italic = true
      }
      #elseif canImport(AppKit)
      if (attribute.attributes.first(where: { $0.key == .font })?.value as? PlatformFont)?
        .fontDescriptor.symbolicTraits.contains(.bold) ?? false
      {
        textNode.format.bold = true
      }

      if (attribute.attributes.first(where: { $0.key == .font })?.value as? PlatformFont)?
        .fontDescriptor.symbolicTraits.contains(.italic) ?? false
      {
        textNode.format.italic = true
      }
      #endif

      if let underlineAttribute = attribute.attributes[.underlineStyle] {
        if underlineAttribute as? NSNumber != 0 {
          textNode.format.underline = true
        }
      }

      if let strikethroughAttribute = attribute.attributes[.strikethroughStyle] {
        if strikethroughAttribute as? NSNumber != 0 {
          textNode.format.strikethrough = true
        }
      }

      nodeArray.append(textNode)
    }

    if i != 0 {
      let paragraphNode = createParagraphNode()
      try paragraphNode.append(nodeArray)
      nodes.append(paragraphNode)
    } else {
      nodes.append(contentsOf: nodeArray)
    }
    i += 1
  }

  _ = try selection.insertNodes(nodes: nodes, selectStart: false)
}

@MainActor
public func insertGeneratedNodes(editor: Editor, nodes: [Node], selection: RangeSelection) throws {
  return try basicInsertStrategy(nodes: nodes, selection: selection)
}

@MainActor
func basicInsertStrategy(nodes: [Node], selection: RangeSelection) throws {
  var topLevelBlocks = [Node]()
  var currentBlock: ElementNode?
  for (index, _) in nodes.enumerated() {
    let node = nodes[index]
    if ((node as? ElementNode)?.isInline() ?? false) || isTextNode(node) || isLineBreakNode(node) {
      if let currentBlock {
        try currentBlock.append([node])
      } else {
        let paragraphNode = createParagraphNode()
        topLevelBlocks.append(paragraphNode)
        try paragraphNode.append([node])
        currentBlock = paragraphNode
      }
    } else {
      topLevelBlocks.append(node)
      currentBlock = nil
    }
  }

  _ = try selection.insertNodes(nodes: topLevelBlocks, selectStart: false)
}

@MainActor
func appendNodesToArray(
  editor: Editor,
  selection: BaseSelection?,
  currentNode: Node,
  targetArray: [Node] = []
) throws -> (shouldInclude: Bool, outArray: [Node]) {
  var array = targetArray
  var shouldInclude = selection != nil ? try currentNode.isSelected() : true
  let shouldExclude = (currentNode as? ElementNode)?.excludeFromCopy() ?? false
  var clone = try cloneWithProperties(node: currentNode)
  (clone as? ElementNode)?.children = []

  if let textClone = clone as? TextNode {
    if let selection {
      clone = try sliceSelectedTextNodeContent(selection: selection, textNode: textClone)
    }
  }

  guard let key = try generateKey(node: clone) else {
    throw LexicalError.invariantViolation("Could not generate key")
  }
  clone.key = key
  editor.getEditorState().nodeMap[key] = clone

  let children = (currentNode as? ElementNode)?.getChildren() ?? []
  var cloneChildren: [Node] = []

  for childNode in children {
    let internalCloneChildren: [Node] = []
    let shouldIncludeChild = try appendNodesToArray(
      editor: editor,
      selection: selection,
      currentNode: childNode,
      targetArray: internalCloneChildren
    )

    if !shouldInclude && shouldIncludeChild.shouldInclude
      && ((currentNode as? ElementNode)?.extractWithChild(
        child: childNode, selection: selection, destination: .clone) ?? false)
    {
      shouldInclude = true
    }

    cloneChildren.append(contentsOf: shouldIncludeChild.outArray)
  }

  for child in cloneChildren {
    (clone as? ElementNode)?.children.append(child.key)
  }

  if shouldInclude && !shouldExclude {
    array.append(clone)
  } else if let children = (clone as? ElementNode)?.children {
    for childKey in children {
      if let childNode = editor.getEditorState().nodeMap[childKey] {
        array.append(childNode)
      }
    }
  }

  return (shouldInclude, array)
}

@MainActor
public func generateArrayFromSelectedNodes(editor: Editor, selection: BaseSelection?) throws -> (
  namespace: String,
  nodes: [Node]
) {
  var nodes: [Node] = []
  guard let root = getRoot() else {
    return ("", [])
  }
  for topLevelNode in root.getChildren() {
    var nodeArray: [Node] = []
    nodeArray = try appendNodesToArray(
      editor: editor, selection: selection, currentNode: topLevelNode, targetArray: nodeArray
    ).outArray
    nodes.append(contentsOf: nodeArray)
  }
  return (
    namespace: "lexical",
    nodes
  )
}

// MARK: Extensions

extension NSAttributedString {
  public func splitByNewlines() -> [NSAttributedString] {
    var result = [NSAttributedString]()
    var rangeArray: [NSRange] = []

    (string as NSString).enumerateSubstrings(
      in: NSRange(location: 0, length: (string as NSString).length),
      options: .byParagraphs
    ) { subString, subStringRange, enclosingRange, stop in
      rangeArray.append(subStringRange)
    }

    for range in rangeArray {
      let attributedString = attributedSubstring(from: range)
      result.append(attributedString)
    }
    return result
  }
}
