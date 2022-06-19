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
      ForEach(bands.indices, id: \.self) { item in
        Toggle(self.bands[item].band, isOn: self.$bands[item].isSelected.didSet { (state) in
          var bandFilterState: BandFilterState = .isOff
          if state {
            bandFilterState = BandFilterState.isOn
          }
          
          if self.bands[item].id != 0 {
            self.controller.bandFilter = (self.bands[item].id, bandFilterState) // .isOn
          } else {
            for (index, band) in bands.enumerated() where band.id != 0 {
              self.bands[index].isSelected = self.bands[0].isSelected
            }
            self.controller.bandFilter = (0, bandFilterState) // .isOff
          }
        })
        .tag(self.bands[item].id)
        .padding(.top, 5)
        .toggleStyle(SwitchToggleStyle(tint: .mint))
        Divider()
      }
    }
  }
}

struct ButtonBarView_Previews: PreviewProvider {
    static var previews: some View {
      let bands: [BandIdentifier] = bandData
      let clusters: [ClusterIdentifier] = clusterData

      ButtonBarView(controller: Controller(), clusters: clusters, bands: bands)
    }
}
