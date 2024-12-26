import Foundation
import Lexical
import Automerge

open class LexicalAutomergePlugin: Plugin {
  
  var editor: Editor?
  
  // automerge documents
  var client1Document: Document?
  var client2Document: Document?
  var serverDocument: Document?
  var activeClientDocument: Document?
  
  var lexical2Automerge1: Lexical2Automerge?
  
  var client1EditorState: EditorState?
  var client2EditorState: EditorState?
  
  private var changeTracker: NodeChangeTracker?
  
  private var timer: Timer?
  
  public init() {
    self.client1Document = Document()

    
//    self.serverDocument = client1Document.fork()
//    self.client2Document = self.serverDocument.fork()
//    self.activeClientDocument = client1Document
        
  }

  public func setUp(editor: Editor) {
    self.editor = editor

    // DirtyNodeMap
    // public typealias DirtyNodeMap = [NodeKey: DirtyStatusCause]
//    public enum DirtyStatusCause {
//      case userInitiated
//      case editorInitiated
//    }
    
    self.changeTracker = NodeChangeTracker(editor: editor)
    
    let _ = editor.registerUpdateListener { [weak self] activeEditorState, previousEditorState, dirtyNodes in
      
      if let plugin = self {
        if plugin.lexical2Automerge1 == nil {
          plugin.lexical2Automerge1 = Lexical2Automerge(document: plugin.client1Document!, rootNode: activeEditorState.getRootNode()!)
        }
        let changes = plugin.changeTracker?.trackChanges(dirtyNodesAndCauses: dirtyNodes)
                    
        // Handle the changes
        self?.handleChanges(changes)
      }
      
      let changes = self?.changeTracker?.trackChanges(dirtyNodesAndCauses: dirtyNodes)
                  
      // Handle the changes
      self?.handleChanges(changes)
      
      //self?.updateAutomergeDocument(with: activeEditorState)
    }
    
    // Schedule a timer to run every 3 seconds
//    timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
//        self?.task()
//    }
  }
  
  private func handleChanges(_ changes: NodeChanges?) {
    
    guard let changes = changes else { return }
    
      if !changes.added.isEmpty {
          print("Added nodes:", changes.added)
          for nodeKey in changes.added {
              if let node = getNodeByKey(key: nodeKey) {
              lexical2Automerge1?.nodeAdded(node)
            }
          }
      }
      
      if !changes.removed.isEmpty {
          print("Removed nodes:", changes.removed)
          for nodeKey in changes.removed {
              if let node = getNodeByKey(key: nodeKey) {
                lexical2Automerge1?.nodeRemoved(node)
                // TODO this node no longer exists
                // node removed needs to accept only a node key
            }
          }
      }
      
      if !changes.updated.isEmpty {
          print("Updated nodes:", changes.updated)
          for nodeKey in changes.updated {
              if let node = getNodeByKey(key: nodeKey) {
                lexical2Automerge1?.nodeUpdated(node)
            }
          }
      }
    
    print("______________________")
      
//      // You can also get node details
//      do {
//          try editor.read {
//              for nodeKey in changes.updated {
//                  if let node = getNodeByKey(key: nodeKey) {
//                      print("Node details:", node)
//                  }
//              }
//          }
//      } catch {
//          print("Error reading node details:", error)
//      }
  }
  
  private func updateAutomergeDocument(with editorState: EditorState) {
//    do {
//      // convert lexical editor state to automerge document
//      // we are currently supporting only plain text paragraphs
//      guard let rootNode = editorState.getRootNode() else { return }
//      let rootChildren = rootNode.getChildren()
//      
//      
//      
//      let jsonState = try editorState.toJSON()
//      let editorObjId: ObjId
//      switch try! document!.get(obj: ObjId.ROOT, key: "editor")! {
//          case .Object(let id, _):
//            editorObjId = id
//          default:
//            fatalError("contacts was not a list")
//          }
//      
//      try document!.updateText(obj: editorObjId, value: jsonState)
//      print("Successfully updated Automerge document")
//    } catch {
//      print("Error updating Automerge document:", error)
//    }
  }
  
  private func task() {
//    let editorObjId: ObjId
//    switch try! document!.get(obj: ObjId.ROOT, key: "editor")! {
//        case .Object(let id, _):
//          editorObjId = id
//        default:
//          fatalError("contacts was not a list")
//        }
//    if let jsonText = try? document!.text(obj: editorObjId) {
//      var jsonText = jsonText
//      if let firstRangeOf = jsonText.range(of: "aa") {
//        jsonText.replaceSubrange(firstRangeOf, with: "aaaa")
//      }
//      
//      let selection = editor?.getEditorState().selection as? RangeSelection
//      
//      let newState = try! EditorState.fromJSON(json: jsonText, editor: editor!)
//      try! editor?.setEditorState(newState)
      
//      if let selection = selection {
        try! editor?.update {
          guard let rootNode = getRoot() else { return }
          let paragraphNode = createParagraphNode()
          let textNode = TextNode(text: "test")
          try! paragraphNode.append([textNode])
          try! rootNode.getFirstChild()?.insertBefore(nodeToInsert: paragraphNode)
//          let node = getNodeByKey(key: selection.anchor.key) as? TextNode
//          try! node?.select(anchorOffset: selection.anchor.offset, focusOffset: selection.focus.offset)
        }
//      }
    //}
    
  }

