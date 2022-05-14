//
//  ListDisplayView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/11/22.
//

import SwiftUI

// MARK: - Cluster list display.

struct ListDisplayView: View {
  @ObservedObject var controller: Controller
  @Environment(\.colorScheme) var currentMode
  @State private var highlighted: Int?

  var body: some View {
    ScrollView {
      VStack(spacing: 1) {
        ForEach(controller.displayedSpots, id: \.self) { spot in
          SpotRowView(spot: spot)
            .background(spot.id == highlighted ? Color(red: 141, green: 213, blue: 240) : Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
            .onTapGesture(count: 1) {
              highlighted = spot.id
              controller.formattedFrequency = spot.formattedFrequency
            }
        }
      }
      .background(currentMode == .dark ?  Color(red: 0.2, green: 0.6, blue: 0.8) : Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
    }
  }
}

// MARK: - Spot Row

struct SpotRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack(spacing: 0) {
      DXStationRowView(spot: spot)
      FrequencyRowView(spot: spot)
      SpotterRowView(spot: spot)
      TimeRowView(spot: spot)
      CommentRowView(spot: spot)
      CountryRowView(spot: spot)
    }
    //.font(.system(size: 12))
    .frame(maxHeight: 17)
    Divider()
  }
}

struct ListDisplayView_Previews: PreviewProvider {
  static var previews: some View {
    ListDisplayView(controller: Controller())
  }
}

/// Have to break out individual rows because you can't
/// have more than 10 child views in a parent view.
struct DXStationRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.dxStation)
        .padding(.leading, 5)
        .frame(width: 90, alignment: .leading)
      //.border(Color.red)
      Divider()
    }
    //.border(Color.green)
  }
}

struct FrequencyRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.formattedFrequency)
        .padding(.leading, 5)
        .frame(width: 68, alignment: .leading)
      Divider()
    }
  }
}

struct SpotterRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.spotter)
        .padding(.leading, 5)
        .frame(width: 98, alignment: .leading)
      Divider()
    }
  }
}

struct TimeRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.timeUTC)
        .frame(width: 48, alignment: .center)
      Divider()
    }
  }
}

struct CommentRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.comment)
        .padding(.leading, 5)
        .frame(width: 208, alignment: .leading)
      Divider()
    }
  }
}

struct CountryRowView: View {
  var spot: ClusterSpot

  var body: some View {
    HStack {
      Text(spot.country)
        .padding(.leading, 5)
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Dummy Cluster list display.

struct ListDisplayViewDummy: View {
  @ObservedObject var controller: Controller
  @Environment(\.colorScheme) var currentMode
  @State private var highlighted: Int?

  var body: some View {
    ScrollView {
      VStack(spacing: 1) {
        SpotRowViewDummy()
        SpotRowViewDummy()
        SpotRowViewDummy()
        SpotRowViewDummy()
      }
      .background(currentMode == .dark ?  Color(red: 0.2, green: 0.6, blue: 0.8) : Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
    }
  }
}

// MARK: - Spot Row

struct SpotRowViewDummy: View {

  var body: some View {
    HStack {
      DXStationRowViewDummy()
      FrequencyRowViewDummy()
      SpotterRowViewDummy()
      TimeRowViewDummy()
      CommentRowViewDummy()
      CountryRowViewDummy()
    }
    .font(.system(size: 12))
    .frame(maxHeight: 17)
    Divider()
  }
}

struct ListDisplayView_PreviewsDummy: PreviewProvider {
  static var previews: some View {
    ListDisplayViewDummy(controller: Controller())
  }
}

/// Have to break out individual rows because you can't
/// have more than 10 child views in a parent view.
struct DXStationRowViewDummy: View {

  var body: some View {
    HStack {
      Text("OZ50DDXG")
        .padding(.leading, 5)
        .frame(width: 90, alignment: .leading)
      //.border(Color.red)
      Divider()
    }
    //.border(Color.green)
  }
}

struct FrequencyRowViewDummy: View {

  var body: some View {
    HStack {
      Text("1144.216")
        .frame(width: 60, alignment: .leading)
      Divider()
    }
  }
}

struct SpotterRowViewDummy: View {

  var body: some View {
    HStack {
      Text("WA6YUL/KP2")
        .frame(width: 90, alignment: .leading)
      Divider()
    }
  }
}

struct TimeRowViewDummy: View {

  var body: some View {
    HStack {
      Text("1200")
        .frame(width: 40, alignment: .center)
      Divider()
    }
  }
}

struct CommentRowViewDummy: View {

  var body: some View {
    HStack {
      Text("spot.comment")
        .frame(width: 200, alignment: .leading)
      Divider()
    }
  }
}

struct CountryRowViewDummy: View {

  var body: some View {
    HStack {
      Text("spot.country")
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
      Divider()
    }
  }
}
