/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

@available(iOS 13.0, *)
@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = UIWindow(windowScene: windowScene)

    // Build the same tab structure as AppDelegate used to do
    let editorVC = ViewController()
    let editorNavController = UINavigationController(rootViewController: editorVC)
    editorNavController.tabBarItem = UITabBarItem(title: "Editor", image: UIImage(systemName: "doc.text"), tag: 0)

    let performanceVC = PerformanceTestViewController()
    let performanceNavController = UINavigationController(rootViewController: performanceVC)
    performanceNavController.tabBarItem = UITabBarItem(title: "Performance", image: UIImage(systemName: "speedometer"), tag: 1)

    let compareVC = CompareViewController()
    let compareNavController = UINavigationController(rootViewController: compareVC)
    compareNavController.tabBarItem = UITabBarItem(title: "Compare", image: UIImage(systemName: "square.split.2x1"), tag: 2)

    let tabBarController = UITabBarController()
    tabBarController.viewControllers = [editorNavController, performanceNavController, compareNavController]
    tabBarController.selectedIndex = 2 // default to Compare tab

    window.rootViewController = tabBarController
    self.window = window
    window.makeKeyAndVisible()
  }
}
