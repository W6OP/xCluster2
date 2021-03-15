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
  
  let controller = Controller()
  
    var body: some Scene {
        WindowGroup {
          ContentView().environmentObject(controller)
        }
      
//        WindowGroup("Status") { // other scene - this is title bar caption - must be single word
//          StatusDisplayView(controller: controller)
//        }
//        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
      
        WindowGroup("Spots") {
          ClusterDisplayView(controller: controller)
          //ListDisplayView(controller: controller)
          //StatusDisplayView(controller: controller)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      return true
  }
}
