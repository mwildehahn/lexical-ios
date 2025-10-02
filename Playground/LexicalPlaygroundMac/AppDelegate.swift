//
//  AppDelegate.swift
//  LexicalPlaygroundMac
//
//  Created by Vedran Burojevic on 02.10.2025..
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog("LexicalPlaygroundMac: applicationDidFinishLaunching")
    DispatchQueue.main.async {
      let desiredFrame = NSRect(x: 200, y: 200, width: 1200, height: 800)
      if let window = NSApp.windows.first {
        window.setFrame(desiredFrame, display: true)
        window.minSize = NSSize(width: 800, height: 600)
      }
      NSLog("LexicalPlaygroundMac: activating app")
      NSApp.activate(ignoringOtherApps: true)
      NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

