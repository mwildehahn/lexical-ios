//
//  Lexical2Automerge.swift
//  LexicalPlayground
//
//  Created by Nemanja Kovacevic on 26.12.24..
//
import Lexical
import Automerge

/// Responsibility of this class is updating the automerge document based on lexical nodes being marked dirty
class Lexical2Automerge {

  let document: Document
  var mapping: [NodeKey: ObjId] = [:]
  
  init(document: Document, rootNode: RootNode) {
    self.document = document
    let rootObjId = try! document.putObject(obj: ObjId.ROOT, key: "root", ty: .Map)
    try! document.putObject(obj: rootObjId, key: "children", ty: .List)
    mapping[rootNode.getKey()] = rootObjId
  }
  
  // automerge document object can only be three things: .Map, .List and .Text
  // in order to represent a lexical node in one of these objects we need to model it according to this
  // every lexical element node would be an automerge .Map object consisting of json representation of the node properties
  // without its children and a list of objects representing its children nodes, if it has any
  public func nodeAdded(_ node: Node) {
    // this node was added, we need to find the right place in am document to insert it into
    if let previousSibling = node.getPreviousSibling() {
      // there is a previous sibling
      // do we have it in the mapping
      if let previousSiblingObjId = mapping[previousSibling.getKey()] {
        // we do - cool, then just insert this node after the previous sibling one in automerge document
        if let parent = node.getParent() {
          if let parentObjId = mapping[parent.getKey()] {
            if let childrenObjId = getChildrenObjId(of: parentObjId) {
              var previousSiblingIndex: Int? = nil
              let values = try! document.values(obj: childrenObjId)
              for (index, value) in values.enumerated() {
                switch value {
                case .Object(let childObjId, .Map):
                  if childObjId == previousSiblingObjId {
                    previousSiblingIndex = index
                    break
                  }
                default:
                  print("Invalid initial state")
                }
              }
              if let previousSiblingIndex = previousSiblingIndex {
                insertNodeIntoAutomergeDocument(node, childrenObjId: childrenObjId, index: UInt64(previousSiblingIndex + 1))
              } else {
                print("Previous sibling index not found")
              }
            } else {
              print("Could not obtain children obj id")
            }
          } else {
            print("Parent is not mapped")
          }
        } else {
          print("Node has no parent")
        }
      } else {
        // we do not, previous sibling is also being added but it's coming after this one perhaps, warn for now
        print("Previous sibling is not mapped")
      }
    } else {
      // there is no previous sibling, this node is either inserted on the begining of the parent or its first node to be inserted
      // either way we want to insert it in the begining of the parent
      if let parent = node.getParent() {
        if let parentObjId = mapping[parent.getKey()] {
          if let childrenObjId = getChildrenObjId(of: parentObjId) {
            insertNodeIntoAutomergeDocument(node, childrenObjId: childrenObjId, index: 0)
          } else {
            print("Could not obtain children obj id")
          }
        } else {
          print("Parent is not mapped")
        }
      } else { // there is no parent, perhaps it's also being added but comes after this node in the update
        // TODO we should mend the NodeChangeTracker to gives us topmost nodes first if possible
        // just warn
        print("There is no parent")
      }
    }
    print("nodeAdded called for \(node.getKey())")
    document.printContents()
  }
  
  public func nodeRemoved(_ node: Node) {
    if let nodeObjId = mapping[node.getKey()] {
      if let parent = node.getParent() {
        if let parentObjId = mapping[parent.getKey()] {
          if let childrenObjId = getChildrenObjId(of: parentObjId) {
            var nodeIndex: Int? = nil
            let values = try! document.values(obj: childrenObjId)
            for (index, value) in values.enumerated() {
              switch value {
              case .Object(let childObjId, .Map):
                if childObjId == nodeObjId {
                  nodeIndex = index
                  break
                }
              default:
                print("List item is not an automerge object")
              }
            }
            if let nodeIndex = nodeIndex {
              try! document.delete(obj: childrenObjId, index: UInt64(nodeIndex))
            } else {
              print("Previous sibling index not found")
            }
          } else {
            print("Could not obtain children obj id")
          }
        } else {
          print("Parent is not mapped")
        }
      } else {
        print("There is no parent")
      }
    } else {
      print("Node is not mapped")
    }
    print("nodeRemoved called for \(node.getKey())")
    document.printContents()
  }
  
  // we will suport just updating TextNode text for now
  public func nodeUpdated(_ node: Node) {
    if let textNode = node as? TextNode {
      if let nodeObjId = mapping[node.getKey()] {
        if let textValueObjId = getTextValueObjId(of: nodeObjId) {
          try! document.updateText(obj: textValueObjId, value: textNode.getTextPart())
        } else {
          print("Text value is not mapped")
        }
      } else {
        print("Node is not mapped")
      }
    } else {
      print("we do not support \(node.type) yet")
    }
    // print("nodeUpdated called for \(node.getKey())")
    // document.printContents()
  }
  
  private func getChildrenObjId(of objId: ObjId) -> ObjId? {
    let value = try! document.get(obj: objId, key: "children")!
    switch value {
      case .Object(let childrenObjId, .List):
        return childrenObjId
      default:
        return nil
      }
  }
  
  private func getTextValueObjId(of objId: ObjId) -> ObjId? {
    let value = try! document.get(obj: objId, key: "text")!
    switch value {
    case .Object(let textValueObjId, .Text):
      return textValueObjId
      default:
        return nil
      }
  }
  
  private func insertNodeIntoAutomergeDocument(_ node: Node, childrenObjId: ObjId, index: UInt64) {
    let nodeObjId = try! document.insertObject(obj: childrenObjId, index: index, ty: .Map)
    mapping[node.getKey()] = nodeObjId
    if let elementNode = node as? ElementNode {
      if let paragraphNode = node as? ParagraphNode {
        try! document.put(obj: nodeObjId, key: "type", value: ScalarValue.String("ParagraphNode"))
        try! document.putObject(obj: nodeObjId, key: "children", ty: .List)
      } else {
        print("we do not support \(node.type) yet")
      }
    } else {
      if let textNode = node as? TextNode {
        try! document.put(obj: nodeObjId, key: "type", value: ScalarValue.String("TextNode"))
        let textObjId = try! document.putObject(obj: nodeObjId, key: "text", ty: .Text)
        try! document.updateText(obj: textObjId, value: textNode.getTextPart())
      } else {
        print("we do not support \(node.type) yet")
      }
    }
  }
  
}
