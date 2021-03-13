//
//  xClusterApp.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import SwiftUI

@main
struct xClusterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
    var body: some Scene {
      
      //let controller = Controller()
      
        WindowGroup {
            ContentView()
              //.environmentObject(controller)
        }
//      WindowGroup("Viewer") { // other scene
//                  Viewer()
//              }
//              .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      return true
  }
}
