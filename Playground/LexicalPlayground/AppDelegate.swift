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
    let testHub = TestHubViewController()
    let navigationController = UINavigationController(rootViewController: testHub)
    window.rootViewController = navigationController
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    persistEditorState()
  }

  func persistEditorState() {
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      return
    }

    if let editorController = navigationController.topViewController as? ViewController {
      editorController.persistEditorState()
    }
  }
}
