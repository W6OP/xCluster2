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
        VStack(spacing: 0) {
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
    VStack{
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
          .frame(minWidth: 140, maxWidth: 140, alignment: .leading)
      }
      .frame(maxHeight: 17)
    }
    .frame(minWidth: 700, minHeight: 18)
    .border(Color.gray)
  }
}

struct ListDisplayView_Previews: PreviewProvider {
    static var previews: some View {
      ListDisplayView(controller: Controller())
    }
}
