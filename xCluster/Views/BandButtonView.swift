//
//  BandButtonView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI

struct ButtonBarView: View {
  var controller: Controller
  var clusters: [ClusterIdentifier]
  var bands: [BandIdentifier]

  var body: some View {
    HStack {
      Divider()
      ClusterPickerView(controller: controller, clusters: clusters)
      Divider()
      BandViewToggle(controller: controller, bands: bands)
    }
  }
}

// MARK: - List of band toggles

// https://stackoverflow.com/questions/60994255/swiftui-get-toggle-state-from-items-inside-a-list

/// Band filter buttons at top of display
struct BandViewToggle: View {
  @ObservedObject var controller: Controller
  @State var bands: [BandIdentifier]

  var body: some View {
    HStack {
      //Spacer()
      ForEach(bands.indices) { item in
        Toggle(self.bands[item].band, isOn: self.$bands[item].isSelected.didSet { (state) in
          if self.bands[item].id != 0 {
            self.controller.bandFilter = (self.bands[item].id, state)
          } else {
            for (index, band) in bands.enumerated() where band.id != 0 {
              self.bands[index].isSelected = self.bands[0].isSelected
            }
            self.controller.bandFilter = (0, state)
          }
        })
        .tag(self.bands[item].id)
        .padding(.top, 5)
        .toggleStyle(SwitchToggleStyle(tint: .mint))
        Divider()
      }
      Spacer()
    }
  }
}

// MARK: - Cluster Picker

struct ClusterPickerView: View {
  @State private var selectedCluster = clusterData[0]
  var controller: Controller
  var clusters: [ClusterIdentifier]
  let characterLimit = 10

  var body: some View {
    HStack {
      Picker(selection: $selectedCluster.id, label: Text("")) {
        ForEach(clusters) { cluster in
          Text("\(cluster.name)")
        }
      }
      .padding(.top, 5)
      .frame(minWidth: 200, maxWidth: 200)
      .onReceive([selectedCluster].publisher.first()) { value in
        if value.id != 9999 {
          if self.controller.connectedCluster.id != value.id {
            controller.displayedSpots = [ClusterSpot]()
            self.controller.connectedCluster = clusterData.first {$0.id == value.id}!
          }
        }
      }
    }
    .border(.green)
  }
}

struct ButtonBarView_Previews: PreviewProvider {
    static var previews: some View {
      //var controller: Controller = .environmentObject(Controller())
      let bands: [BandIdentifier] = bandData
      let clusters: [ClusterIdentifier] = clusterData

      ButtonBarView(controller: Controller(), clusters: clusters, bands: bands)
    }
}
