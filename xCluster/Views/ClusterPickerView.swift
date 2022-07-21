//
//  ClusterPickerView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/15/22.
//

import SwiftUI

// MARK: - Cluster Picker

struct ClusterPickerView: View {

  var controller: Controller
  var clusters: [ClusterIdentifier]
  @State private var selectedCluster = clusterData[0]

  var body: some View {
    Divider()

    HStack {
      Picker(selection: $selectedCluster.id, label: Text("")) {
        ForEach(clusters) { cluster in
          Text("\(cluster.name)")
        }
      }
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
    //.border(.green)
    Divider()
  }
}

struct ClusterPickerView_Previews: PreviewProvider {
    static var previews: some View {
      let clusters: [ClusterIdentifier] = clusterData
      ClusterPickerView(controller: Controller(), clusters: clusters)
    }
}
