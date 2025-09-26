/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)

    let editorVC = ViewController()
    editorVC.tabBarItem = UITabBarItem(title: "Editor", image: UIImage(systemName: "doc.text"), selectedImage: UIImage(systemName: "doc.text.fill"))
    let perfVC = PerformanceViewController()
    perfVC.tabBarItem = UITabBarItem(title: "Perf", image: UIImage(systemName: "speedometer"), selectedImage: UIImage(systemName: "speedometer"))

    let editorNav = UINavigationController(rootViewController: editorVC)
    let perfNav = UINavigationController(rootViewController: perfVC)

    let tab = UITabBarController()
    tab.viewControllers = [editorNav, perfNav]

    window.rootViewController = tab
    self.window = window
    window.makeKeyAndVisible()
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    persistEditorState()
  }

  private func persistEditorState() {
    if let tab = window?.rootViewController as? UITabBarController,
       let nav = tab.viewControllers?.first as? UINavigationController,
       let editorVC = nav.viewControllers.first as? ViewController {
      editorVC.persistEditorState()
    }
  }
}
