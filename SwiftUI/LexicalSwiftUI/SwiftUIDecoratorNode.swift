#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import Lexical

@available(iOS 17.0, *)
@MainActor
public final class SwiftUIDecoratorNode<Content: View>: DecoratorNode {
  private let content: Content
  private var hostingController: UIHostingController<Content>?

  public init(content: Content, key: NodeKey? = nil) {
    self.content = content
    super.init(key)
  }

  public required init(_ key: NodeKey?) {
    fatalError("init(_:) has not been implemented; use init(content:key:)")
  }

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    fatalError("Decoding is not supported for SwiftUIDecoratorNode stubs yet")
  }

  public override func clone() -> Self {
    SwiftUIDecoratorNode(content: content, key: key) as! Self
  }

  public override func createView() -> UXView {
    let controller = UIHostingController(rootView: content)
    hostingController = controller
    controller.view.backgroundColor = .clear
    return controller.view
  }

  public override func decorate(view: UXView) {
    hostingController?.rootView = content
  }
}
#endif
