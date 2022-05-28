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
  @State private var highlighted: Int?

  var body: some View {
    ScrollView {
      VStack(spacing: 1) {
        ForEach(controller.displayedSpots, id: \.self) { spot in
          SpotRowView(spot: spot)
            .background(spot.id == highlighted ? Color("Hilite") : Color("Background"))
            .onTapGesture(count: 1) {
              highlighted = spot.id
              controller.formattedFrequency = spot.formattedFrequency
            }
        }
      }
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
    .frame(maxHeight: 17)
    .background(spot.isHilited ? Color("Alert") : Color("Background"))
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
      Divider()
    }
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
      Text(spot.dxCountry)
        .padding(.leading, 5)
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }
  }
}
