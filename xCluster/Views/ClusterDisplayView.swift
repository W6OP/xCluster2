//
//  ClusterDisplayView.swift
//  xCluster
//
//  Created by Peter Bourget on 7/27/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import SwiftUI

struct ClusterDisplayView: View {
  //@ObservedObject var controller: Controller
  @EnvironmentObject var controller: Controller

  var body: some View {
    // MARK: - Spot list display.

    VStack {
      ListDisplayView(controller: controller)

      StatusDisplayView(controller: controller)
    }
    .frame(maxWidth: 700, minHeight: 1000, maxHeight: .infinity)
    .padding(.vertical, 0)
  }
}

// MARK: - Cluster list display.
struct ListDisplayView: View {
  @ObservedObject var controller: Controller

  var body: some View {
    HStack {
      ScrollView {
        VStack {
          SpotHeader()
          Divider()
            .frame(maxHeight: 1)
            .padding(-5)
          ForEach(controller.displayedSpots, id: \.self) { spot in
            SpotRow(spot: spot)
          }
        }
        .frame(alignment: .topLeading)
        .background(Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
      }
    }
    //.frame(minHeight: 700, maxHeight: .infinity)
    .border(Color.gray)
  }
}

// MARK: - Spot Header

struct SpotHeader: View {
  var body: some View {

    HStack {
      Text("DX")
        .frame(minWidth: 75, maxWidth: 75)
        .border(width: 1, edges: [.trailing], color: .gray)
      Text("Frequency")
        .frame(minWidth: 90, maxWidth: 90)
        .border(width: 1, edges: [.trailing], color: .gray)
      Text("Spotter")
        .frame(minWidth: 75, maxWidth: 75)
        .border(width: 1, edges: [.trailing], color: .gray)
      Text("Time")
        .frame(minWidth: 60, maxWidth: 60)
        .border(width: 1, edges: [.trailing], color: .gray)
      Text("Comment")
        .padding(.leading, 20)
        .frame(minWidth: 200, maxWidth: 200, alignment: .leading)
        .border(width: 1, edges: [.trailing], color: .gray)
      Text("Country")
        .frame(minWidth: 120, maxWidth: 120)
    }
    .foregroundColor(Color.red)
    .font(.system(size: 14))
    .padding(0)
  }
}

// MARK: - Spot Row

struct SpotRow: View {
  var spot: ClusterSpot

  var body: some View {
    VStack {
      HStack {
        Text(spot.dxStation)
          .frame(minWidth: 75, maxWidth: 75, alignment: .leading)
          .padding(.leading, 5)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text(spot.formattedFrequency)
          .frame(minWidth: 90, maxWidth: 90, alignment: .leading)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text(spot.spotter)
          .frame(minWidth: 75, maxWidth: 75, alignment: .leading)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text(spot.timeUTC)
          .frame(minWidth: 60, maxWidth: 60, alignment: .leading)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text(spot.comment)
          .frame(minWidth: 200, maxWidth: 200, alignment: .leading)
          .padding(.leading, 5)
          .padding(.trailing, 5)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text(spot.country)
          .frame(minWidth: 120, maxWidth: 120, alignment: .leading)
          .border(width: 1, edges: [.trailing], color: .gray)
      }
      .frame(maxWidth: .infinity, maxHeight: 15)
      .padding(.leading, 5)
      .padding(.top, -5)
      .padding(.bottom, -5)

      VStack {
        Divider()
          .frame(maxHeight: 1)
          .padding(-5)
      }
      .frame(maxWidth: .infinity, maxHeight: 1)
    }
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
