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

  var body: some View {
    // MARK: - Spot list display.

    VStack {
        SpotHeader()

        ListDisplayView(controller: controller)

        StatusDisplayView(controller: controller)
    }
    .frame(minWidth: 700, maxWidth: 700, minHeight: 1000, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: - Status message display.
struct StatusDisplayView: View {
  @ObservedObject var controller: Controller

  var body: some View {
    HStack {
      ScrollView {
        VStack {
          ForEach(controller.statusMessage, id: \.self) { message in
            HStack {
              Text(message)
                .padding(.leading, 2)
                .foregroundColor(Color.black)
              Spacer()
            }
            .frame(maxHeight: 15)
            .multilineTextAlignment(.leading)
          }
        }
        //.frame(minHeight: 50, maxHeight: 200, alignment: .topLeading)
        .background(Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
      }
    }
    .frame(minHeight: 50, maxHeight: 200, alignment: .topLeading)
    .border(Color.gray)
  }
}

/// Preview of ClusterDisplayView
struct ClusterDisplayView_Previews: PreviewProvider {
  static var previews: some View {
    ClusterDisplayView()
      .environmentObject(Controller())
    //ClusterDisplayView(controller: Controller())
  }
}

extension View {
  func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
    overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
  }
}

struct EdgeBorder: Shape {

  var width: CGFloat
  var edges: [Edge]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for edge in edges {
      var xCoordinate: CGFloat {
        switch edge {
        case .top, .bottom, .leading: return rect.minX
        case .trailing: return rect.maxX - width
        }
      }

      var yCoordinate: CGFloat {
        switch edge {
        case .top, .leading, .trailing: return rect.minY
        case .bottom: return rect.maxY - width
        }
      }

      var width: CGFloat {
        switch edge {
        case .top, .bottom: return rect.width
        case .leading, .trailing: return self.width
        }
      }

      var height: CGFloat {
        switch edge {
        case .top, .bottom: return self.width
        case .leading, .trailing: return rect.height
        }
      }
      path.addPath(Path(CGRect(x: xCoordinate, y: yCoordinate, width: width, height: height)))
    }
    return path
  }
}
