//
//  xClusterApp.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import SwiftUI

@main
struct XClusterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  let controller = Controller()

    var body: some Scene {
        WindowGroup {
          ContentView().environmentObject(controller)
        }

        WindowGroup("Spots") {
          ClusterDisplayView().environmentObject(controller)
          // ClusterDisplayView(controller: controller)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      return true
  }
}

// https://developer.apple.com/forums/thread/651592 - open external windows
//enum OpenWindows: String, CaseIterable {
//    case SecondView = "SecondView"
//    //case ThirdView   = "ThirdView"
//    //As many views as you need.
//
//    func open(){
//        if let url = URL(string: "xClusterApp://\(self.rawValue)") { //replace myapp with your app's name
//            NSWorkspace.shared.open(url)
//        }
//    }
//}