  public func tearDown() {
  }
      
}

struct NodeChanges {
    var added: Set<NodeKey>
    var removed: Set<NodeKey>
    var updated: Set<NodeKey>
}

class NodeChangeTracker {
    private var previousNodes: Set<NodeKey>
    private let editor: Editor
    
    init(editor: Editor) {
        self.editor = editor
        self.previousNodes = Set()
        setupInitialState()
    }
    
    private func setupInitialState() {
        // Capture initial state of nodes
        do {
            try editor.read {
                self.previousNodes = try! getAllNodeKeys()
            }
        } catch {
            print("Error setting up initial state:", error)
        }
    }
    
    func trackChanges(dirtyNodesAndCauses: [NodeKey: DirtyStatusCause]) -> NodeChanges {
      
      let dirtyNodes = Set(dirtyNodesAndCauses.keys)
      
        var changes = NodeChanges(added: Set(), removed: Set(), updated: Set())
        
        do {
            try editor.read {
                // Get current set of all nodes
                let currentNodes = try! getAllNodeKeys()
                
                // Find added nodes (in current but not in previous)
                changes.added = currentNodes.subtracting(previousNodes)
                
                // Find removed nodes (in previous but not in current)
                changes.removed = previousNodes.subtracting(currentNodes)
                
                // Find updated nodes (dirty nodes that weren't added or removed)
                changes.updated = dirtyNodes
                    .subtracting(changes.added)
                    .subtracting(changes.removed)
                
                // Update previous nodes for next comparison
                previousNodes = currentNodes
            }
        } catch {
            print("Error tracking changes:", error)
        }
        
        return changes
    }
    
    private func getAllNodeKeys() throws -> Set<NodeKey> {
        var nodeKeys = Set<NodeKey>()
        
        guard let rootNode = getRoot() else {
            return nodeKeys
        }
        
        // Traverse the node tree and collect all keys
        try traverseNodes(node: rootNode) { node in
            nodeKeys.insert(node.key)
        }
        
        return nodeKeys
    }
    
    private func traverseNodes(node: Node, action: (Node) throws -> Void) throws {
        try action(node)
        
        if let element = node as? ElementNode {
          for child in element.getChildren() {
            if let childNode = getNodeByKey(key: child.getKey()) {
                    try traverseNodes(node: childNode, action: action)
                }
            }
        }
    }
}

extension Document {
    /// Prints the contents of the Automerge document in a readable format
    /// - Parameter indentLevel: The initial indentation level (default is 0)
    public func printContents(indentLevel: Int = 0) {
        do {
            // Start with the root object
            printObject(ObjId.ROOT, indent: indentLevel)
        } catch {
            print("Error printing document contents:", error)
        }
    }
    
    private func printObject(_ objId: ObjId, indent: Int) {
        do {
            let objType = objectType(obj: objId)
            let indentation = String(repeating: "  ", count: indent)
            
            switch objType {
            case .Map:
              print("\(indentation)Map (\(objId.debugDescription)) {")
                // Print all key-value pairs in the map
                for key in keys(obj: objId) {
                    if let value = try get(obj: objId, key: key) {
                        printValue(key: key, value: value, indent: indent + 1)
                    }
                }
                print("\(indentation)}")
                
            case .List:
                print("\(indentation)List (\(objId.debugDescription)) [")
                // Print all items in the list
                let values = try values(obj: objId)
                for (index, value) in values.enumerated() {
                    print("\(indentation)  [\(index)]:", terminator: " ")
                    printValue(value: value, indent: indent + 1)
                }
                print("\(indentation)]")
                
            case .Text:
                let text = try text(obj: objId)
              print("\(indentation)Text (\(objId.debugDescription)): \"\(text)\"")
                // Optionally print marks if they exist
                if let marks = try? marks(obj: objId), !marks.isEmpty {
                    print("\(indentation)Marks: {")
                    for mark in marks {
                        print("\(indentation)  \(mark)")
                    }
                    print("\(indentation)}")
                }
            }
        } catch {
            print("Error printing object:", error)
        }
    }
    
    private func printValue(key: String? = nil, value: Value, indent: Int) {
        let indentation = String(repeating: "  ", count: indent)
        let keyPrefix = key.map { "\($0): " } ?? ""
        
        switch value {
        case .Object(let objId, let objType):
            if let key = key {
                print("\(indentation)\(key):")
            }
            printObject(objId, indent: indent + (key != nil ? 1 : 0))
            
        case .Scalar(let scalar):
            print("\(indentation)\(keyPrefix)\(formatScalar(scalar))")
        }
    }
    
    private func formatScalar(_ scalar: ScalarValue) -> String {
        switch scalar {
        case .Null:
            return "null"
        case .Boolean(let bool):
            return bool ? "true" : "false"
        case .String(let str):
            return "\"\(str)\""
        case .Int(let num):
            return "\(num)"
        case .Uint(let num):
            return "\(num)"
        case .F64(let num):
            return "\(num)"
        case .Counter(let count):
            return "Counter(\(count))"
        case .Timestamp(let time):
            return "Timestamp(\(time))"
        case .Unknown:
            return "Unknown"
        default:
            return "default"
        }
    }
}
