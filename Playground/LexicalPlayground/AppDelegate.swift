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
    let editorVC = ViewController()
    editorVC.tabBarItem = UITabBarItem(title: "Editor", image: UIImage(systemName: "doc.text"), selectedImage: UIImage(systemName: "doc.text.fill"))
    let perfVC = PerformanceViewController()
    perfVC.tabBarItem = UITabBarItem(title: "Perf", image: UIImage(systemName: "speedometer"), selectedImage: UIImage(systemName: "speedometer"))

    let editorNav = UINavigationController(rootViewController: editorVC)
    let perfNav = UINavigationController(rootViewController: perfVC)

    let tab = UITabBarController()
    tab.viewControllers = [editorNav, perfNav]
    window.rootViewController = tab
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    persistEditorState()
  }

  func persistEditorState() {
    // Try to persist from the editor tab if present
    if let tab = window?.rootViewController as? UITabBarController,
       let nav = tab.viewControllers?.first as? UINavigationController,
       let editorVC = nav.viewControllers.first as? ViewController {
      editorVC.persistEditorState()
    }
  }
}
