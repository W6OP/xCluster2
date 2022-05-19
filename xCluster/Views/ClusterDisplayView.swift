//
//  ClusterDisplayView.swift
//  xCluster
//
//  Created by Peter Bourget on 7/27/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import SwiftUI

struct ClusterDisplayView: View {
  @EnvironmentObject var controller: Controller
  @State private var selectedTab = "Spots"
  
  var body: some View {
    // MARK: - Spot list display.
      TabView(selection: $selectedTab) {
        VStack(spacing: 0) {
          Divider()
          HStack {
            SpotHeaderView()
          }
          .frame(width: .infinity, height: 20)
          Divider()

          HStack {
            ListDisplayView(controller: controller)
          }
        }
        .background(Color("Background"))
        .onTapGesture {
          selectedTab = "Status"
        }
        .tabItem {
          Label("Spots", systemImage: "star")
        }
        .tag("Spots")
        VStack(spacing: 0) {
          Divider()
          HStack {
            StatusDisplayView(controller: controller)
          }
        }
        .background(Color("StatusDisplayView"))
        .tabItem {
          Label("Status", systemImage: "circle")
        }
        .tag("Status")
      }
    .frame(minWidth: 750, maxWidth: 750, minHeight: 1000, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Preview of ClusterDisplayView
struct ClusterDisplayView_Previews: PreviewProvider {
  static var previews: some View {
    ClusterDisplayView()
      .environmentObject(Controller())
  }
}

//extension View {
//  func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
//    overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
//  }
//}
//
//struct EdgeBorder: Shape {
//
//  var width: CGFloat
//  var edges: [Edge]
//
//  func path(in rect: CGRect) -> Path {
//    var path = Path()
//    for edge in edges {
//      var xCoordinate: CGFloat {
//        switch edge {
//        case .top, .bottom, .leading: return rect.minX
//        case .trailing: return rect.maxX - width
//        }
//      }
//
//      var yCoordinate: CGFloat {
//        switch edge {
//        case .top, .leading, .trailing: return rect.minY
//        case .bottom: return rect.maxY - width
//        }
//      }
//
//      var width: CGFloat {
//        switch edge {
//        case .top, .bottom: return rect.width
//        case .leading, .trailing: return self.width
//        }
//      }
//
//      var height: CGFloat {
//        switch edge {
//        case .top, .bottom: return self.width
//        case .leading, .trailing: return rect.height
//        }
//      }
//      path.addPath(Path(CGRect(x: xCoordinate, y: yCoordinate, width: width, height: height)))
//    }
//    return path
//  }
//}
