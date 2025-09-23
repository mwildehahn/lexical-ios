/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow()
    guard let window else { return false }
    window.makeKeyAndVisible()

    // Create main editor tab
    let editorVC = ViewController()
    let editorNavController = UINavigationController(rootViewController: editorVC)
    editorNavController.tabBarItem = UITabBarItem(title: "Editor", image: UIImage(systemName: "doc.text"), tag: 0)

    // Create performance test tab
    let performanceVC = PerformanceTestViewController()
    let performanceNavController = UINavigationController(rootViewController: performanceVC)
    performanceNavController.tabBarItem = UITabBarItem(title: "Performance", image: UIImage(systemName: "speedometer"), tag: 1)

    // Create tab bar controller
    let tabBarController = UITabBarController()
    tabBarController.viewControllers = [editorNavController, performanceNavController]

    // Preselect the Performance tab
    tabBarController.selectedIndex = 1

    window.rootViewController = tabBarController
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    persistEditorState()
  }

  func persistEditorState() {
    guard let tabBarController = window?.rootViewController as? UITabBarController,
          let editorNavController = tabBarController.viewControllers?.first as? UINavigationController,
          let viewController = editorNavController.viewControllers.first as? ViewController else {
      return
    }

    viewController.persistEditorState()
  }
}
